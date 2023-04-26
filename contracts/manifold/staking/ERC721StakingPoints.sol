// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "../../libraries/IERC721CreatorCoreVersion.sol";
import "./IERC721StakingPoints.sol";
import "./StakingPoints.sol";

contract ERC721StakingPoints is StakingPoints, IERC721StakingPoints {
  using Strings for uint256;

  // { creatorContractAddress => { instanceId =>  bool } }
  mapping(address => mapping(uint256 => bool)) private _identicalTokenURI;

  function supportsInterface(bytes4 interfaceId) public view virtual override(StakingPoints, IERC165) returns (bool) {
    return interfaceId == type(IERC721StakingPoints).interfaceId || super.supportsInterface(interfaceId);
  }

  function initializeStakingPoints(
    address creatorContractAddress,
    uint256 instanceId,
    bool identicalTokenURI,
    StakingPointsParams calldata stakingPointsParams
  ) external override creatorAdminRequired(creatorContractAddress) {
    // Max uint56 for instanceId
    require(instanceId > 0 && instanceId <= MAX_UINT_56, "Invalid instanceId");
    // Revert if StakingPoints at instanceId already exists
    StakingPoints storage instance = _getStakingPointsInstance(creatorContractAddress, instanceId);
    require(instance.storageProtocol == StorageProtocol.INVALID, "StakingPoints already initialized");
    require(
      stakingPointsParams.storageProtocol != StorageProtocol.INVALID,
      "Cannot initialize with invalid storage protocol"
    );

    uint8 creatorContractVersion;
    try IERC721CreatorCoreVersion(creatorContractAddress).VERSION() returns (uint256 version) {
      require(version <= 255, "Unsupported contract version");
      creatorContractVersion = uint8(version);
    } catch {}

    //
    _initialize(creatorContractAddress, creatorContractVersion, instanceId, stakingPointsParams);
    _identicalTokenURI[creatorContractAddress][instanceId] = identicalTokenURI;

    emit StakingPointsInitialized(creatorContractAddress, instanceId, msg.sender);
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
  ) external override creatorAdminRequired(creatorContractAddress) {
    StakingPoints storage stakingPointsInstance = _getStakingPointsInstance(creatorContractAddress, instanceId);
    stakingPointsInstance.storageProtocol = storageProtocol;
    stakingPointsInstance.location = location;
    _identicalTokenURI[creatorContractAddress][instanceId] = identicalTokenURI;
    emit StakingPointsUpdated(creatorContractAddress, instanceId);
  }
}
