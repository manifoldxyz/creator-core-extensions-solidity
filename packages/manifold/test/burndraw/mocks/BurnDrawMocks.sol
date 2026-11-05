// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/// Stand-in for the Chainlink VRF v2.5 direct-funding wrapper (native payment).
/// Mirrors the real wrapper's observable behaviour that the consumer depends on:
/// price check on request, `checkPaymentMode` extraArgs check, and an exact-gas callback to
/// `rawFulfillRandomWords` whose failure is swallowed (the real one emits WrapperFulfillmentFailed).
contract MockVRFWrapper {
    uint256 public gasPrice = 30 gwei;
    uint256 public nextId = 1000;
    uint256 public lastRequestIdValue;

    struct Req {
        address consumer;
        uint32 gasLimit;
        uint32 numWords;
        bool fulfilled;
    }
    mapping(uint256 => Req) public reqs;
    uint256[] public requestIds;

    // measurement outputs of the last `fulfill`
    uint256 public lastCallbackGasUsed;
    bool public lastCallbackSuccess;
    bytes public lastCallbackRevert;

    event WrapperFulfillmentFailed(uint256 indexed requestId, address indexed consumer);

    function setGasPrice(uint256 p) external {
        gasPrice = p;
    }

    function calculateRequestPriceNative(uint32 gasLimit, uint32 numWords) public view returns (uint256) {
        // same shape as the real formula: gasPrice * (callback + overheads + perWord) * (1 + premium) + flat
        return (gasPrice * (uint256(gasLimit) + 150_000 + 5_000 * uint256(numWords)) * 160) / 100 + 1e14;
    }

    function requestRandomWordsInNative(uint32 gasLimit, uint16, uint32 numWords, bytes calldata extraArgs)
        external
        payable
        returns (uint256 id)
    {
        // checkPaymentMode(extraArgs, false): len >= 36, tag bytes, nativePayment byte [35] == 1
        require(extraArgs.length >= 36, "bad extraArgs length");
        require(bytes4(extraArgs[0:4]) == bytes4(keccak256("VRF ExtraArgsV1")), "bad tag");
        require(extraArgs[35] == 0x01, "not native");
        require(msg.value >= calculateRequestPriceNative(gasLimit, numWords), "fee too low");
        id = nextId++;
        reqs[id] = Req(msg.sender, gasLimit, numWords, false);
        requestIds.push(id);
        lastRequestIdValue = id;
    }

    function fulfill(uint256 id, uint256[] memory words) external returns (bool ok) {
        Req storage r = reqs[id];
        require(r.consumer != address(0), "request not found");
        r.fulfilled = true; // real wrapper deletes the callback record first; a second fulfil reverts there
        bytes memory data = abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", id, words);
        address c = r.consumer;
        uint256 g = r.gasLimit;
        uint256 before = gasleft();
        bytes memory ret;
        (ok, ret) = c.call{gas: g}(data);
        lastCallbackGasUsed = before - gasleft();
        lastCallbackSuccess = ok;
        lastCallbackRevert = ret;
        if (!ok) emit WrapperFulfillmentFailed(id, c);
    }

    function fulfillWord(uint256 id, uint256 word) external returns (bool) {
        uint256[] memory w = new uint256[](1);
        w[0] = word;
        return this.fulfill(id, w);
    }
}

/// Anything that can re-enter a target during a token transfer hook, once per arming.
abstract contract Attacker {
    address public atkTarget;
    bytes public atkData;
    bool public armed;
    bool public attacked;
    bool public atkSuccess;
    bytes public atkReturn;

    function arm(address target, bytes calldata data) external {
        atkTarget = target;
        atkData = data;
        armed = true;
        attacked = false;
    }

    function _fire() internal {
        if (!armed) return;
        armed = false;
        attacked = true;
        (atkSuccess, atkReturn) = atkTarget.call(atkData);
    }

    /// 4-byte selector, or the Error(string) message if the revert carried one.
    function atkReason() external view returns (string memory) {
        bytes memory r = atkReturn;
        if (r.length < 68) return "";
        bytes memory body = new bytes(r.length - 4);
        for (uint256 i; i < body.length; i++) body[i] = r[i + 4];
        return abi.decode(body, (string));
    }
}

/// ERC721 prize that re-enters during transfer. Also used to approve/own packs as an opener.
contract MalERC721 is ERC721, Attacker {
    constructor() ERC721("Mal", "MAL") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function transferFrom(address from, address to, uint256 id) public override {
        _fire();
        super.transferFrom(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id) public override {
        _fire();
        super.safeTransferFrom(from, to, id);
    }

    function approveAll(address token, address operator) external {
        (bool ok,) = token.call(abi.encodeWithSignature("setApprovalForAll(address,bool)", operator, true));
        require(ok);
    }
}

/// ERC1155 prize that re-enters during transfer.
contract MalERC1155 is ERC1155, Attacker {
    constructor() ERC1155("mal") {}

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data)
        public
        override
    {
        _fire();
        super.safeTransferFrom(from, to, id, amount, data);
    }
}

