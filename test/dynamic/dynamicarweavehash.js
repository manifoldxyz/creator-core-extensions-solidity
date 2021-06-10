const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockTestERC721Creator');
const DynamicArweaveHash = artifacts.require("DynamicArweaveHash");

contract('DynamicArweaveHash', function ([creator, ...accounts]) {
    const name = 'Token';
    const symbol = 'NFT';
    const minter = creator;
    const [
           owner,
           newOwner,
           another,
           anyone,
           ] = accounts;

    describe('DynamicArweaveHash', function() {
        var creator;
        var extension;
        var mock721;
        var mock1155;
        var redemptionRate = 3;
        var redemptionMax = 2;

        beforeEach(async function () {
            console.log('deploying creator');
            creator = await ERC721Creator.new(name, symbol, {from:owner});
            console.log('creator deployed');
            extension = await DynamicArweaveHash.new(creator.address, {from:owner});
            await creator.registerExtension(extension.address, "override", {from:owner})
        });

        it('access test', async function () {
            await truffleAssert.reverts(extension.mint(anyone, {from:anyone}), "Ownable: caller is not the owner");
        });

        it('uri test', async function () {
            await extension.setApproveTransfer(creator.address, true, {from:owner});
            await extension.mint(anyone, {from:owner});
            console.log(await creator.tokenURI(1));
            // Advance by 1 day.
            await helper.advanceTimeAndBlock(60*60*24*1);
            console.log(await creator.tokenURI(1));
            // Does not reset clock when transferred
            await creator.transferFrom(anyone, newOwner, 1, {from:anyone});
            console.log(await creator.tokenURI(1));  
        });

    });

});