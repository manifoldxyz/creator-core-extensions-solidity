// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./IERC1155BurnDraw.sol";

/// Subset of the Chainlink VRF v2.5 direct-funding wrapper (IVRFV2PlusWrapper) that this contract uses.
/// Written locally so no chainlink dependency is added.
interface IBurnDrawVRFWrapper {
    function calculateRequestPriceNative(uint32 callbackGasLimit, uint32 numWords) external view returns (uint256);

    function requestRandomWordsInNative(
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        uint32 numWords,
        bytes calldata extraArgs
    ) external payable returns (uint256 requestId);
}

/// Manifold creator-core ERC1155 burn (ERC1155CreatorCore.burn): caller must be owner or approved.
interface IBurnDrawManifold1155 {
    function burn(address account, uint256[] calldata tokenIds, uint256[] calldata amounts) external;
}

/**
 * @title ERC1155 Burn Draw
 * @notice Shared singleton extension-style contract (instances keyed by (packContract, instanceId)).
 *         A collector approves this contract for their packs, calls `open`, and after Chainlink VRF v2.5
 *         randomness lands the packs are burned and N uniformly random prize units are assigned out of the
 *         instance's deposited prize pool. Prizes are delivered by `claim`.
 *
 * Design notes
 * - Prize pool = `uint32[] slots`, each entry is an index into a per-instance `PrizeType` table (token, id, kind).
 *   Every ERC721 is one slot, every ERC1155 unit is one slot. uint32 entries pack 8 per storage word.
 * - `open` only reserves a COUNT. Concrete units are chosen in the VRF callback by swap-removing uniformly
 *   random entries from all not-yet-assigned slots. Invariant: reservedCount <= slots.length, so every pending
 *   request can always be filled (deposits only add; withdraw/deposit are blocked while any request is pending).
 * - The callback never transfers prizes. It burns the held packs (one external call to the pack contract) and
 *   records prize type ids. Delivery is `claim`.
 * - No owner, no admin keys, no protocol fee in v1.
 */
