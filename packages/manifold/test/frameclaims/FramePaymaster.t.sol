// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/frameclaims/FramePaymaster.sol";
import "../../contracts/frameclaims/IFramePaymaster.sol";
import "../mocks/Mock.sol";

contract FramePaymasterTest is Test {
    FramePaymaster public paymaster;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    address public signingAddress;

    uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;

    function setUp() public {
        signingAddress = vm.addr(privateKey);

        vm.startPrank(owner);
        paymaster = new FramePaymaster();
        paymaster.setSigner(signingAddress);
        vm.stopPrank();

        vm.deal(owner, 10 ether);
        vm.deal(other, 10 ether);
        vm.deal(address(paymaster), 10 ether);
    }

    function testAccess() public {
        vm.startPrank(other);
        // Must be admin
        vm.expectRevert();
        paymaster.withdraw(payable(other), 20);
        vm.expectRevert();
        paymaster.setSigner(other);
        vm.stopPrank();
        vm.expectRevert(IFramePaymaster.InvalidSignature.selector);
        paymaster.deliver(address(0), new IFrameLazyClaim.Mint[](0));
    }

    function testWithdraw() public {
        vm.startPrank(owner);
        paymaster.withdraw(payable(other), 5 ether);
        assertEq(other.balance, 15 ether);
        vm.stopPrank();
    }

}
