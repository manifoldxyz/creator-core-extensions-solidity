const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockTestERC721Creator');
const ERC721EditionTemplate = artifacts.require("ERC721EditionTemplate");
const NiftyGatewayERC721EditionImplementation = artifacts.require("NiftyGatewayERC721EditionImplementation");

contract('Nifty Gateway Edition', function ([creator, ...accounts]) {
  const name = 'Token';
  const symbol = 'NFT';
  const minter = creator;
  const [
    owner,
    niftyGatewayOmnibus,
    niftyGatewayMinter1,
    niftyGatewayMinter2,
    anyone,
    another1,
    another2,
    ] = accounts;

  describe('Nifty Gateway Edition', function() {
    var creator;
    var editionImplementation;
    var editionTemplate;

    beforeEach(async function () {
      creator = await ERC721Creator.new(name, symbol, {from:owner});
      editionImplementation = await NiftyGatewayERC721EditionImplementation.new();
      editionTemplate = await ERC721EditionTemplate.new(editionImplementation.address, creator.address, {from:owner});
      await creator.registerExtension(editionTemplate.address, "override", {from:owner})
      editionTemplate = await NiftyGatewayERC721EditionImplementation.at(editionTemplate.address);
    });

    it('access test', async function () {
      await truffleAssert.reverts(editionTemplate.activate(1, [niftyGatewayMinter1, niftyGatewayMinter2], niftyGatewayOmnibus), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.updateURIParts([]), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.mintNifty(1, 1), "Unauthorized");
    });

    it('edition template test', async function () {
        await editionTemplate.activate(10, [niftyGatewayMinter1, niftyGatewayMinter2], niftyGatewayOmnibus, {from:owner});
        await truffleAssert.reverts(editionTemplate.activate(1, [niftyGatewayMinter1, niftyGatewayMinter2], niftyGatewayOmnibus, {from:owner}), "Already activated");
        await editionTemplate.mintNifty(1, 1, {from:niftyGatewayMinter1});
        await editionTemplate.mintNifty(1, 3, {from:niftyGatewayMinter2});
        assert.equal(await creator.balanceOf(niftyGatewayOmnibus), 4);
        assert.equal(await editionTemplate._mintCount(1), 4);
        await truffleAssert.reverts(editionTemplate.mintNifty(1, 7, {from:niftyGatewayMinter1}), "Too many requested");

        console.log(await creator.tokenURI(3));
    });

  });

});