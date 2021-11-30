const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockTestERC721Creator');
const LazyWhitelist = artifacts.require("ERC721LazyMintWhitelist");
const LazyWhitelistTemplate = artifacts.require("ERC721LazyMintWhitelistTemplate");
const LazyWhitelistImplementation = artifacts.require("ERC721LazyMintWhitelistImplementation");

contract('LazyWhitelist', function ([creator, ...accounts]) {
  const name = 'Token';
  const symbol = 'NFT';
  const minter = creator;
  const [
    owner,
    newOwner,
    another,
    anyone,
  ] = accounts;

  describe('LazyWhitelist', function() {
    var creator;
    var lazywhitelist;
    var lazywhitelistImplementation;
    var lazywhitelistTemplate;
    beforeEach(async function () {
      creator = await ERC721Creator.new(name, symbol, {from:owner});
      lazywhitelist = await LazyWhitelist.new(creator.address, "https://lazywhitelist/", {from:owner});
      await creator.registerExtension(lazywhitelist.address, "override", {from:owner})
      lazywhitelistImplementation = await LazyWhitelistImplementation.new();
      lazywhitelistTemplate = await LazyWhitelistTemplate.new(lazywhitelistImplementation.address, creator.address, "https://lazywhitelist/template", {from:owner});
      await creator.registerExtension(lazywhitelistTemplate.address, "override", {from:owner})
      lazywhitelistTemplate = await LazyWhitelist.at(lazywhitelistTemplate.address);
    });

    it('access test', async function () {
      await truffleAssert.reverts(lazywhitelist.premint([anyone], {from:anyone}), "AdminControl: Must be owner or admin");

      // await truffleAssert.reverts(airdrop.airdrop([anyone], {from:anyone}), "AdminControl: Must be owner or admin");
      // await truffleAssert.reverts(airdrop.setTokenURIPrefix("", {from:anyone}), "AdminControl: Must be owner or admin");
      // await truffleAssert.reverts(airdropTemplate.airdrop([anyone], {from:anyone}), "AdminControl: Must be owner or admin");
      // await truffleAssert.reverts(airdropTemplate.setTokenURIPrefix("", {from:anyone}), "AdminControl: Must be owner or admin");
    });

    // it('batch mint test', async function () {
    //   // Mint X things
    //   const x = 100;
    //   var receivers = [];
    //   for (let i = 0; i < x; i++) {
    //     receivers.push(anyone);
    //   }
        
      
    //   const creatorBatchTx = await creator.methods['mintBaseBatch(address,uint16)'](anyone, x, {from:owner});
    //   const extensionTx = await airdrop.airdrop(receivers, {from:owner});
    //   console.log(await creator.tokenURI(x+1));
    //   var baseGas = 0;
    //   for (let i = 0; i < x; i++) {
    //     const baseTx = await creator.methods['mintBase(address,string)'](anyone, "http://testdomain.com/testdata", {from:owner});
    //     baseGas += baseTx.receipt.gasUsed;
    //   }

    //   // 952 extra gas used per NFT for internal vs external mint.
    //   console.log(x+" NFT's via simulated native batch - Gas Cost: "+(creatorBatchTx.receipt.gasUsed+952*x));
    //   console.log(x+" NFT's via a batch extension - Gas Cost: "+extensionTx.receipt.gasUsed);
    //   console.log(x+" NFT's via 1-by-1 base mint - Gas Cost: "+baseGas);
    // });

    // it('template mint test', async function () {
    //   // Mint X things
    //   const x = 5;
    //   var receivers = [];
    //   for (let i = 0; i < x; i++) {
    //     receivers.push(anyone);
    //   }
      
    //   await creator.methods['mintBaseBatch(address,uint16)'](anyone, x, {from:owner});
    //   await airdropTemplate.airdrop(receivers, {from:owner});
    //   console.log(await creator.tokenURI(x+1));
  
    // });

  });

});