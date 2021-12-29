const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockERC721Creator');
const Airdrop = artifacts.require("ManifoldAirdrop");

contract('Airdrop', function ([creator, ...accounts]) {
  const name = 'Token';
  const symbol = 'NFT';
  const minter = creator;
  const [
    owner,
    another1,
    another2,
    anyone,
    airdropUser1,
    airdropUser2,
  ] = accounts;

  describe('Airdrop', function() {
    var creator1;
    var creator2;
    var airdrop;
    beforeEach(async function () {
      creator1 = await ERC721Creator.new(name, symbol, {from:another1});
      creator2 = await ERC721Creator.new(name, symbol, {from:another2});
      airdrop = await Airdrop.new({from:owner});

      assert.equal(await airdrop.isRegistered(creator1.address), false);
      await creator1.registerExtension(airdrop.address, "", {from:another1})
      assert.equal(await airdrop.isRegistered(creator1.address), true);
        
      assert.equal(await airdrop.isRegistered(creator2.address), false);
      await creator2.registerExtension(airdrop.address, "", {from:another2})
      assert.equal(await airdrop.isRegistered(creator2.address), true);
    });

    it('access test', async function () {
      await truffleAssert.reverts(airdrop.setEnabled(false, {from:anyone}), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(airdrop.methods["airdrop(address,address[],string)"](creator1.address, [airdropUser1,airdropUser2], "", {from:another2}), "Must be admin of the token contract to mint");
      await truffleAssert.reverts(airdrop.methods["airdrop(address,address[],string[])"](creator1.address, [airdropUser1,airdropUser2], ["",""], {from:another2}), "Must be admin of the token contract to mint");
    });

    it('airdrop test', async function () {
      await airdrop.methods["airdrop(address,address[],string)"](creator1.address, [airdropUser1,airdropUser2], "first", {from:another1});
      assert.equal(await creator1.balanceOf(airdropUser1), 1);
      assert.equal(await creator1.balanceOf(airdropUser2), 1);
      assert.equal(await creator1.tokenURI(1), "first");
      assert.equal(await creator1.tokenURI(2), "first");
      await airdrop.methods["airdrop(address,address[],string[])"](creator2.address, [airdropUser1,airdropUser2], ["second","third"], {from:another2});
      assert.equal(await creator2.balanceOf(airdropUser1), 1);
      assert.equal(await creator2.balanceOf(airdropUser2), 1);
      assert.equal(await creator2.tokenURI(1), "second");
      assert.equal(await creator2.tokenURI(2), "third");
    });

    it('airdrop cost test', async function () {
      // Mint 100 things
      const x = 100;
      var receivers = [];
      for (let i = 0; i < x; i++) {
        receivers.push(anyone);
      }
      var tx = await airdrop.methods["airdrop(address,address[],string)"](creator1.address, receivers, "jEoth4ck7IWDhmXaI6d2Obg_lP6o1cezR_P-r7nbsuE", {from:another1});
      console.log("Cost to mint 100 items: "+ tx.receipt.gasUsed);
    });
      
  });

});
