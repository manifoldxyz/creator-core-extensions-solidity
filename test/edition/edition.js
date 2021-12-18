const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockERC721Creator');
const ERC721Edition = artifacts.require("ERC721Edition");
const ERC721EditionTemplate = artifacts.require("ERC721EditionTemplate");
const ERC721EditionImplementation = artifacts.require("ERC721EditionImplementation");

contract('Edition', function ([creator, ...accounts]) {
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

  describe('Edition', function() {
    var creator;
    var edition;
    var editionImplementation;
    var editionTemplate;

    beforeEach(async function () {
      creator = await ERC721Creator.new(name, symbol, {from:owner});
      edition = await ERC721Edition.new(creator.address, [
          'data:application/json;utf8,{"name":"Edition #','<EDITION>',
          '/',
          '<TOTAL>',
          ', "description":"Description",',
          '"attributes":[{"display_type":"number","trait_type":"Edition","value":',
          '<EDITION>',
          ',"max_value":',
          '<TOTAL>',
          '}]}'
          ], {from:owner});
      await creator.registerExtension(edition.address, "override", {from:owner})
      editionImplementation = await ERC721EditionImplementation.new();
      editionTemplate = await ERC721EditionTemplate.new(editionImplementation.address, creator.address, {from:owner});
      await creator.registerExtension(editionTemplate.address, "override", {from:owner})
      editionTemplate = await ERC721Edition.at(editionTemplate.address);
    });

    it('access test', async function () {
      await truffleAssert.reverts(edition.activate(1), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(edition.updateURIParts([]), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(edition.methods['mint(address,uint256)'](anyone,1), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(edition.methods['mint(address[])']([anyone]), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.activate(1), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.updateURIParts([]), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.methods['mint(address,uint256)'](anyone,1), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.methods['mint(address[])']([anyone]), "AdminControl: Must be owner or admin");
    });

    it('edition test', async function () {
        await truffleAssert.reverts(edition.methods['mint(address,uint256)'](anyone, 1, {from:owner}), "Not activated");
        await truffleAssert.reverts(edition.methods['mint(address[])']([anyone], {from:owner}), "Not activated");

        await edition.activate(10, {from:owner});
        await truffleAssert.reverts(edition.activate(1, {from:owner}), "Already activated");
        await edition.methods['mint(address,uint256)'](anyone, 2, {from:owner});
        await edition.methods['mint(address[])']([another1,another2], {from:owner});
        assert.equal(await creator.balanceOf(anyone), 2);
        assert.equal(await creator.balanceOf(another1), 1);
        assert.equal(await creator.balanceOf(another2), 1);
        await truffleAssert.reverts(edition.methods['mint(address,uint256)'](anyone, 7, {from:owner}), "Too many requested");

        console.log(await creator.tokenURI(3));
    });

    it('edition template test', async function () {
        await truffleAssert.reverts(editionTemplate.methods['mint(address,uint256)'](anyone, 1, {from:owner}), "Not activated");
        await truffleAssert.reverts(editionTemplate.methods['mint(address[])']([anyone], {from:owner}), "Not activated");

        await editionTemplate.activate(10, {from:owner});
        await truffleAssert.reverts(editionTemplate.activate(1, {from:owner}), "Already activated");
        await editionTemplate.methods['mint(address,uint256)'](anyone, 2, {from:owner});
        await editionTemplate.methods['mint(address[])']([another1,another2], {from:owner});
        assert.equal(await creator.balanceOf(anyone), 2);
        assert.equal(await creator.balanceOf(another1), 1);
        assert.equal(await creator.balanceOf(another2), 1);
        await truffleAssert.reverts(editionTemplate.methods['mint(address,uint256)'](anyone, 7, {from:owner}), "Too many requested");

        console.log(await creator.tokenURI(3));
    });

  });

});