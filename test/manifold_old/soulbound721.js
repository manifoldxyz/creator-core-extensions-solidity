const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const ERC721Soulbound = artifacts.require('ERC721Soulbound');
const keccak256 = require('keccak256');
const ethers = require('ethers');

contract('Soulbound721', function ([...accounts]) {
  const [owner, anotherOwner, anyone1, anyone2] = accounts;
  describe('Soulbound721', function () {
    let creator, soulbound;
    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", {from:owner});
      soulbound = await ERC721Soulbound.new({from:owner});
      
      // Must register with empty prefix in order to set per-token uri's
      await creator.registerExtension(soulbound.address, {from:owner});
    });


    it('access test', async function () {
      await truffleAssert.reverts(soulbound.setApproveTransfer(creator.address, true, {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.configureContract(creator.address, true, true, "", {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.methods['configureToken(address,uint256,bool,bool)'](creator.address, 1, true, true, {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.methods['configureToken(address,uint256[],bool,bool)'](creator.address, [1], true, true, {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.mintToken(creator.address, anyone1, "", {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.methods['setTokenURI(address,uint256,string)'](creator.address, 1, "", {from: anotherOwner}), "Must be owner or admin")
      await truffleAssert.reverts(soulbound.methods['setTokenURI(address,uint256[],string[])'](creator.address, [1], [""], {from: anotherOwner}), "Must be owner or admin")
    });

    it('functionality test', async function () {
      await soulbound.mintToken(creator.address, anyone1, "token1", {from:owner})
      await soulbound.mintToken(creator.address, anyone1, "token2", {from:owner})
      await soulbound.mintToken(creator.address, anyone1, "token3", {from:owner})
      await soulbound.mintToken(creator.address, anyone1, "token4", {from:owner})

      // Default soulbound but burnable
      await truffleAssert.reverts(creator.transferFrom(anyone1, anyone2, 1, {from:anyone1}), "Extension approval failure")
      await creator.burn(1, {from:anyone1})

      // Make non-burnable at token level
      await soulbound.methods['configureToken(address,uint256,bool,bool)'](creator.address, 2, true, false, {from:owner});
      await truffleAssert.reverts(creator.burn(2, {from:anyone1}), "Extension approval failure")
      await creator.burn(3, {from:anyone1})

      // Make non-burnable at contract level
      await soulbound.configureContract(creator.address, true, false, "", {from:owner});
      await truffleAssert.reverts(creator.burn(4, {from:anyone1}), "Extension approval failure")

      // Make specific token burnable at token level, still cannot burn because restrction exists at the contract level
      await soulbound.methods['configureToken(address,uint256[],bool,bool)'](creator.address, [2], true, true, {from:owner});
      await truffleAssert.reverts(creator.burn(2, {from:anyone1}), "Extension approval failure")

      // Make non-soulbound at token level
      await soulbound.methods['configureToken(address,uint256[],bool,bool)'](creator.address, [2], false, false, {from:owner});
      await creator.transferFrom(anyone1, anyone2, 2, {from:anyone1});
      await truffleAssert.reverts(creator.transferFrom(anyone1, anyone2, 4, {from:anyone1}), "Extension approval failure")

      // Make non-soulbound at contract level
      await soulbound.configureContract(creator.address, false, false, "", {from:owner});
      await creator.transferFrom(anyone1, anyone2, 4, {from:anyone1});

      // Make soulbound at token level, transfers allowed because it's still not soulbound at contract level
      await soulbound.methods['configureToken(address,uint256[],bool,bool)'](creator.address, [2,4], true, false, {from:owner});
      await creator.transferFrom(anyone2, anyone1, 2, {from:anyone2})
      await creator.transferFrom(anyone2, anyone1, 4, {from:anyone2})

      // Make soulbound at contract level
      await soulbound.configureContract(creator.address, true, true, "", {from:owner});
      await truffleAssert.reverts(creator.transferFrom(anyone1, anyone2, 2, {from:anyone1}), "Extension approval failure")
      await truffleAssert.reverts(creator.transferFrom(anyone1, anyone2, 4, {from:anyone1}), "Extension approval failure")

      // Disable extension
      await soulbound.setApproveTransfer(creator.address, false, {from: owner});
      // No longer enforcing soulbound
      await creator.transferFrom(anyone1, anyone2, 2, {from:anyone1})
      await creator.transferFrom(anyone1, anyone2, 4, {from:anyone1})

      // Check URIs
      assert.equal(await creator.tokenURI(2), "token2")
      assert.equal(await creator.tokenURI(4), "token4")

      await soulbound.configureContract(creator.address, true, true, "prefix://", {from:owner});
      assert.equal(await creator.tokenURI(2), "prefix://token2")
      assert.equal(await creator.tokenURI(4), "prefix://token4")

    });
  });
});