const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockERC721Creator');
const ManifoldERC721Edition = artifacts.require("ManifoldERC721Edition");

contract('Manifold Edition', function ([creator, ...accounts]) {
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

  describe('Manifold Edition', function() {
    var creator1;
    var creator2;
    var creator3;
    var edition;

    beforeEach(async function () {
      creator1 = await ERC721Creator.new('c1', 'c1', {from:another1});
      creator2 = await ERC721Creator.new('c2', 'c2', {from:another2});
      creator3 = await ERC721Creator.new('c3', 'c3', {from:another3});
      
      edition = await ManifoldERC721Edition.new({from:owner});
      
      await creator1.registerExtension(edition.address, "", {from:another1});
      await creator2.registerExtension(edition.address, "", {from:another2});
      await creator3.registerExtension(edition.address, "", {from:another3});
    });

    it('access test', async function () {
      await truffleAssert.reverts(edition.createSeries(creator1.address, 1, "", {from:owner}), "Must be owner or admin of creator contract");
      await truffleAssert.reverts(edition.setTokenURIPrefix(creator1.address, 1, "", {from:owner}), "Must be owner or admin of creator contract");
      await truffleAssert.reverts(edition.setTokenURIPrefix(creator1.address, 0, "", {from:another1}), "Invalid series");
      await truffleAssert.reverts(edition.methods['mint(address,uint256,address,uint16)'](creator1.address, 1, anyone,1, {from:owner}), "Must be owner or admin of creator contract");
      await truffleAssert.reverts(edition.methods['mint(address,uint256,address[])'](creator1.address, 1, [anyone], {from:owner}), "Must be owner or admin of creator contract");
    });

    it('edition test', async function () {
      await truffleAssert.reverts(edition.methods['mint(address,uint256,address,uint16)'](creator1.address, 1, anyone,1, {from:another1}), "Too many requested");
      await edition.createSeries(creator1.address, 10, 'http://creator1series1/', {from:another1})
      await edition.methods['mint(address,uint256,address,uint16)'](creator1.address, 1, another3, 2, {from:another1});
      await edition.methods['mint(address,uint256,address[])'](creator1.address, 1, [another1,another2], {from:another1});
      assert.equal(await creator1.balanceOf(another3), 2);
      assert.equal(await creator1.balanceOf(another1), 1);
      assert.equal(await creator1.balanceOf(another2), 1);
      await truffleAssert.reverts(edition.methods['mint(address,uint256,address,uint16)'](creator1.address, 1, anyone, 7, {from:another1}), "Too many requested");
      console.log(await creator1.tokenURI(3));
    });

    it('edition index test', async function () {
      await edition.createSeries(creator1.address, 10, 'http://creator1series1/', {from:another1})
      await edition.createSeries(creator1.address, 20, 'http://creator1series2/', {from:another1})
      await edition.createSeries(creator2.address, 200, 'http://creator1series2/', {from:another2})
      await edition.createSeries(creator3.address, 300, 'http://creator1series2/', {from:another3})

      assert.equal(10, await edition.maxSupply(creator1.address, 1));
      assert.equal(20, await edition.maxSupply(creator1.address, 2));
      assert.equal(200, await edition.maxSupply(creator2.address, 1));
      assert.equal(300, await edition.maxSupply(creator3.address, 1));

      await edition.methods['mint(address,uint256,address,uint16)'](creator1.address, 1, another3, 2, {from:another1});
      // Mint some tokens in between
      await creator1.methods['mintBaseBatch(address,uint16)'](owner, 10, {from:another1});
      await edition.methods['mint(address,uint256,address,uint16)'](creator1.address, 1, another3, 3, {from:another1});
      assert.equal('http://creator1series1/3', await creator1.tokenURI(13));
      assert.equal('http://creator1series1/5', await creator1.tokenURI(15));
      // Mint series in between
      await edition.methods['mint(address,uint256,address,uint16)'](creator1.address, 2, another3, 2, {from:another1});
      await edition.methods['mint(address,uint256,address,uint16)'](creator1.address, 1, another3, 1, {from:another1});
      // Mint items from other creators in between
      await edition.methods['mint(address,uint256,address,uint16)'](creator2.address, 1, another3, 2, {from:another2});
      await edition.methods['mint(address,uint256,address,uint16)'](creator3.address, 1, another3, 2, {from:another3});
      
      assert.equal('http://creator1series2/1', await creator1.tokenURI(16));
      assert.equal('http://creator1series2/2', await creator1.tokenURI(17));
      assert.equal('http://creator1series1/6', await creator1.tokenURI(18));

      await truffleAssert.reverts(edition.tokenURI(creator1.address, 6), "Invalid token");
      await truffleAssert.reverts(edition.tokenURI(creator1.address, 19), "Invalid token");

      // Prefix change test
      await edition.setTokenURIPrefix(creator1.address, 1, 'http://creator1series1new/', {from:another1});
      assert.equal('http://creator1series1new/3', await creator1.tokenURI(13));
      assert.equal('http://creator1series1new/5', await creator1.tokenURI(15));
    });

    it('edition cost test (10)', async function () {
      // Mint 10 things
      const x = 10;
      await edition.createSeries(creator1.address, x, 'prefix://', {from:another1})
      var receivers = [];
      var uris = []
      for (let i = 0; i < x; i++) {
        receivers.push(anyone);
        uris.push('https://arweave.net/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX');
      }
      var tx = await edition.methods["mint(address,uint256,address[])"](creator1.address, 1, receivers, {from:another1});
      console.log("Cost to mint 10 items: "+ tx.receipt.gasUsed);

      // Mint 10 things using mintBaseBatch
      tx = await creator1.methods["mintBaseBatch(address,string[])"](owner, uris, {from:another1});
      console.log("Cost to mint 10 items (mintBaseBatch): "+ tx.receipt.gasUsed);
    });

    it('edition cost test (20)', async function () {
      // Mint 20 things
      const x = 20;
      await edition.createSeries(creator1.address, x, 'prefix://', {from:another1})
      var receivers = [];
      var uris = []
      for (let i = 0; i < x; i++) {
        receivers.push(anyone);
        uris.push('https://arweave.net/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX');
      }
      var tx = await edition.methods["mint(address,uint256,address[])"](creator1.address, 1, receivers, {from:another1});
      console.log("Cost to mint 20 items: "+ tx.receipt.gasUsed);

      // Mint 20 things using mintBaseBatch
      tx = await creator1.methods["mintBaseBatch(address,string[])"](owner, uris, {from:another1});
      console.log("Cost to mint 20 items (mintBaseBatch): "+ tx.receipt.gasUsed);
    });

    it('edition cost test (100)', async function () {
      // Mint 100 things
      const x = 100;
      await edition.createSeries(creator1.address, x, 'prefix://', {from:another1})
      var receivers = [];
      var uris = []
      for (let i = 0; i < x; i++) {
        receivers.push(anyone);
        uris.push('https://arweave.net/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX');
      }
      var tx = await edition.methods["mint(address,uint256,address[])"](creator1.address, 1, receivers, {from:another1});
      console.log("Cost to mint 100 items: "+ tx.receipt.gasUsed);

      // Mint 100 things using mintBaseBatch
      tx = await creator1.methods["mintBaseBatch(address,string[])"](owner, uris, {from:another1});
      console.log("Cost to mint 100 items (mintBaseBatch): "+ tx.receipt.gasUsed);
    });

  });

});
