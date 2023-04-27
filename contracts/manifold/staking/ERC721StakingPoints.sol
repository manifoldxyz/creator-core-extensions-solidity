// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "../../libraries/IERC721CreatorCoreVersion.sol";
import "./IERC721StakingPoints.sol";
import "./StakingPointsCore.sol";
import "./IStakingPointsCore.sol";

/**
 * @title ERC721 Staking Points
 * @author manifold.xyz
 * @notice logic for Staking Points for ERC721 extension.
 */
contract ERC721StakingPoints is StakingPointsCore, IERC721StakingPoints {
  using Strings for uint256;

  // { creatorContractAddress => { instanceId =>  bool } }
  mapping(address => mapping(uint256 => bool)) private _identicalTokenURI;

  function supportsInterface(bytes4 interfaceId) public view virtual override(StakingPointsCore, IERC165) returns (bool) {
    return interfaceId == type(IERC721StakingPoints).interfaceId || super.supportsInterface(interfaceId);
  }

  function initializeStakingPoints(
    address creatorContractAddress,
    uint256 instanceId,
    bool identicalTokenURI,
    StakingPointsParams calldata stakingPointsParams
  ) external creatorAdminRequired(creatorContractAddress) nonReentrant {
    // Max uint56 for instanceId
    require(instanceId > 0 && instanceId <= MAX_UINT_56, "Invalid instanceId");
    require(
      stakingPointsParams.storageProtocol != StorageProtocol.INVALID,
      "Cannot initialize with invalid storage protocol"
    );

    uint8 creatorContractVersion;
    try IERC721CreatorCoreVersion(creatorContractAddress).VERSION() returns (uint256 version) {
      require(version <= 255, "Unsupported contract version");
      creatorContractVersion = uint8(version);
    } catch {}

    _initialize(creatorContractAddress, creatorContractVersion, instanceId, stakingPointsParams);
    _identicalTokenURI[creatorContractAddress][instanceId] = identicalTokenURI;

    emit StakingPointsInitialized(creatorContractAddress, instanceId, msg.sender);
  }

  /**
   * See {ICreatorExtensionTokenURI-tokenURI}.
   */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {

    }

  /**
   * See {ICreatorExtensionTokenURI-updateTokenURIParams}.
   */
  function updateTokenURIParams(
    address creatorContractAddress,
    uint256 instanceId,
    StorageProtocol storageProtocol,
    string calldata location
  ) external creatorAdminRequired(creatorContractAddress) {
    StakingPoints storage stakingPoint = _stakingPointsInstances[creatorContractAddress][instanceId];
    require(stakingPoint.storageProtocol != StorageProtocol.INVALID, "Staking points not initialized");
    require(storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");

    stakingPoint.storageProtocol = storageProtocol;
    stakingPoint.location = location;
    emit StakingPointsUpdated(creatorContractAddress, instanceId);
  }

  /**
   * See {IERC721StakingPoints-updateTokenURI}
   */
  function updateTokenURI(
    address creatorContractAddress,
    uint256 instanceId,
    StorageProtocol storageProtocol,
    bool identicalTokenURI,
    string calldata location
  ) external creatorAdminRequired(creatorContractAddress) {
    StakingPoints storage stakingPointsInstance = _getStakingPointsInstance(creatorContractAddress, instanceId);
    stakingPointsInstance.storageProtocol = storageProtocol;
    stakingPointsInstance.location = location;
    _identicalTokenURI[creatorContractAddress][instanceId] = identicalTokenURI;
    emit StakingPointsUpdated(creatorContractAddress, instanceId);
  }
}