/// A prize ERC721 that lies: transferFrom does nothing.
contract LyingERC721 {
    function ownerOf(uint256) external pure returns (address) {
        return address(0xdead);
    }

    function transferFrom(address, address, uint256) external {}
}

/// A prize ERC1155 that lies: safeTransferFrom does nothing, balances report zero.
contract LyingERC1155 {
    function balanceOf(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function safeTransferFrom(address, address, uint256, uint256, bytes calldata) external {}
}

/// Contract opener whose receive hooks can be switched to reject (to test failed delivery).
contract SwitchableReceiver is IERC721Receiver, IERC1155Receiver {
    bool public accept = true;

    function setAccept(bool a) external {
        accept = a;
    }

    function callOpen(address draw, address pack, uint256 instanceId, uint256 n, uint256 value) external returns (uint256 id) {
        (bool ok, bytes memory ret) = pack.call(abi.encodeWithSignature("setApprovalForAll(address,bool)", draw, true));
        require(ok, "approve");
        bytes memory r;
        (ok, r) = draw.call{value: value}(abi.encodeWithSignature("open(address,uint256,uint256)", pack, instanceId, n));
        if (!ok) {
            assembly { revert(add(r, 0x20), mload(r)) }
        }
        ret;
        id = abi.decode(r, (uint256));
    }

    function callCancel(address draw, uint256 requestId, address to) external {
        (bool ok, bytes memory r) = draw.call(abi.encodeWithSignature("cancel(uint256,address)", requestId, to));
        if (!ok) {
            assembly { revert(add(r, 0x20), mload(r)) }
        }
    }

    function callClaimTo(address draw, uint256 requestId, address to) external {
        (bool ok, bytes memory r) = draw.call(abi.encodeWithSignature("claimTo(uint256,address)", requestId, to));
        if (!ok) {
            assembly { revert(add(r, 0x20), mload(r)) }
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        require(accept, "rejected");
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        require(accept, "rejected");
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        view
        returns (bytes4)
    {
        require(accept, "rejected");
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == type(IERC721Receiver).interfaceId || id == type(IERC1155Receiver).interfaceId
            || id == 0x01ffc9a7;
    }

    receive() external payable {}
}

/// ETH refund griefer: rejects ETH.
contract NoEthOpener {
    function callOpen(address draw, address pack, uint256 instanceId, uint256 n, uint256 value) external {
        (bool ok,) = pack.call(abi.encodeWithSignature("setApprovalForAll(address,bool)", draw, true));
        require(ok);
        bytes memory r;
        (ok, r) = draw.call{value: value}(abi.encodeWithSignature("open(address,uint256,uint256)", pack, instanceId, n));
        if (!ok) {
            assembly { revert(add(r, 0x20), mload(r)) }
        }
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == type(IERC1155Receiver).interfaceId || id == 0x01ffc9a7;
    }
}

/// Opener that re-enters the draw from its ETH refund hook (receive) once armed, and also accepts 1155s.
contract RefundReenter is Attacker {
    function callOpen(address draw, address pack, uint256 instanceId, uint256 n, uint256 value)
        external
        returns (uint256 id)
    {
        (bool ok,) = pack.call(abi.encodeWithSignature("setApprovalForAll(address,bool)", draw, true));
        require(ok, "approve");
        bytes memory r;
        (ok, r) = draw.call{value: value}(abi.encodeWithSignature("open(address,uint256,uint256)", pack, instanceId, n));
        if (!ok) {
            assembly { revert(add(r, 0x20), mload(r)) }
        }
        id = abi.decode(r, (uint256));
    }

    receive() external payable {
        _fire();
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == type(IERC1155Receiver).interfaceId || id == 0x01ffc9a7;
    }
}

/// A pack-like ERC1155 (admin = anyone in `admins`) whose `burn` can be made to revert,
/// to model a pack contract that makes fulfilment fail.
contract MockPack is ERC1155 {
    mapping(address => bool) public admins;
    bool public burnReverts;

    constructor() ERC1155("pack") {
        admins[msg.sender] = true;
    }

    function isAdmin(address a) external view returns (bool) {
        return admins[a];
    }

    function setBurnReverts(bool b) external {
        burnReverts = b;
    }

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }

    function burn(address account, uint256[] calldata ids, uint256[] calldata amounts) external {
        require(!burnReverts, "burn disabled");
        require(account == msg.sender || isApprovedForAll(account, msg.sender), "Caller is not owner or approved");
        _burnBatch(account, ids, amounts);
    }
}
