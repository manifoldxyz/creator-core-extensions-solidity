// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ERC1155 Burn Draw interface
 * @notice Burn a pack token (an ERC1155 token id on a Manifold creator contract) to receive
 *         randomly drawn prizes (ERC721 or ERC1155 units) that were deposited by the creator
 *         contract admin. Randomness comes from Chainlink VRF v2.5 direct funding (native).
 */
interface IERC1155BurnDraw {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct Params {
        uint256 packTokenId;
        uint48 startDate;
        uint48 endDate;
    }

    struct InstanceInfo {
        uint256 packTokenId;
        uint48 startDate;
        uint48 endDate;
        bool exists;
        bool hasOpened;
        uint32 pendingRequests; // opened but not yet fulfilled / cancelled
        uint32 reservedCount; // sum of `count` over pending requests
        uint256 totalSlots; // unassigned prize slots (reserved + available)
        uint256 availableSlots; // totalSlots - reservedCount
    }

    /// One prize unit. A deposited ERC1155 of amount N becomes N slots.
    struct Slot {
        address token;
        bool is1155;
        uint256 id;
    }

    struct PrizeDeposit {
        address token;
        uint256 id;
        uint256 amount; // ERC721: must be 1. ERC1155: number of units (each unit is one slot)
        bool is1155;
    }

    enum Status {
        NONE,
        PENDING, // randomness requested, packs held
        FULFILLED, // prizes assigned, at least one not yet delivered
        CLAIMED, // every prize delivered
        CANCELLED // timed out, packs returned
    }

    struct RequestInfo {
        address packContract;
        uint256 instanceId;
        address opener;
        uint48 requestedAt;
        uint32 count;
        Status status;
        uint16 deliveredMask; // bit i set => prizes[i] delivered
        Slot[] prizes; // empty until FULFILLED
    }

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotAdmin(address packContract);
    error InvalidInput();
    error InstanceAlreadyExists(uint256 instanceId);
    error InstanceDoesNotExist(uint256 instanceId);
    error InstanceInactive(uint256 instanceId);
    error DrawPending();
    error PackTokenLocked();
    error NotEnoughPrizes(uint256 requested, uint256 available);
    error TooManyPerOpen(uint256 requested, uint256 max);
    error InsufficientPayment(uint256 required, uint256 sent);
    error RefundFailed();
    error UnexpectedReceipt();
    error NotWrapper(address caller);
    error RequestNotPending(uint256 requestId);
    error RequestNotFulfilled(uint256 requestId);
    error NotOpener(uint256 requestId);
    error TimeoutNotReached(uint256 requestId, uint256 availableAt);
    error WithdrawLocked();
    error PrizeNotReceived(address token, uint256 id);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event InstanceInitialized(address indexed packContract, uint256 indexed instanceId, Params params, address admin);
    event InstanceUpdated(address indexed packContract, uint256 indexed instanceId, Params params, address admin);
    event PrizeDeposited(
        address indexed packContract,
        uint256 indexed instanceId,
        address indexed token,
        uint256 id,
        uint256 amount,
        bool is1155
    );
    event PrizeWithdrawn(
        address indexed packContract,
        uint256 indexed instanceId,
        address indexed token,
        uint256 id,
        bool is1155,
        address to
    );
    event OpenRequested(
        uint256 indexed requestId,
        address indexed packContract,
        uint256 indexed instanceId,
        address opener,
        uint256 count,
        uint256 vrfPaid
    );
    event PrizeAssigned(uint256 indexed requestId, uint256 index, address indexed token, uint256 id, bool is1155);
    event RequestFulfilled(uint256 indexed requestId, address indexed packContract, uint256 indexed instanceId, uint256 packsBurned);
    event PrizeDelivered(uint256 indexed requestId, uint256 index, address indexed to, address indexed token, uint256 id, bool is1155);
    event PrizeDeliveryFailed(uint256 indexed requestId, uint256 index, address indexed to, address indexed token, uint256 id, bool is1155);
    event RequestClaimed(uint256 indexed requestId);
    event RequestCancelled(uint256 indexed requestId, address indexed opener, address to, uint256 packsReturned);

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initialize(address packContract, uint256 instanceId, Params calldata params) external;

    function update(address packContract, uint256 instanceId, Params calldata params) external;

    function depositPrizes(address packContract, uint256 instanceId, PrizeDeposit[] calldata deposits) external;

    /// @param indices strictly descending indices into the unassigned slot list
    function withdrawPrizes(address packContract, uint256 instanceId, uint256[] calldata indices, address to) external;

    function open(address packContract, uint256 instanceId, uint256 count) external payable returns (uint256 requestId);

    /// Deliver every undelivered prize of a fulfilled request to its opener. Callable by anyone.
    function claim(uint256 requestId) external;

    /// Same as `claim` but only for the prizes whose bit is set in `mask` (isolates a prize that cannot be delivered).
    function claimSelected(uint256 requestId, uint16 mask) external;

    /// Opener only: deliver every undelivered prize to `to` instead of the opener.
    function claimTo(uint256 requestId, address to) external;

    /// Opener only, after REQUEST_TIMEOUT without fulfilment: return the packs to `to` and release the reservation.
    function cancel(uint256 requestId, address to) external;

    function getInstance(address packContract, uint256 instanceId) external view returns (InstanceInfo memory);

    function remainingSlots(address packContract, uint256 instanceId) external view returns (uint256);

    function getSlots(address packContract, uint256 instanceId, uint256 offset, uint256 limit) external view returns (Slot[] memory);

    function getRequest(uint256 requestId) external view returns (RequestInfo memory);

    function quoteOpen(uint256 count) external view returns (uint256);
}
