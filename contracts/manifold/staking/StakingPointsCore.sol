// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IStakingPointsCore.sol";

/**
 * @title Staking Points Core
 * @author manifold.xyz
 * @notice Core logic for Staking Points shared extensions.
 */
abstract contract StakingPointsCore is ReentrancyGuard, ERC165, AdminControl, IStakingPointsCore {
  using Strings for uint256;

  uint256 internal constant MAX_UINT_24 = 0xffffff;
  uint256 internal constant MAX_UINT_32 = 0xffffffff;
  uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
  uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  address private constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

  // { creatorContractAddress => { instanceId => StakingPoints } }
  mapping(address => mapping(uint256 => StakingPoints)) internal _stakingPointsInstances;

  // { instanceId => { walletAddress => Staker } }
  mapping(uint256 => mapping(address => Staker)) public stakers;

  // { instanceId => { tokenAddress => StakingRule } }
  mapping(uint256 => mapping(address => StakingRule)) internal _stakingRules;

  // { walletAddress => { tokenAddress => { tokenId => StakedToken } } }
  mapping(address => mapping(address => mapping(uint256 => StakedToken))) public userStakedTokens;

  // { walletAddress => bool}
  mapping(address => bool) internal _isStakerIndexed;

  address public manifoldMembershipContract;

  address[] public stakersAddresses;

  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165, AdminControl) returns (bool) {
    return
      interfaceId == type(IStakingPointsCore).interfaceId ||
      interfaceId == type(IERC721Receiver).interfaceId ||
      // interfaceId == type(IERC1155Receiver).interfaceId ||
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
    StakingPoints storage stakingPointsInstance = _stakingPointsInstances[creatorContractAddress][instanceId];
    require(stakingPointsInstance.paymentReceiver == address(0), "StakingPoints already initialized");
    _validateStakingPointsParams(stakingPointsParams);
    stakingPointsInstance.paymentReceiver = stakingPointsParams.paymentReceiver;
    stakingPointsInstance.contractVersion = creatorContractVersion;
    require(stakingPointsParams.stakingRules.length > 0, "Needs at least one stakingRule");
    _setStakingRules(stakingPointsInstance, instanceId, stakingPointsParams.stakingRules);

    emit StakingPointsInitialized(creatorContractAddress, instanceId, msg.sender);
  }

  /**
   * Abstract helper to transfer tokens. To be implemented by inheriting contracts.
   */
  function _transfer(address contractAddress, uint256 tokenId, address fromAddress, address toAddress) internal virtual;

  /**
   * Abstract helper to transfer tokens. To be implemented by inheriting contracts.
   */
  function _transferBack(address contractAddress, uint256 tokenId, address fromAddress, address toAddress) internal virtual;

  /** STAKING */

  function stakeTokens(uint256 instanceId, StakedTokenParams[] calldata stakingTokens) external nonReentrant {
    _stakeTokens(instanceId, stakingTokens);
  }

  function _stakeTokens(uint256 instanceId, StakedTokenParams[] calldata stakingTokens) private {
    bool isIndexed = _isStakerIndexed[msg.sender];
    if (!isIndexed) {
      Staker storage newStaker = stakers[instanceId][msg.sender];
      newStaker.stakerTokenIdx = stakersAddresses.length;
      stakersAddresses.push(msg.sender);
      _isStakerIndexed[msg.sender] = true;
    }
    StakedToken[] memory newlyStaked = new StakedToken[](stakingTokens.length);
    Staker storage user = stakers[instanceId][msg.sender];
    StakedToken[] storage userTokens = user.stakersTokens;
    uint256 length = stakingTokens.length;
    for (uint256 i = 0; i < length; ) {
      StakedToken storage currToken = userStakedTokens[msg.sender][stakingTokens[i].tokenAddress][stakingTokens[i].tokenId];
      require(currToken.stakerAddress == address(0), "Token already staked");
      currToken.tokenId = stakingTokens[i].tokenId;
      currToken.contractAddress = stakingTokens[i].tokenAddress;
      currToken.stakerAddress = msg.sender;
      currToken.timeStaked = block.timestamp;
      currToken.stakerTokenIdx = userTokens.length;
      userStakedTokens[msg.sender][stakingTokens[i].tokenAddress][stakingTokens[i].tokenId] = currToken;
      userTokens.push(currToken);
      newlyStaked[i] = currToken;
      _stake(instanceId, stakingTokens[i].tokenAddress, stakingTokens[i].tokenId);
      unchecked {
        ++i;
      }
    }
    emit TokensStaked(instanceId, newlyStaked, msg.sender);
  }

  function _stake(uint256 instanceId, address tokenAddress, uint256 tokenId) private {
    StakingRule memory ruleExists = _getTokenRule(instanceId, tokenAddress);
    require(ruleExists.tokenAddress == tokenAddress, "Token does not match existing rule");

    _transfer(tokenAddress, tokenId, msg.sender, address(this));
  }

  /** UNSTAKING */
  function unstakeTokens(uint256 instanceId, StakedTokenParams[] calldata stakingTokens) external nonReentrant {
    _unstakeTokens(instanceId, stakingTokens);
  }

  function _unstakeTokens(uint256 instanceId, StakedTokenParams[] calldata stakingTokens) private {
    require(stakingTokens.length != 0, "Cannot unstake 0 tokens");

    StakedToken[] memory unstakedTokens = new StakedToken[](stakingTokens.length);
    for (uint256 i = 0; i < stakingTokens.length; ++i) {
      StakedToken storage currToken = userStakedTokens[msg.sender][stakingTokens[i].tokenAddress][stakingTokens[i].tokenId];
      require(
        msg.sender != address(0) && msg.sender == currToken.stakerAddress,
        "No sender address or not the original staker"
      );
      currToken.timeUnstaked = block.timestamp;
      stakers[instanceId][msg.sender].stakersTokens[currToken.stakerTokenIdx] = currToken;
      unstakedTokens[i] = currToken;
      _unstakeToken(stakingTokens[i].tokenAddress, stakingTokens[i].tokenId);
    }

    emit TokensUnstaked(instanceId, unstakedTokens, msg.sender);
  }

  function _unstakeToken(address tokenAddress, uint256 tokenId) private {
    StakedToken storage userToken = userStakedTokens[msg.sender][tokenAddress][tokenId];
    require(
      msg.sender != address(0) && msg.sender == userToken.stakerAddress,
      "No sender address or not the original staker"
    );
    _transferBack(tokenAddress, tokenId, address(this), msg.sender);
  }

  // function redeemPoints() external nonReentrant {
  //   // guard against more than calculated
  //   // update Staker with redeemed points
  // }

  // function _calculatePoints(address _staker, StakedToken[] stakingTokens) private view returns (uint256 memory points) {
  //   uint256 length = stakingTokens.length;
  //   for (uint256 i = 0; i < length; ) {
  //     unchecked {
  //       ++i;
  //     }
  //   }
  //   // get the tokenRule for each
  //   // get the balance from the user
  //   // add
  //   // safe multiply
  //   // check for overflow
  // }

  /** VIEW HELPERS */

  function getStakerDetails(uint256 instanceId, address staker) external view returns (Staker memory) {
    return stakers[instanceId][staker];
  }

  function _getTokenRule(uint256 instanceId, address tokenAddress) internal view returns (StakingRule memory) {
    return _stakingRules[instanceId][tokenAddress];
  }

  function getUserStakedToken(
    address wallet,
    address tokenAddress,
    uint256 tokenId
  ) external view returns (StakedToken memory) {
    return userStakedTokens[wallet][tokenAddress][tokenId];
  }

  /** HELPERS */

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
  function _getStaker(uint256 instanceId, address walletAddress) internal view returns (Staker memory staker) {
    staker = stakers[instanceId][walletAddress];
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

  function _onERC721Received(address from, uint256 id, bytes calldata data) private {}

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
    StakingPoints storage stakingPointsInstance,
    uint256 instanceId,
    StakingRule[] calldata stakingRules
  ) private {
    // delete old rules in map
    StakingRule[] memory oldRules = stakingPointsInstance.stakingRules;
    for (uint256 i; i < oldRules.length; ) {
      delete _stakingRules[instanceId][oldRules[i].tokenAddress];
    }
    delete stakingPointsInstance.stakingRules;
    StakingRule[] storage rules = stakingPointsInstance.stakingRules;
    uint256 length = stakingRules.length;
    for (uint256 i; i < length; ) {
      StakingRule memory rule = stakingRules[i];
      require(rule.tokenAddress != address(0), "Staking rule: Contract address required");
      require((rule.endTime == 0) || (rule.startTime < rule.endTime), "Staking rule: Invalid time range");
      require(rule.timeUnit > 0, "Staking rule: Invalid timeUnit");
      require(rule.pointsRate > 0, "Staking rule: Invalid points rate");
      rules.push(rule);
      _stakingRules[instanceId][rule.tokenAddress] = rule;
      unchecked {
        ++i;
      }
    }
  }
}