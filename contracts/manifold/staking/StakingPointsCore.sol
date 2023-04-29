// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./IStakingPointsCore.sol";

/**
 * @title Staking Points Core
 * @author manifold.xyz
 * @notice Core logic for Staking Points shared extensions. Currently only handles ERC721, next steps could include
 * implementing batch fns, ERC1155 support, using a ERC20 token to represent points, and explore more point dynamics
 */
abstract contract StakingPointsCore is ReentrancyGuard, ERC165, AdminControl, IStakingPointsCore {
  using SafeMath for uint256;
  uint256 internal constant MAX_UINT_24 = 0xffffff;
  uint256 internal constant MAX_UINT_32 = 0xffffffff;
  uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
  uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  address private constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

  // { creatorContractAddress => { instanceId => StakingPoints } }
  mapping(address => mapping(uint256 => StakingPoints)) internal _stakingPointsInstances;

  // { creatorContractAddress => { instanceId => { walletAddress => stakerIdx } } }
  mapping(address => mapping(uint256 => mapping(address => uint256))) internal _stakerIdxs;

  // { creatorContractAddress => {  instanceId => { tokenAddress => ruleIdx } } }
  mapping(address => mapping(uint256 => mapping(address => uint256))) internal _stakingRulesIdxs;

  // { walletAddress => { tokenAddress => { tokenId => StakedTokenIdx } } }
  mapping(address => mapping(address => mapping(uint256 => StakedTokenIdx))) internal _stakedTokenIdxs;

  // { creatorContractAddress => {instanceId => { walletAddress => bool } } }
  mapping(address => mapping(uint256 => mapping(address => bool))) internal _isStakerIndexed;

  address public manifoldMembershipContract;

  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165, AdminControl) returns (bool) {
    return
      interfaceId == type(IStakingPointsCore).interfaceId ||
      interfaceId == type(IERC721Receiver).interfaceId ||
      super.supportsInterface(interfaceId);
  }

  /**
   * @notice This extension is shared, not single-creator. So we must ensure
   * that a staking points's initializer is an admin on the creator contract
   * @param creatorContractAddress    the address of the creator contract to check the admin against
   */
  modifier creatorAdminRequired(address creatorContractAddress) {
    require(IAdminControl(creatorContractAddress).isAdmin(msg.sender), "Wallet is not an admin");
    _;
  }

  /**
   * Initialiazes a StakingPoints with base parameters
   */
  function _initialize(
    address creatorContractAddress,
    uint8 creatorContractVersion,
    uint256 instanceId,
    StakingPointsParams calldata stakingPointsParams
  ) internal {
    _update(creatorContractAddress, creatorContractVersion, instanceId, stakingPointsParams);
  }

  /**
   * Updates a stakingPionts with params
   */
  function _update(
    address creatorContractAddress,
    uint8 creatorContractVersion,
    uint256 instanceId,
    StakingPointsParams calldata stakingPointsParams
  ) internal {
    StakingPoints storage instance = _stakingPointsInstances[creatorContractAddress][instanceId];
    _validateStakingPointsParams(stakingPointsParams);
    instance.paymentReceiver = stakingPointsParams.paymentReceiver;
    instance.contractVersion = creatorContractVersion;
    require(stakingPointsParams.stakingRules.length > 0, "Needs at least one stakingRule");
    _setStakingRules(creatorContractAddress, instance, instanceId, stakingPointsParams.stakingRules);
  }

  /**
   * Abstract helper to transfer tokens. To be implemented by inheriting contracts.
   */
  function _transfer(address contractAddress, uint256 tokenId, address fromAddress, address toAddress) internal virtual;

  /**
   * Abstract helper to transfer tokens. To be implemented by inheriting contracts.
   */
  function _transferBack(address contractAddress, uint256 tokenId, address fromAddress, address toAddress) internal virtual;

  /**
   * Abstract helper to redeem points. To be implemented by inheriting contracts.
   */
  function _redeem(
    address creatorContractAddress,
    uint256 instanceId,
    uint256 pointsAmount
  ) internal virtual;

  /** STAKING */

  function stakeTokens(
    address creatorContractAddress,
    uint256 instanceId,
    StakedTokenParams[] calldata stakingTokens
  ) external nonReentrant {
    _stakeTokens(creatorContractAddress, instanceId, stakingTokens);
  }

  function _stakeTokens(
    address creatorContractAddress,
    uint256 instanceId,
    StakedTokenParams[] calldata stakingTokens
  ) private {
    // get instance
    StakingPoints storage instance = _getStakingPointsInstance(creatorContractAddress, instanceId);
    bool isIndexed = _isStakerIndexed[creatorContractAddress][instanceId][msg.sender];
    if (!isIndexed) {
      uint256 newStakerIdx = instance.stakers.length;
      instance.stakers.push();
      instance.stakers[newStakerIdx].stakerIdx = newStakerIdx;
      // add staker to index map
      _stakerIdxs[creatorContractAddress][instanceId][msg.sender] = newStakerIdx;
      _isStakerIndexed[creatorContractAddress][instanceId][msg.sender] = true;
    }

    StakedToken[] memory newlyStaked = new StakedToken[](stakingTokens.length);
    uint256 stakerIdx = _getStakerIdx(creatorContractAddress, instanceId, msg.sender);
    StakedToken[] storage userTokens = instance.stakers[stakerIdx].stakersTokens;
    uint256 length = stakingTokens.length;
    for (uint256 i = 0; i < length; ) {
      StakedTokenIdx storage currStakedTokenIdx = _stakedTokenIdxs[msg.sender][stakingTokens[i].tokenAddress][
        stakingTokens[i].tokenId
      ];
      require(currStakedTokenIdx.stakerAddress == address(0), "Token already staked");
      StakedToken memory currToken;
      currToken.tokenId = stakingTokens[i].tokenId;
      currToken.contractAddress = stakingTokens[i].tokenAddress;
      currToken.stakerAddress = msg.sender;
      currToken.timeStaked = block.timestamp;
      currToken.tokenIdx = userTokens.length;

      _stakedTokenIdxs[msg.sender][stakingTokens[i].tokenAddress][stakingTokens[i].tokenId] = StakedTokenIdx(
        currToken.tokenIdx,
        msg.sender
      );
      userTokens.push(currToken);
      newlyStaked[i] = currToken;

      _stake(creatorContractAddress, instanceId, instance, stakingTokens[i].tokenAddress, stakingTokens[i].tokenId);
      unchecked {
        ++i;
      }
    }
    emit TokensStaked(creatorContractAddress, instanceId, newlyStaked, msg.sender);
  }

  function _stake(
    address creatorContractAddress,
    uint256 instanceId,
    StakingPoints storage stakingPointsInstance,
    address tokenAddress,
    uint256 tokenId
  ) private {
    StakingRule memory ruleExists = _getTokenRule(creatorContractAddress, instanceId, stakingPointsInstance, tokenAddress);
    require(ruleExists.tokenAddress == tokenAddress, "Token does not match existing rule");

    _transfer(tokenAddress, tokenId, msg.sender, address(this));
  }

  /** UNSTAKING */

  function unstakeTokens(
    address creatorContractAddress,
    uint256 instanceId,
    StakedTokenParams[] calldata unstakingTokens
  ) external nonReentrant {
    _unstakeTokens(creatorContractAddress, instanceId, unstakingTokens);
  }

  function _unstakeTokens(
    address creatorContractAddress,
    uint256 instanceId,
    StakedTokenParams[] calldata unstakingTokens
  ) private {
    require(unstakingTokens.length != 0, "Cannot unstake 0 tokens");

    StakingPoints storage instance = _getStakingPointsInstance(creatorContractAddress, instanceId);
    StakedToken[] memory unstakedTokens = new StakedToken[](unstakingTokens.length);
    uint256 stakerIdx = _getStakerIdx(creatorContractAddress, instanceId, msg.sender);

    for (uint256 i = 0; i < unstakingTokens.length; ++i) {
      StakedTokenIdx storage currStakedTokenIdx = _stakedTokenIdxs[msg.sender][unstakingTokens[i].tokenAddress][
        unstakingTokens[i].tokenId
      ];
      StakedToken storage currToken = instance.stakers[stakerIdx].stakersTokens[currStakedTokenIdx.tokenIdx];
      require(
        msg.sender != address(0) && msg.sender == currToken.stakerAddress,
        "No sender address or not the original staker"
      );
      currToken.timeUnstaked = block.timestamp;
      delete _stakedTokenIdxs[msg.sender][unstakingTokens[i].tokenAddress][unstakingTokens[i].tokenId];
      unstakedTokens[i] = currToken;
      _unstakeToken(unstakingTokens[i].tokenAddress, unstakingTokens[i].tokenId);
    }

    // add redeem functionality if staker has not redeemed past qualifying amount for unstaking tokens
    // ensure that staker is coming from right place
    Staker storage staker = instance.stakers[stakerIdx];
    uint256 totalUnstakingTokensPoints = _calculateTotalQualifyingPoints(creatorContractAddress, instanceId, unstakedTokens);
    uint256 diffRedeemed = totalUnstakingTokensPoints - staker.pointsRedeemed;

    if (diffRedeemed > 0) {
      _redeemPointsAmount(creatorContractAddress, instanceId, diffRedeemed);
    }
    emit TokensUnstaked(creatorContractAddress, instanceId, unstakedTokens, msg.sender);
  }

  /**
   * @dev assumes that fn that calls protects against sender not matching original owner
   */
  function _unstakeToken(address tokenAddress, uint256 tokenId) private {
    _transferBack(tokenAddress, tokenId, address(this), msg.sender);
  }

  function redeemPoints(address creatorContractAddress, uint256 instanceId) external nonReentrant {
    _redeemPoints(creatorContractAddress, instanceId);
  }

  function _redeemPoints(address creatorContractAddress, uint256 instanceId) private {
    StakingPoints storage instance = _getStakingPointsInstance(creatorContractAddress, instanceId);
    uint256 stakerIdx = _getStakerIdx(creatorContractAddress, instanceId, msg.sender);

    Staker storage staker = instance.stakers[stakerIdx];
    uint256 totalQualifyingPoints = _calculateTotalQualifyingPoints(
      creatorContractAddress,
      instanceId,
      staker.stakersTokens
    );
    uint256 diff = totalQualifyingPoints - staker.pointsRedeemed;
    require(totalQualifyingPoints != 0 && diff >= 0, "Need more than zero points");
    // compare with pointsRedeemd
    staker.pointsRedeemed = totalQualifyingPoints;
    _redeem(creatorContractAddress, instanceId, diff);
    emit PointsDistributed(creatorContractAddress, instanceId, msg.sender, diff);
  }

  /**
   * @dev assumes that the sender is qualified to redeem amount and not in excess of points already redeemed
   */
  function _redeemPointsAmount(address creatorContractAddress, uint256 instanceId, uint256 amount) private {
    _redeem(creatorContractAddress, instanceId, amount);
    emit PointsDistributed(creatorContractAddress, instanceId, msg.sender, amount);
  }

  function getPointsForWallet(
    address creatorContractAddress,
    uint256 instanceId,
    address walletAddress
  ) external view returns (uint256 totalPoints, uint256 diff) {
    return _getPointsForWallet(creatorContractAddress, instanceId, walletAddress);
  }

  function _getPointsForWallet(
    address creatorContractAddress,
    uint256 instanceId,
    address walletAddress
  ) private view returns (uint256 totalPoints, uint256 diff) {
    StakingPoints storage instance = _getStakingPointsInstance(creatorContractAddress, instanceId);
    uint256 stakerIdx = _getStakerIdx(creatorContractAddress, instanceId, walletAddress);
    Staker storage staker = instance.stakers[stakerIdx];
    totalPoints = _calculateTotalQualifyingPoints(creatorContractAddress, instanceId, staker.stakersTokens);
    diff = totalPoints - staker.pointsRedeemed;
  }

  /**
   * @notice assumes points
   */
  function _calculateTotalQualifyingPoints(
    address creatorContractAddress,
    uint256 instanceId,
    StakedToken[] memory stakingTokens
  ) private view returns (uint256 points) {
    uint256 length = stakingTokens.length;
    StakingPoints storage instance = _getStakingPointsInstance(creatorContractAddress, instanceId);
    StakingRule[] storage rules = instance.stakingRules;
    for (uint256 i = 0; i < length; ) {
      uint256 ruleIdx = _stakingRulesIdxs[creatorContractAddress][instanceId][stakingTokens[i].contractAddress];
      StakingRule storage rule = rules[ruleIdx];
      require(rule.startTime >= 0 && rule.endTime >= 0, "Invalid rule values");
      uint256 tokenEnd = stakingTokens[i].timeUnstaked == 0 ? block.timestamp : stakingTokens[i].timeUnstaked;
      uint256 start = Math.max(rule.startTime, stakingTokens[i].timeStaked);
      uint256 end = Math.min(tokenEnd, rule.endTime);
      uint256 diff = start - end;
      uint256 qualified = _calculateTotalPoints(diff, rule.pointsRatePerDay, 86400);
      points = points + qualified;

      unchecked {
        ++i;
      }
    }
  }

  /** VIEW HELPERS */

  function getStaker(
    address creatorContractAddress,
    uint256 instanceId,
    address stakerAddress
  ) external view returns (Staker memory) {
    uint256 stakerIdx = _getStakerIdx(creatorContractAddress, instanceId, stakerAddress);
    StakingPoints storage instance = _getStakingPointsInstance(creatorContractAddress, instanceId);
    return instance.stakers[stakerIdx];
  }

  function _getTokenRule(
    address creatorContractAddress,
    uint256 instanceId,
    StakingPoints storage stakingPointsInstance,
    address tokenAddress
  ) internal view returns (StakingRule memory) {
    uint256 ruleIdx = _stakingRulesIdxs[creatorContractAddress][instanceId][tokenAddress];
    return stakingPointsInstance.stakingRules[ruleIdx];
  }

  /**
   * See {IStakingPointsCore-getStakingPointsInstance}.
   */
  function getStakingPointsInstance(
    address creatorContractAddress,
    uint256 instanceId
  ) external view override returns (StakingPoints memory _stakingPoints) {
    _stakingPoints = _getStakingPointsInstance(creatorContractAddress, instanceId);
  }

  /**
   * Helper to get Staker
   */
  function _getStakerIdx(
    address creatorContractAddress,
    uint256 instanceId,
    address walletAddress
  ) internal view returns (uint256) {
    return _stakerIdxs[creatorContractAddress][instanceId][walletAddress];
  }

  /**
   * Helper to get staking points instance
   */
  function _getStakingPointsInstance(
    address creatorContractAddress,
    uint256 instanceId
  ) internal view returns (StakingPoints storage stakingPointsInstance) {
    stakingPointsInstance = _stakingPointsInstances[creatorContractAddress][instanceId];
    require(stakingPointsInstance.paymentReceiver != address(0), "Staking points not initialized");
  }

  /** HELPERS */

  function _calculateTotalPoints(uint256 diff, uint256 rate, uint256 div) private pure returns (uint256) {
    return (diff * rate) / div;
  }

  /**
   * @dev See {IStakingPointsCore-recoverERC721}.
   */
  function recoverERC721(address tokenAddress, uint256 tokenId, address destination) external override adminRequired {
    IERC721(tokenAddress).transferFrom(address(this), destination, tokenId);
  }

  /**
   * @dev See {IERC721Receiver-onERC721Received}.
   */
  function onERC721Received(
    address,
    address from,
    uint256 id,
    bytes calldata data
  ) external override nonReentrant returns (bytes4) {
    _onERC721Received(from, id, data);
    return this.onERC721Received.selector;
  }

  function _onERC721Received(address from, uint256 id, bytes calldata data) private {
    /** TODO attempt to stake */
  }

  /**
   * @dev See {IstakingPointsCore-setManifoldMembership}.
   */
  function setMembershipAddress(address addr) external override adminRequired {
    manifoldMembershipContract = addr;
  }

  function _validateStakingPointsParams(StakingPointsParams calldata stakingPointsParams) internal pure {
    require(stakingPointsParams.paymentReceiver != address(0), "Payment receiver required");
  }

  function _setStakingRules(
    address creatorContractAddress,
    StakingPoints storage stakingPointsInstance,
    uint256 instanceId,
    StakingRule[] calldata newStakingRules
  ) private {
    StakingRule[] memory oldRules = stakingPointsInstance.stakingRules;
    uint256 oldLength = oldRules.length;
    for (uint256 i; i < oldLength; ) {
      delete _stakingRulesIdxs[creatorContractAddress][instanceId][oldRules[i].tokenAddress];
      unchecked {
        ++i;
      }
    }
    delete stakingPointsInstance.stakingRules;
    StakingRule[] storage rules = stakingPointsInstance.stakingRules;
    uint256 length = newStakingRules.length;
    for (uint256 i; i < length; ) {
      StakingRule memory rule = newStakingRules[i];
      require(rule.tokenAddress != address(0), "Staking rule: Contract address required");
      require((rule.endTime == 0) || (rule.startTime < rule.endTime), "Staking rule: Invalid time range");
      require(rule.pointsRatePerDay > 0, "Staking rule: Invalid points rate");
      _stakingRulesIdxs[creatorContractAddress][instanceId][rule.tokenAddress] = rules.length;
      rules.push(rule);
      unchecked {
        ++i;
      }
    }
  }
}