contract ERC1155BurnDraw is IERC1155BurnDraw, ERC165, IERC1155Receiver, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_PER_OPEN = 10;
    uint256 public constant REQUEST_TIMEOUT = 24 hours;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 1;

    /// Callback gas = BASE + PER_PRIZE * count. Sized from measured gas (see test `testMeasureCallbackGas`).
    uint32 public constant CALLBACK_GAS_BASE = 160_000;
    uint32 public constant CALLBACK_GAS_PER_PRIZE = 30_000;

    /// Resting value of `_expectedToken` (precompile address, can never be a token contract).
    address private constant NOT_EXPECTING = address(1);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    struct PrizeType {
        address token;
        bool is1155;
        uint256 id;
    }

    struct Instance {
        uint256 packTokenId;
        uint48 startDate;
        uint48 endDate;
        bool exists;
        bool hasOpened;
        uint32 pendingRequests;
        uint32 reservedCount;
        PrizeType[] types;
        mapping(bytes32 => uint32) typeIndexPlusOne; // ERC1155 dedupe only
        uint32[] slots; // unassigned prize units (indices into `types`)
    }

    struct Request {
        address packContract;
        uint40 requestedAt;
        uint8 count;
        Status status;
        uint16 deliveredMask;
        address opener;
        uint256 instanceId;
        uint32[] prizeTypes; // set at fulfilment
    }

    IBurnDrawVRFWrapper public immutable vrfWrapper;

    // packContract => instanceId => Instance
    mapping(address => mapping(uint256 => Instance)) private _instances;
    // VRF requestId => Request
    mapping(uint256 => Request) private _requests;

    /// The only token contract allowed to call onERC1155Received, and only inside a transfer this contract started.
    address private _expectedToken = NOT_EXPECTING;

    constructor(address vrfWrapper_) {
        if (vrfWrapper_ == address(0)) revert InvalidInput();
        vrfWrapper = IBurnDrawVRFWrapper(vrfWrapper_);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    function _validateAdmin(address packContract) internal view {
        if (!IAdminControl(packContract).isAdmin(msg.sender)) revert NotAdmin(packContract);
    }

    function _getInstance(address packContract, uint256 instanceId) internal view returns (Instance storage inst) {
        inst = _instances[packContract][instanceId];
        if (!inst.exists) revert InstanceDoesNotExist(instanceId);
    }

    function _validateDates(Params calldata params) internal pure {
        if (params.endDate != 0 && params.endDate <= params.startDate) revert InvalidInput();
    }

    /// @inheritdoc IERC1155BurnDraw
    function initialize(address packContract, uint256 instanceId, Params calldata params) external override nonReentrant {
        _validateAdmin(packContract);
        _validateDates(params);
        Instance storage inst = _instances[packContract][instanceId];
        if (inst.exists) revert InstanceAlreadyExists(instanceId);
        inst.exists = true;
        inst.packTokenId = params.packTokenId;
        inst.startDate = params.startDate;
        inst.endDate = params.endDate;
        emit InstanceInitialized(packContract, instanceId, params, msg.sender);
    }

    /// @inheritdoc IERC1155BurnDraw
    function update(address packContract, uint256 instanceId, Params calldata params) external override nonReentrant {
        _validateAdmin(packContract);
        _validateDates(params);
        Instance storage inst = _getInstance(packContract, instanceId);
        if (inst.pendingRequests != 0) revert DrawPending();
        if (inst.hasOpened && inst.packTokenId != params.packTokenId) revert PackTokenLocked();
        inst.packTokenId = params.packTokenId;
        inst.startDate = params.startDate;
        inst.endDate = params.endDate;
        emit InstanceUpdated(packContract, instanceId, params, msg.sender);
    }

    /// @inheritdoc IERC1155BurnDraw
    function depositPrizes(address packContract, uint256 instanceId, PrizeDeposit[] calldata deposits)
        external
        override
        nonReentrant
    {
        _validateAdmin(packContract);
        Instance storage inst = _getInstance(packContract, instanceId);
        // Pool composition must not change between a randomness request and its fulfilment: the random
        // words are visible in the mempool before the fulfilment lands.
        if (inst.pendingRequests != 0) revert DrawPending();
        if (deposits.length == 0) revert InvalidInput();

        for (uint256 i; i < deposits.length;) {
            PrizeDeposit calldata d = deposits[i];
            if (d.token == address(0) || d.amount == 0) revert InvalidInput();
            if (d.token == address(this)) revert InvalidInput();

            if (d.is1155) {
                uint256 beforeBal = IERC1155(d.token).balanceOf(address(this), d.id);
                _pull1155(d.token, msg.sender, d.id, d.amount);
                if (IERC1155(d.token).balanceOf(address(this), d.id) < beforeBal + d.amount) {
                    revert PrizeNotReceived(d.token, d.id);
                }
                uint32 typeId = _typeFor1155(inst, d.token, d.id);
                for (uint256 j; j < d.amount;) {
                    inst.slots.push(typeId);
                    unchecked { ++j; }
                }
            } else {
                if (d.amount != 1) revert InvalidInput();
                IERC721(d.token).transferFrom(msg.sender, address(this), d.id);
                if (IERC721(d.token).ownerOf(d.id) != address(this)) revert PrizeNotReceived(d.token, d.id);
                inst.types.push(PrizeType({token: d.token, is1155: false, id: d.id}));
                inst.slots.push(uint32(inst.types.length - 1));
            }
            emit PrizeDeposited(packContract, instanceId, d.token, d.id, d.amount, d.is1155);
            unchecked { ++i; }
        }
    }

    function _typeFor1155(Instance storage inst, address token, uint256 id) private returns (uint32) {
        bytes32 key = keccak256(abi.encode(token, id));
        uint32 idxPlusOne = inst.typeIndexPlusOne[key];
        if (idxPlusOne != 0) return idxPlusOne - 1;
        inst.types.push(PrizeType({token: token, is1155: true, id: id}));
        uint32 idx = uint32(inst.types.length - 1);
        inst.typeIndexPlusOne[key] = idx + 1;
        return idx;
    }

    /// @inheritdoc IERC1155BurnDraw
    function withdrawPrizes(address packContract, uint256 instanceId, uint256[] calldata indices, address to)
        external
        override
        nonReentrant
    {
        _validateAdmin(packContract);
        Instance storage inst = _getInstance(packContract, instanceId);
        if (to == address(0) || indices.length == 0) revert InvalidInput();
        if (inst.pendingRequests != 0) revert WithdrawLocked();
        if (!(block.timestamp < inst.startDate || (inst.endDate != 0 && block.timestamp >= inst.endDate))) {
            revert WithdrawLocked();
        }

        // Effects first: remove all slots (strictly descending indices => swap-remove never disturbs the
        // remaining indices and duplicates are impossible), remember the types to send.
        uint32[] memory removed = new uint32[](indices.length);
        uint256 prev = type(uint256).max;
        for (uint256 i; i < indices.length;) {
            uint256 idx = indices[i];
            if (idx >= prev) revert InvalidInput();
            prev = idx;
            if (idx >= inst.slots.length) revert InvalidInput();
            removed[i] = _takeSlot(inst.slots, idx);
            unchecked { ++i; }
        }
        // Interactions.
        for (uint256 i; i < removed.length;) {
            PrizeType memory t = inst.types[removed[i]];
            if (t.is1155) {
                IERC1155(t.token).safeTransferFrom(address(this), to, t.id, 1, "");
            } else {
                IERC721(t.token).safeTransferFrom(address(this), to, t.id);
            }
            emit PrizeWithdrawn(packContract, instanceId, t.token, t.id, t.is1155, to);
            unchecked { ++i; }
        }
    }

    /*//////////////////////////////////////////////////////////////
                                  OPEN
    //////////////////////////////////////////////////////////////*/

    function callbackGasLimit(uint256 count) public pure returns (uint32) {
        return CALLBACK_GAS_BASE + CALLBACK_GAS_PER_PRIZE * uint32(count);
    }

    /// @inheritdoc IERC1155BurnDraw
    function quoteOpen(uint256 count) external view override returns (uint256) {
        if (count == 0 || count > MAX_PER_OPEN) revert InvalidInput();
        return vrfWrapper.calculateRequestPriceNative(callbackGasLimit(count), NUM_WORDS);
    }

    /// @inheritdoc IERC1155BurnDraw
    function open(address packContract, uint256 instanceId, uint256 count)
        external
        payable
        override
        nonReentrant
        returns (uint256 requestId)
    {
        Instance storage inst = _getInstance(packContract, instanceId);
        if (block.timestamp < inst.startDate || (inst.endDate != 0 && block.timestamp >= inst.endDate)) {
            revert InstanceInactive(instanceId);
        }
        if (count == 0) revert InvalidInput();
        if (count > MAX_PER_OPEN) revert TooManyPerOpen(count, MAX_PER_OPEN);
        {
            uint256 available = inst.slots.length - inst.reservedCount;
            if (count > available) revert NotEnoughPrizes(count, available);
        }

        uint32 gasLimit = callbackGasLimit(count);
        uint256 price = vrfWrapper.calculateRequestPriceNative(gasLimit, NUM_WORDS);
        if (msg.value < price) revert InsufficientPayment(price, msg.value);

        // Effects: reserve a count (units are chosen at fulfilment).
        inst.reservedCount += uint32(count);
        inst.pendingRequests += 1;
        inst.hasOpened = true;

        // Pull the packs. Receipt is verified by balance delta.
        {
            uint256 packId = inst.packTokenId;
            uint256 beforeBal = IERC1155(packContract).balanceOf(address(this), packId);
            _pull1155(packContract, msg.sender, packId, count);
            if (IERC1155(packContract).balanceOf(address(this), packId) < beforeBal + count) {
                revert PrizeNotReceived(packContract, packId);
            }
        }

        // VRF v2.5 direct funding, native payment. extraArgs = VRFV2PlusClient._argsToBytes(ExtraArgsV1(true)).
        requestId = vrfWrapper.requestRandomWordsInNative{value: price}(
            gasLimit,
            REQUEST_CONFIRMATIONS,
            NUM_WORDS,
            abi.encodeWithSelector(bytes4(keccak256("VRF ExtraArgsV1")), true)
        );

        Request storage r = _requests[requestId];
        if (r.status != Status.NONE) revert InvalidInput(); // wrapper returned a reused id
        r.packContract = packContract;
        r.instanceId = instanceId;
        r.opener = msg.sender;
        r.requestedAt = uint40(block.timestamp);
        r.count = uint8(count);
        r.status = Status.PENDING;

        emit OpenRequested(requestId, packContract, instanceId, msg.sender, count, price);

        if (msg.value > price) {
            (bool ok,) = payable(msg.sender).call{value: msg.value - price}("");
            if (!ok) revert RefundFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                               FULFILMENT
    //////////////////////////////////////////////////////////////*/

    /// Called by the VRF wrapper only.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external nonReentrant {
        if (msg.sender != address(vrfWrapper)) revert NotWrapper(msg.sender);
        Request storage r = _requests[requestId];
        if (r.status != Status.PENDING) revert RequestNotPending(requestId);
        if (randomWords.length == 0) revert InvalidInput();

        Instance storage inst = _instances[r.packContract][r.instanceId];
        uint256 count = r.count;
        uint256 seed = randomWords[0];

        r.status = Status.FULFILLED;
        inst.reservedCount -= uint32(count);
        inst.pendingRequests -= 1;

        uint32[] storage slots = inst.slots;
        for (uint256 i; i < count;) {
            // invariant: reservedCount <= slots.length at request time and slots only shrink here, once per
            // reserved unit, so slots.length >= 1 for every pick.
            uint256 idx = uint256(keccak256(abi.encode(seed, i))) % slots.length;
            uint32 typeId = _takeSlot(slots, idx);
            r.prizeTypes.push(typeId);
            PrizeType storage t = inst.types[typeId];
            emit PrizeAssigned(requestId, i, t.token, t.id, t.is1155);
            unchecked { ++i; }
        }

        // Burn the held packs (pack contract is a Manifold ERC1155 creator; we hold the tokens so we burn our own balance).
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = inst.packTokenId;
        amounts[0] = count;
        IBurnDrawManifold1155(r.packContract).burn(address(this), ids, amounts);

        emit RequestFulfilled(requestId, r.packContract, r.instanceId, count);
    }

    /*//////////////////////////////////////////////////////////////
                                 CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC1155BurnDraw
    function claim(uint256 requestId) external override nonReentrant {
        _deliver(requestId, type(uint16).max, _requests[requestId].opener);
    }

    /// @inheritdoc IERC1155BurnDraw
    function claimSelected(uint256 requestId, uint16 mask) external override nonReentrant {
        _deliver(requestId, mask, _requests[requestId].opener);
    }

    /// @inheritdoc IERC1155BurnDraw
    function claimTo(uint256 requestId, address to) external override nonReentrant {
        Request storage r = _requests[requestId];
        if (msg.sender != r.opener) revert NotOpener(requestId);
        if (to == address(0)) revert InvalidInput();
        _deliver(requestId, type(uint16).max, to);
    }

    function _deliver(uint256 requestId, uint16 mask, address to) private {
        Request storage r = _requests[requestId];
        if (r.status != Status.FULFILLED) revert RequestNotFulfilled(requestId);
        Instance storage inst = _instances[r.packContract][r.instanceId];

        uint256 n = r.prizeTypes.length;
        uint16 delivered = r.deliveredMask;
        uint16 full = uint16((uint256(1) << n) - 1);

        for (uint256 i; i < n;) {
            uint16 bit = uint16(uint256(1) << i);
            if (mask & bit != 0 && delivered & bit == 0) {
                // Effects before interaction; reverted below if the transfer fails.
                delivered |= bit;
                r.deliveredMask = delivered;
                if (!_send(requestId, i, inst.types[r.prizeTypes[i]], to)) {
                    delivered &= ~bit;
                    r.deliveredMask = delivered;
                }
            }
            unchecked { ++i; }
        }

        if (delivered == full) {
            r.status = Status.CLAIMED;
            emit RequestClaimed(requestId);
        }
    }

    function _send(uint256 requestId, uint256 index, PrizeType storage t, address to) private returns (bool ok) {
        address token = t.token;
        uint256 id = t.id;
        bool is1155 = t.is1155;
        ok = is1155
            ? _tryCall(token, abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, address(this), to, id, 1, bytes("")))
            : _tryCall(token, abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(this), to, id));
        if (ok) emit PrizeDelivered(requestId, index, to, token, id, is1155);
        else emit PrizeDeliveryFailed(requestId, index, to, token, id, is1155);
    }

    /// Low-level call that ignores return data (no return-bomb copy) and reports success only.
    function _tryCall(address target, bytes memory data) private returns (bool ok) {
        assembly {
            ok := call(gas(), target, 0, add(data, 0x20), mload(data), 0, 0)
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 CANCEL
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC1155BurnDraw
    function cancel(uint256 requestId, address to) external override nonReentrant {
        Request storage r = _requests[requestId];
        if (r.status != Status.PENDING) revert RequestNotPending(requestId);
        if (msg.sender != r.opener) revert NotOpener(requestId);
        if (to == address(0)) revert InvalidInput();
        uint256 availableAt = uint256(r.requestedAt) + REQUEST_TIMEOUT;
        if (block.timestamp < availableAt) revert TimeoutNotReached(requestId, availableAt);

        Instance storage inst = _instances[r.packContract][r.instanceId];
        uint256 count = r.count;
        r.status = Status.CANCELLED;
        inst.reservedCount -= uint32(count);
        inst.pendingRequests -= 1;

        // packTokenId cannot change once an instance has been opened.
        IERC1155(r.packContract).safeTransferFrom(address(this), to, inst.packTokenId, count, "");
        emit RequestCancelled(requestId, msg.sender, to, count);
    }

    /*//////////////////////////////////////////////////////////////
                              1155 RECEIVING
    //////////////////////////////////////////////////////////////*/

    /// Pull ERC1155 units from `from` to this contract, accepting exactly the callback this call triggers.
    function _pull1155(address token, address from, uint256 id, uint256 amount) private {
        _expectedToken = token;
        IERC1155(token).safeTransferFrom(from, address(this), id, amount, "");
        _expectedToken = NOT_EXPECTING;
    }

    function onERC1155Received(address operator, address, uint256, uint256, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        if (msg.sender != _expectedToken || operator != address(this)) revert UnexpectedReceipt();
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert UnexpectedReceipt();
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function _takeSlot(uint32[] storage slots, uint256 idx) private returns (uint32 typeId) {
        uint256 last = slots.length - 1;
        typeId = slots[idx];
        if (idx != last) slots[idx] = slots[last];
        slots.pop();
    }

    /// @inheritdoc IERC1155BurnDraw
    function getInstance(address packContract, uint256 instanceId) external view override returns (InstanceInfo memory info) {
        Instance storage inst = _getInstance(packContract, instanceId);
        info.packTokenId = inst.packTokenId;
        info.startDate = inst.startDate;
        info.endDate = inst.endDate;
        info.exists = true;
        info.hasOpened = inst.hasOpened;
        info.pendingRequests = inst.pendingRequests;
        info.reservedCount = inst.reservedCount;
        info.totalSlots = inst.slots.length;
        info.availableSlots = inst.slots.length - inst.reservedCount;
    }

    /// @inheritdoc IERC1155BurnDraw
    function remainingSlots(address packContract, uint256 instanceId) external view override returns (uint256) {
        Instance storage inst = _getInstance(packContract, instanceId);
        return inst.slots.length - inst.reservedCount;
    }

    /// @inheritdoc IERC1155BurnDraw
    function getSlots(address packContract, uint256 instanceId, uint256 offset, uint256 limit)
        external
        view
        override
        returns (Slot[] memory out)
    {
        Instance storage inst = _getInstance(packContract, instanceId);
        uint256 len = inst.slots.length;
        if (offset >= len) return new Slot[](0);
        uint256 end = offset + limit;
        if (end > len) end = len;
        out = new Slot[](end - offset);
        for (uint256 i = offset; i < end;) {
            PrizeType storage t = inst.types[inst.slots[i]];
            out[i - offset] = Slot({token: t.token, is1155: t.is1155, id: t.id});
            unchecked { ++i; }
        }
    }

    /// @inheritdoc IERC1155BurnDraw
    function getRequest(uint256 requestId) external view override returns (RequestInfo memory info) {
        Request storage r = _requests[requestId];
        info.packContract = r.packContract;
        info.instanceId = r.instanceId;
        info.opener = r.opener;
        info.requestedAt = r.requestedAt;
        info.count = r.count;
        info.status = r.status;
        info.deliveredMask = r.deliveredMask;
        uint256 n = r.prizeTypes.length;
        info.prizes = new Slot[](n);
        if (n != 0) {
            Instance storage inst = _instances[r.packContract][r.instanceId];
            for (uint256 i; i < n;) {
                PrizeType storage t = inst.types[r.prizeTypes[i]];
                info.prizes[i] = Slot({token: t.token, is1155: t.is1155, id: t.id});
                unchecked { ++i; }
            }
        }
    }
}
