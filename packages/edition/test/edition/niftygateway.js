const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockERC721Creator');
const ERC721NumberedEditionTemplate = artifacts.require("ERC721NumberedEditionTemplate");
const NiftyGatewayERC721NumberedEditionImplementation = artifacts.require("NiftyGatewayERC721NumberedEditionImplementation");

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
    var maxSupply;
    var uriParts;

    beforeEach(async function () {
      uriParts = [
          'data:application/json;utf8,{"name":"Edition #','<EDITION>',
          '/',
          '<TOTAL>',
          ', "description":"Description",',
          '"attributes":[{"display_type":"number","trait_type":"Edition","value":',
          '<EDITION>',
          ',"max_value":',
          '<TOTAL>',
          '}]}'
      ];
      maxSupply = 10;
      creator = await ERC721Creator.new(name, symbol, {from:owner});
      editionImplementation = await NiftyGatewayERC721NumberedEditionImplementation.new(creator.address, maxSupply, uriParts);
      editionTemplate = await ERC721NumberedEditionTemplate.new(editionImplementation.address, creator.address, maxSupply, {from:owner});
      await creator.registerExtension(editionTemplate.address, "override", {from:owner});
      editionTemplate = await NiftyGatewayERC721NumberedEditionImplementation.at(editionTemplate.address);

      assert.equal(maxSupply, await editionTemplate.maxSupply());
    });

    it('access test', async function () {
      await truffleAssert.reverts(editionTemplate.activate([niftyGatewayMinter1, niftyGatewayMinter2], niftyGatewayOmnibus), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.updateURIParts([]), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.mintNifty(1, 1), "Unauthorized");
    });

    it('edition template test', async function () {
        await editionTemplate.activate([niftyGatewayMinter1, niftyGatewayMinter2], niftyGatewayOmnibus, {from:owner});
        await editionTemplate.mintNifty(1, 1, {from:niftyGatewayMinter1});
        await editionTemplate.mintNifty(1, 3, {from:niftyGatewayMinter2});
        assert.equal(await creator.balanceOf(niftyGatewayOmnibus), 4);
        assert.equal(await editionTemplate._mintCount(1), 4);
        await truffleAssert.reverts(editionTemplate.mintNifty(1, 7, {from:niftyGatewayMinter1}), "Too many requested");

        console.log(await creator.tokenURI(3));
    });

  });

});
