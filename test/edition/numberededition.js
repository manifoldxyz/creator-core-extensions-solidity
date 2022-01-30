const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockERC721Creator');
const ERC721NumberedEdition = artifacts.require("ERC721NumberedEdition");
const ERC721NumberedEditionTemplate = artifacts.require("ERC721NumberedEditionTemplate");
const ERC721NumberedEditionImplementation = artifacts.require("ERC721NumberedEditionImplementation");

contract('Numbered Edition', function ([creator, ...accounts]) {
  const name = 'Token';
  const symbol = 'NFT';
  const minter = creator;
  const [
    owner,
    newOwner,
    anyone,
    another1,
    another2,
    ] = accounts;

  describe('Numbered Edition', function() {
    var creator;
    var edition;
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
      edition = await ERC721NumberedEdition.new(creator.address, maxSupply, uriParts, {from:owner});
      await creator.registerExtension(edition.address, "override", {from:owner});
      editionImplementation = await ERC721NumberedEditionImplementation.new(creator.address, maxSupply, uriParts);
      editionTemplate = await ERC721NumberedEditionTemplate.new(editionImplementation.address, creator.address, maxSupply, {from:owner});
      await creator.registerExtension(editionTemplate.address, "override", {from:owner});
      editionTemplate = await ERC721NumberedEdition.at(editionTemplate.address);

      assert.equal(maxSupply, await edition.maxSupply());
      assert.equal(maxSupply, await editionTemplate.maxSupply());
    });

    it('access test', async function () {
      await truffleAssert.reverts(edition.updateURIParts([]), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(edition.methods['mint(address,uint16)'](anyone,1), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(edition.methods['mint(address[])']([anyone]), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.updateURIParts([]), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.methods['mint(address,uint16)'](anyone,1), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.methods['mint(address[])']([anyone]), "AdminControl: Must be owner or admin");
    });

    it('edition test', async function () {
        await edition.methods['mint(address,uint16)'](anyone, 2, {from:owner});
        await edition.methods['mint(address[])']([another1,another2], {from:owner});
        assert.equal(await creator.balanceOf(anyone), 2);
        assert.equal(await creator.balanceOf(another1), 1);
        assert.equal(await creator.balanceOf(another2), 1);
        await truffleAssert.reverts(edition.methods['mint(address,uint16)'](anyone, 7, {from:owner}), "Too many requested");

        console.log(await creator.tokenURI(3));
    });

    it('edition template test', async function () {
        await editionTemplate.methods['mint(address,uint16)'](anyone, 2, {from:owner});
        await editionTemplate.methods['mint(address[])']([another1,another2], {from:owner});
        assert.equal(await creator.balanceOf(anyone), 2);
        assert.equal(await creator.balanceOf(another1), 1);
        assert.equal(await creator.balanceOf(another2), 1);
        await truffleAssert.reverts(editionTemplate.methods['mint(address,uint16)'](anyone, 7, {from:owner}), "Too many requested");

        console.log(await creator.tokenURI(3));
    });

  });

});
