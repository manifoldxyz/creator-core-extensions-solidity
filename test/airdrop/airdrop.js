const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockTestERC721Creator');
const Airdrop = artifacts.require("Airdrop");

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
        var extension;
        beforeEach(async function () {
            creator = await ERC721Creator.new(name, symbol, {from:owner});
            extension = await Airdrop.new({from:owner});
            await creator.registerExtension(extension.address, "override", {from:owner})
        });

        it('access test', async function () {
            await truffleAssert.reverts(extension.methods['airdrop(address,address[])'](creator.address, [anyone], {from:anyone}), "AdminControl: Must be owner or admin");
            await truffleAssert.reverts(extension.methods['airdrop(address,address[],string[])'](creator.address, [anyone], [""], {from:anyone}), "AdminControl: Must be owner or admin");
        });

        it('batch mint test', async function () {
            // Mint X things
            const x = 100;
            var receivers = [];
            for (let i = 0; i < x; i++) {
                receivers.push(anyone);
            }
            
            const creatorBatchTx = await creator.methods['mintBaseBatch(address,uint16)'](anyone, x, {from:owner});
            const extensionTx = await extension.methods['airdrop(address,address[])'](creator.address, receivers, {from:owner});
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

    });

});