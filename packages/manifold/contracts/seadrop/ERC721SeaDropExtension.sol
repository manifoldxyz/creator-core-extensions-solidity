// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct PublicDrop {
  uint80 mintPrice;
  uint48 startTime;
  uint48 endTime;
  uint16 maxTotalMintableByWallet;
  uint16 feeBps;
  bool restrictFeeRecipients;
}

interface ISeaDrop {
  function updatePublicDrop(PublicDrop calldata publicDrop) external;

  function updateCreatorPayoutAddress(address payoutAddress) external;

  function mintPublic(
    address nftContract,
    address feeRecipient,
    address minterIfNotPayer,
    uint256 quantity
  ) external payable;

  function getPublicDrop(address nftContract) external view returns (PublicDrop memory);
}

interface IERC721CreatorContract {
  function mintExtension(address to) external returns (uint256);
}

contract ERC721SeaDropExtension {
  address public creatorContractAddress;
  uint256 public maxSupply = 10000;
  uint256 public currentTotalSupply = 0;

  mapping(address => uint256) private minterNumMinted;

  event SeaDropTokenDeployed();

  constructor(address _creatorContractAddress) {
    creatorContractAddress = _creatorContractAddress;

    emit SeaDropTokenDeployed();
  }

  function updatePublicDrop(address seaDropImpl, PublicDrop calldata publicDrop) external {
    ISeaDrop(seaDropImpl).updatePublicDrop(publicDrop);
  }

  function updateCreatorPayoutAddress(address seaDropImpl, address payoutAddress) external {
    ISeaDrop(seaDropImpl).updateCreatorPayoutAddress(payoutAddress);
  }

  function mintSeaDrop(address minter, uint256 quantity) external {
    for (uint256 i = 0; i < quantity; i++) {
      IERC721CreatorContract(creatorContractAddress).mintExtension(minter);
    }
    minterNumMinted[minter] += quantity;
    currentTotalSupply += quantity;
  }

  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return interfaceId == 0x1890fe8e; // hack: don't want to implement all functions right now
  }

  function getMintStats(address minter) external view returns (uint256, uint256, uint256) {
    return (minterNumMinted[minter], currentTotalSupply, maxSupply);
  }
}
