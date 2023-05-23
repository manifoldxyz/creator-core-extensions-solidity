const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator');
const ERC1155Soulbound = artifacts.require('ERC1155Soulbound');
const keccak256 = require('keccak256');
const ethers = require('ethers');

contract('Soulbound1155', function ([...accounts]) {
  const [owner, anotherOwner, anyone1, anyone2] = accounts;
  describe('Soulbound1155', function () {
    let creator, soulbound;
    beforeEach(async function () {
      creator = await ERC1155Creator.new("Test", "TEST", {from:owner});
      soulbound = await ERC1155Soulbound.new({from:owner});
      
      // Must register with empty prefix in order to set per-token uri's
      await creator.registerExtension(soulbound.address, {from:owner});
    });


    it('access test', async function () {
      await truffleAssert.reverts(soulbound.setApproveTransfer(creator.address, true, {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.configureContract(creator.address, true, true, "", {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.methods['configureToken(address,uint256,bool,bool)'](creator.address, 1, true, true, {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.methods['configureToken(address,uint256[],bool,bool)'](creator.address, [1], true, true, {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.mintNewToken(creator.address, [anyone1], [1], [""], {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.mintExistingToken(creator.address, [anyone1], [1], [1], {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.methods['setTokenURI(address,uint256,string)'](creator.address, 1, "", {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.methods['setTokenURI(address,uint256[],string[])'](creator.address, [1], [""], {from: anotherOwner}), "Must be owner or admin")
    });

    it('functionality test', async function () {
      await soulbound.mintNewToken(creator.address, [anyone1], [1], ["token1"], {from:owner})
      await soulbound.mintNewToken(creator.address, [anyone1], [1], ["token2"], {from:owner})
      await soulbound.mintNewToken(creator.address, [anyone1], [1], ["token3"], {from:owner})
      await soulbound.mintNewToken(creator.address, [anyone1], [1], ["token4"], {from:owner})

      // Default soulbound but burnable
      await truffleAssert.reverts(creator.safeTransferFrom(anyone1, anyone2, 1, 1, "0x0", {from:anyone1}), "Extension approval failure")
      await truffleAssert.reverts(creator.safeBatchTransferFrom(anyone1, anyone2, [1], [1], "0x0", {from:anyone1}), "Extension approval failure")
      await creator.burn(anyone1, [1], [1], {from:anyone1})

      // Make non-burnable at token level
      await soulbound.methods['configureToken(address,uint256,bool,bool)'](creator.address, 2, true, false, {from:owner});
      await truffleAssert.reverts(creator.burn(anyone1, [2], [1], {from:anyone1}), "Extension approval failure")
      await creator.burn(anyone1, [3], [1], {from:anyone1})

      // Make non-burnable at contract level
      await soulbound.configureContract(creator.address, true, false, "", {from:owner});
      await truffleAssert.reverts(creator.burn(anyone1, [4], [1], {from:anyone1}), "Extension approval failure")

      // Make specific token burnable at token level, still cannot burn because restrction exists at the contract level
      await soulbound.methods['configureToken(address,uint256[],bool,bool)'](creator.address, [2], true, true, {from:owner});
      await truffleAssert.reverts(creator.burn(anyone1, [2], [1], {from:anyone1}), "Extension approval failure")

      // Make non-soulbound at token level
      await soulbound.methods['configureToken(address,uint256[],bool,bool)'](creator.address, [2], false, false, {from:owner});
      await truffleAssert.reverts(creator.safeBatchTransferFrom(anyone1, anyone2, [2,4], [1,1], "0x0", {from:anyone1}), "Extension approval failure")
      await creator.safeTransferFrom(anyone1, anyone2, 2, 1, "0x0", {from:anyone1});
      await creator.safeBatchTransferFrom(anyone2, anyone1, [2], [1], "0x0", {from:anyone2});
      await truffleAssert.reverts(creator.safeTransferFrom(anyone1, anyone2, 4, 1, "0x0", {from:anyone1}), "Extension approval failure")
      await truffleAssert.reverts(creator.safeBatchTransferFrom(anyone1, anyone2, [4], [1], "0x0", {from:anyone1}), "Extension approval failure")

      // Make non-soulbound at contract level
      await soulbound.configureContract(creator.address, false, false, "", {from:owner});
      await creator.safeTransferFrom(anyone1, anyone2, 4, 1, "0x0", {from:anyone1});
      await creator.safeBatchTransferFrom(anyone2, anyone1, [4], [1], "0x0", {from:anyone2});

      // Make soulbound at token level, transfers allowed because it's still not soulbound at contract level
      await soulbound.methods['configureToken(address,uint256[],bool,bool)'](creator.address, [2,4], true, false, {from:owner});
      await creator.safeTransferFrom(anyone1, anyone2, 2, 1, "0x0", {from:anyone1});
      await creator.safeBatchTransferFrom(anyone1, anyone2, [4], [1], "0x0", {from:anyone1});
    
      // Make soulbound at contract level
      await soulbound.configureContract(creator.address, true, true, "", {from:owner});
      await truffleAssert.reverts(creator.safeTransferFrom(anyone1, anyone2, 4, 1, "0x0", {from:anyone1}), "Extension approval failure")
      await truffleAssert.reverts(creator.safeBatchTransferFrom(anyone1, anyone2, [4], [1], "0x0", {from:anyone1}), "Extension approval failure")

      // Disable extension
      await soulbound.setApproveTransfer(creator.address, false, {from: owner});
      // No longer enforcing soulbound
      await creator.safeTransferFrom(anyone2, anyone1, 2, 1, "0x0", {from:anyone2});
      await creator.safeBatchTransferFrom(anyone2, anyone1, [4], [1], "0x0", {from:anyone2});

      // Check URIs
      assert.equal(await creator.uri(2), "token2")
      assert.equal(await creator.uri(4), "token4")

      await soulbound.configureContract(creator.address, true, true, "prefix://", {from:owner});
      assert.equal(await creator.uri(2), "prefix://token2")
      assert.equal(await creator.uri(4), "prefix://token4")
    });
  });
});