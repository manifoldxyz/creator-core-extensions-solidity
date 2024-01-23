// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/physicalclaim/PhysicalClaim.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract PhysicalClaimTest is Test {
  PhysicalClaim public example;
  ERC721Creator public creatorCore721;
  ERC1155Creator public creatorCore1155;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public other1 = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
  address public seller = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  address public zeroSigner = address(0);

  address public zeroAddress = address(0);

  address public signingAddress;
  uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;

  function setUp() public {
    vm.startPrank(owner);
    creatorCore721 = new ERC721Creator("Token721", "NFT721");
    creatorCore1155 = new ERC1155Creator("Token1155", "NFT1155");

    signingAddress = vm.addr(privateKey);
    example = new PhysicalClaim(owner, signingAddress);

    vm.deal(owner, 10 ether);
    vm.deal(other1, 10 ether);
    vm.deal(other2, 10 ether);
    vm.stopPrank();
  }

  function testAccess() public {
    vm.startPrank(other1);
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.recover(address(creatorCore721), 1, other1);
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.withdraw(payable(other1), 1 ether);
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.setMembershipAddress(other1);
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.updateSigner(address(0));
    vm.stopPrank();

    // Accidentally send token to contract
    vm.startPrank(owner);
    creatorCore721.mintBase(owner, "");
    creatorCore721.transferFrom(owner, address(example), 1);
    example.recover(address(creatorCore721), 1, owner);
    vm.stopPrank();

    // Test withdraw
    vm.deal(address(example), 10 ether);
    vm.startPrank(owner);
    example.withdraw(payable(other1), 1 ether);
    assertEq(address(example).balance, 9 ether);
    assertEq(other1.balance, 11 ether);
    vm.stopPrank();

    // Test setMembershipAddress
    vm.startPrank(owner);
    example.setMembershipAddress(other2);
    assertEq(example.manifoldMembershipContract(), other2);
    vm.stopPrank();

    // Test updateSigner
    vm.startPrank(owner);
    example.updateSigner(seller);
    vm.stopPrank();

  }

  function testSupportsInterface() public {
    vm.startPrank(owner);

    bytes4 interfaceId = type(IPhysicalClaim).interfaceId;
    assertEq(example.supportsInterface(interfaceId), true);
    assertEq(example.supportsInterface(0xffffffff), false);

    interfaceId = type(IERC721Receiver).interfaceId;
    assertEq(example.supportsInterface(interfaceId), true);

    interfaceId = type(IERC1155Receiver).interfaceId;
    assertEq(example.supportsInterface(interfaceId), true);

    interfaceId = type(AdminControl).interfaceId;
    assertEq(example.supportsInterface(interfaceId), true);

    vm.stopPrank();
  }

  function testPhysicalClaim() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
    burnTokens[0] = IPhysicalClaim.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
      burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
      amount: 1
    });

    uint256 instanceId = 100;
    uint8 variation = 2;
    uint64 variationLimit = 0;
    address erc20 = address(0);
    uint256 price = 0;
    address payable fundsRecipient = payable(address(0));
    uint160 expiration = uint160(block.timestamp + 1000);

    IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration);

    // Test redeem
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    example.burnRedeem{value: PhysicalClaim(example).BURN_FEE()}(submission);
    vm.stopPrank(); 
  }

  function constructSubmission(uint256 instanceId, IPhysicalClaim.BurnToken[] memory burnTokens, uint8 variation, uint64 variationLimit, address erc20, uint256 price, address payable fundsRecipient, uint160 expiration) public returns (IPhysicalClaim.BurnSubmission memory submission) {
    bytes memory messageData = abi.encode(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration);
    bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageData));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
    bytes memory signature = abi.encodePacked(r, s, v);

    submission.signature = signature;
    submission.message = message;
    submission.instanceId = instanceId;
    submission.burnTokens = burnTokens;
    submission.variation = variation;
    submission.variationLimit = variationLimit;
    submission.erc20 = erc20;
    submission.price = price;
    submission.fundsRecipient = fundsRecipient;
    submission.expiration = expiration;
  }

}
