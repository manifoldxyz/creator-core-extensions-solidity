const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const OperatorFilter = artifacts.require("CreatorOperatorFilterer");
const ERC721Creator = artifacts.require('MockERC721Creator');
const ERC721FrozenMetadata = artifacts.require("ERC721FrozenMetadataNoFilterer");

contract('Manifold 721 Frozen Metadata No Filterer', function ([minter, ...accounts]) {
  const name = 'Token';
  const symbol = 'NFT';
  const [
    deployer,
    operator,
    owner,
    another,
    anyone,
    ] = accounts;

  describe('Manifold 721 Frozen Metadata No Filterer', function() {
    var creator;
    var extension;

    beforeEach(async function () {
      creator = await ERC721Creator.new('c1', 'c1', {from:owner});
      extension = await ERC721FrozenMetadata.new({from:deployer});
      await creator.registerExtension(extension.address, "", {from:owner});
    });

    it('access test', async function () {
      await truffleAssert.reverts(extension.mintToken(creator.address, another, "", {from:deployer}), "Must be owner or admin of creator contract");
    });

    it('mintToken blank URI test', async function () {
      await truffleAssert.reverts(extension.mintToken(creator.address, owner, "", {from:owner}), "Cannot mint blank string");
    });

    it('mintToken test', async function () {
      await extension.mintToken(creator.address, another, "{hey:hey}", {from:owner})
      assert.equal(await creator.balanceOf(another), 1)
      assert.equal(await creator.tokenURI(1), "{hey:hey}")
    });

    it('cannot update URI test', async function () {
      await extension.mintToken(creator.address, another, "{hey:hey}", {from:owner})
      assert.equal(await creator.balanceOf(another), 1)
      assert.equal(await creator.tokenURI(1), "{hey:hey}")

      // Only extension itself is allowed to update tokenURI extension
      // And no code is written in the extension to do so. Effectively,
      // this freezes the token.
      await truffleAssert.reverts(creator.setTokenURIExtension(1, "{hey2:hey2}", {from:owner}), "Must be registered extension");
    });

    it('transfer restriction test', async function () {
      await extension.mintToken(creator.address, operator, "{hey:hey}", {from:owner})
      // Create an operator filter and set it
      var filterer = await OperatorFilter.new();
      await creator.setApproveTransfer(filterer.address, {from:owner});
      await filterer.configureBlockedOperators(creator.address, [operator], [true], { from: owner })

      // Should still be able to transfer
      await creator.transferFrom(operator, another, 1, {from:operator});
    });

  });

});
