// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
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
abstract contract StakingPointsCore is ReentrancyGuard, ERC165, AdminControl, IStakingPointsCore, ICreatorExtensionTokenURI {
  using Strings for uint256;

  string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
  string internal constant IPFS_PREFIX = "ipfs://";

  /** TODO: FEES */

  uint256 internal constant MAX_UINT_24 = 0xffffff;
  uint256 internal constant MAX_UINT_32 = 0xffffffff;
  uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
  uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  address private constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

  // { creatorContractAddress => { instanceId => StakingPoints } }
  mapping(address => mapping(uint256 => StakingPoints)) internal _stakingPointsInstances;

  address public manifoldMembershipContract;

  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165, AdminControl) returns (bool) {
    return
      interfaceId == type(IStakingPointsCore).interfaceId ||
      interfaceId == type(IERC721Receiver).interfaceId ||
      // interfaceId == type(IERC1155Receiver).interfaceId ||
      interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
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
    require(stakingPointsInstance.storageProtocol == StorageProtocol.INVALID, "StakingPoints already initialized");
    _validateStakingPointsParams(stakingPointsParams);
    stakingPointsInstance.paymentReceiver = stakingPointsParams.paymentReceiver;
    stakingPointsInstance.storageProtocol = stakingPointsParams.storageProtocol;
    stakingPointsInstance.contractVersion = creatorContractVersion;
    stakingPointsInstance.location = stakingPointsParams.location;
    require(stakingPointsParams.stakingRules.length > 0, "Needs at least one stakingRule");
    _setStakingRules(stakingPointsInstance, stakingPointsParams.stakingRules);

    emit StakingPointsInitialized(creatorContractAddress, instanceId, msg.sender);
  }

  /** VIEW */

  // function getTotalPoints() {}

  // function getStakedToken() {}

  /** STAKING */

  function stakeTokens() external nonReentrant {
    // TODO
    // emit TokensStaked()
  }

  function _stake(address _tokenAddress, uint256 _tokenId) internal {
    // TODO
  }

  /** UNSTAKING */
  function unstakeTokens() external nonReentrant {
    // TODO
    // emit TokensUnstaked()
  }

  function _unstake(address _user, uint256 _tokenId) internal {
    // TODO
  }

  function updateTokenURI() public view virtual {}

  /** HELPERS */

  /**
   * See {IStakingPointsCore-getStakingPointsInstance}.
   */
  function getStakingPointsInstance(
    address creatorContractAddress,
    uint256 instanceId
  ) external view override returns (StakingPoints memory) {
    return _getStakingPointsInstance(creatorContractAddress, instanceId);
  }

  /**
   * Helper to get staking points instance
   */
  function _getStakingPointsInstance(
    address creatorContractAddress,
    uint256 instanceId
  ) internal view returns (StakingPoints storage stakingPointsInstance) {
    stakingPointsInstance = _stakingPointsInstances[creatorContractAddress][instanceId];
    require(stakingPointsInstance.storageProtocol != StorageProtocol.INVALID, "Staking points not initialized");
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
    require(stakingPointsParams.storageProtocol != StorageProtocol.INVALID, "Storage protocol invalid");
    require(stakingPointsParams.paymentReceiver != address(0), "Payment receiver required");
  }

  function _setStakingRules(StakingPoints storage stakingPointsInstance, StakingRule[] calldata stakingRules) private {
    delete stakingPointsInstance.stakingRules;
    StakingRule[] storage rules = stakingPointsInstance.stakingRules;
    for (uint256 i; i < stakingRules.length; ) {
      StakingRule memory rule = stakingRules[i];
      require(rule.tokenAddress != address(0), "Staking rule: Contract address required");
      require(rule.tokenSpec == TokenSpec.ERC721, "Staking rule: Only supports ERC721 at this time");
      require((rule.endTime == 0) || (rule.startTime < rule.endTime), "Staking rule: Invalid time range");
      require(rule.timeUnit > 0, "Staking rule: Invalid timeUnit");
      require(rule.pointsRate > 0, "Staking rule: Invalid points rate");
      rules.push(rule);
      unchecked {
        ++i;
      }
    }
  }
}
