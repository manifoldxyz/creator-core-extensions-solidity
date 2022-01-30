const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockERC721Creator');
const ERC721PrefixEdition = artifacts.require("ERC721PrefixEdition");
const ERC721PrefixEditionTemplate = artifacts.require("ERC721PrefixEditionTemplate");
const ERC721PrefixEditionImplementation = artifacts.require("ERC721PrefixEditionImplementation");

contract('Prefix Edition', function ([creator, ...accounts]) {
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

  describe('Prefix Edition', function() {
    var creator;
    var edition;
    var editionImplementation;
    var editionTemplate;
    var maxSupply;
    var prefix;

    beforeEach(async function () {
      prefix = 'http://prefix/';
      maxSupply = 10;
      creator = await ERC721Creator.new(name, symbol, {from:owner});
      edition = await ERC721PrefixEdition.new(creator.address, maxSupply, prefix, {from:owner});
      await creator.registerExtension(edition.address, "override", {from:owner});
      editionImplementation = await ERC721PrefixEditionImplementation.new(creator.address, maxSupply, prefix);
      editionTemplate = await ERC721PrefixEditionTemplate.new(editionImplementation.address, creator.address, maxSupply, prefix, {from:owner});
      await creator.registerExtension(editionTemplate.address, "override", {from:owner});
      editionTemplate = await ERC721PrefixEdition.at(editionTemplate.address);

      assert.equal(maxSupply, await edition.maxSupply());
      assert.equal(maxSupply, await editionTemplate.maxSupply());
    });

    it('access test', async function () {
      await truffleAssert.reverts(edition.setTokenURIPrefix(""), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(edition.methods['mint(address,uint16)'](anyone,1), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(edition.methods['mint(address[])']([anyone]), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(editionTemplate.setTokenURIPrefix(""), "AdminControl: Must be owner or admin");
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

    it('edition index test', async function () {
      await edition.methods['mint(address,uint16)'](anyone, 2, {from:owner});
      // Mint some tokens in between
      await creator.methods['mintBaseBatch(address,uint16)'](owner, 10, {from:owner});
      await edition.methods['mint(address,uint16)'](another1, 3, {from:owner});

      assert.equal('http://prefix/3', await creator.tokenURI(13));
      assert.equal('http://prefix/5', await creator.tokenURI(15));
      
      await truffleAssert.reverts(edition.tokenURI(creator.address, 16), "Invalid token");
    });
    
    it('edition cost test (10)', async function () {
      // Mint 10 things
      const largeEdition = await ERC721PrefixEdition.new(creator.address, 10, prefix, {from:owner});
      await creator.registerExtension(largeEdition.address, "override", {from:owner})
      
      const x = 10;
      var receivers = [];
      var uris = []
      for (let i = 0; i < x; i++) {
        receivers.push(anyone);
        uris.push('https://arweave.net/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX');
      }
      var tx = await largeEdition.methods["mint(address[])"](receivers, {from:owner});
      console.log("Cost to mint 10 items: "+ tx.receipt.gasUsed);

      // Mint 10 things using mintBaseBatch
      tx = await creator.methods["mintBaseBatch(address,string[])"](owner, uris, {from:owner});
      console.log("Cost to mint 10 items (mintBaseBatch): "+ tx.receipt.gasUsed);
    });

    it('edition cost test (20)', async function () {
      // Mint 20 things
      const largeEdition = await ERC721PrefixEdition.new(creator.address, 20, prefix, {from:owner});
      await creator.registerExtension(largeEdition.address, "override", {from:owner})
      
      const x = 20;
      var receivers = [];
      var uris = []
      for (let i = 0; i < x; i++) {
        receivers.push(anyone);
        uris.push('https://arweave.net/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX');
      }
      var tx = await largeEdition.methods["mint(address[])"](receivers, {from:owner});
      console.log("Cost to mint 20 items: "+ tx.receipt.gasUsed);

      // Mint 20 things using mintBaseBatch
      tx = await creator.methods["mintBaseBatch(address,string[])"](owner, uris, {from:owner});
      console.log("Cost to mint 20 items (mintBaseBatch): "+ tx.receipt.gasUsed);
    });

    it('edition cost test (100)', async function () {
      // Mint 100 things
      const largeEdition = await ERC721PrefixEdition.new(creator.address, 100, prefix, {from:owner});
      await creator.registerExtension(largeEdition.address, "override", {from:owner})
      
      const x = 100;
      var receivers = [];
      var uris = []
      for (let i = 0; i < x; i++) {
        receivers.push(anyone);
        uris.push('https://arweave.net/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX');
      }
      var tx = await largeEdition.methods["mint(address[])"](receivers, {from:owner});
      console.log("Cost to mint 100 items: "+ tx.receipt.gasUsed);

      // Mint 100 things using mintBaseBatch
      tx = await creator.methods["mintBaseBatch(address,string[])"](owner, uris, {from:owner});
      console.log("Cost to mint 100 items (mintBaseBatch): "+ tx.receipt.gasUsed);
    });

  });

});
