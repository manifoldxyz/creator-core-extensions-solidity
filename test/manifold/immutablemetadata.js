const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockERC721Creator');
const ERC721ImmutableMetadata = artifacts.require("ERC721ImmutableMetadata");

contract('Manifold Immutable Metadata', function ([creator, ...accounts]) {
  const name = 'Token';
  const symbol = 'NFT';
  const minter = creator;
  const [
    owner,
    another1,
    another2,
    another3,
    anyone,
    ] = accounts;

  describe('Manifold Immutable Metadata', function() {
    var creator1;
    var extension;

    beforeEach(async function () {
      creator1 = await ERC721Creator.new('c1', 'c1', {from:another1});
      
      extension = await ERC721ImmutableMetadata.new({from:owner});
      
      await creator1.registerExtension(extension.address, "", {from:another1});
    });

    it('access test', async function () {
      await truffleAssert.reverts(extension.mintToken(creator1.address, another2, "", {from:owner}), "Must be owner or admin of creator contract");
    });

    it('mintToken blank URI test', async function () {
      await truffleAssert.reverts(extension.mintToken(creator1.address, another1, "", {from:another1}), "Cannot mint blank string");
    });

    it('mintToken test', async function () {
      await extension.mintToken(creator1.address, another2, "{hey:hey}", {from:another1})
      assert.equal(await creator1.balanceOf(another2), 1)
      assert.equal(await creator1.tokenURI(1), "{hey:hey}")
    });

    it('cannot update URI test', async function () {
      await extension.mintToken(creator1.address, another2, "{hey:hey}", {from:another1})
      assert.equal(await creator1.balanceOf(another2), 1)
      assert.equal(await creator1.tokenURI(1), "{hey:hey}")

      // Only extension itself is allowed to update tokenURI extension
      // And no code is written in the extension to do so. Effectively,
      // this freezes the token.
      await truffleAssert.reverts(creator1.setTokenURIExtension(1, "{hey2:hey2}", {from:another1}), "Must be registered extension");
    });

  });

});
