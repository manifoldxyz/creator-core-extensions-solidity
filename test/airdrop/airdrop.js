const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockTestERC721Creator');
const Airdrop = artifacts.require("ERC721Airdrop");
const AirdropTemplate = artifacts.require("ERC721AirdropTemplate");
const AirdropImplementation = artifacts.require("ERC721AirdropImplementation");

contract('Airdrop', function ([creator, ...accounts]) {
  const name = 'Token';
  const symbol = 'NFT';
  const minter = creator;
  const [
    owner,
    newOwner,
    another,
    anyone,
  ] = accounts;

  describe('Airdrop', function() {
    var creator;
    var airdrop;
    var airdropImplementation;
    var airdropTemplate;
    beforeEach(async function () {
      creator = await ERC721Creator.new(name, symbol, {from:owner});
      airdrop = await Airdrop.new(creator.address, "https://airdrop/", {from:owner});
      await creator.registerExtension(airdrop.address, "override", {from:owner})
      airdropImplementation = await AirdropImplementation.new();
      airdropTemplate = await AirdropTemplate.new(airdropImplementation.address, creator.address, "https://airdrop/template", {from:owner});
      await creator.registerExtension(airdropTemplate.address, "override", {from:owner})
      airdropTemplate = await Airdrop.at(airdropTemplate.address);
    });

    it('access test', async function () {
      await truffleAssert.reverts(airdrop.airdrop([anyone], {from:anyone}), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(airdrop.setTokenURIPrefix("", {from:anyone}), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(airdropTemplate.airdrop([anyone], {from:anyone}), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(airdropTemplate.setTokenURIPrefix("", {from:anyone}), "AdminControl: Must be owner or admin");
    });

    it('batch mint test', async function () {
      // Mint X things
      const x = 100;
      var receivers = [];
      for (let i = 0; i < x; i++) {
        receivers.push(anyone);
      }
        
      
      const creatorBatchTx = await creator.methods['mintBaseBatch(address,uint16)'](anyone, x, {from:owner});
      const extensionTx = await airdrop.airdrop(receivers, {from:owner});
      console.log(await creator.tokenURI(x+1));
      var baseGas = 0;
      for (let i = 0; i < x; i++) {
        const baseTx = await creator.methods['mintBase(address,string)'](anyone, "http://testdomain.com/testdata", {from:owner});
        baseGas += baseTx.receipt.gasUsed;
      }

      // 952 extra gas used per NFT for internal vs external mint.
      console.log(x+" NFT's via simulated native batch - Gas Cost: "+(creatorBatchTx.receipt.gasUsed+952*x));
      console.log(x+" NFT's via a batch extension - Gas Cost: "+extensionTx.receipt.gasUsed);
      console.log(x+" NFT's via 1-by-1 base mint - Gas Cost: "+baseGas);
    });

    it('template mint test', async function () {
      // Mint X things
      const x = 5;
      var receivers = [];
      for (let i = 0; i < x; i++) {
        receivers.push(anyone);
      }
      
      await creator.methods['mintBaseBatch(address,uint16)'](anyone, x, {from:owner});
      await airdropTemplate.airdrop(receivers, {from:owner});
      console.log(await creator.tokenURI(x+1));
  
    });

  });

});