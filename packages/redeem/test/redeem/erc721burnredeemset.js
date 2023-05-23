const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockERC721Creator');
const ERC721BurnRedeemSet = artifacts.require("ERC721BurnRedeemSet");
const MockERC721 = artifacts.require('@manifoldxyz/creator-core-solidity/MockERC721');
const MockERC1155 = artifacts.require('@manifoldxyz/creator-core-solidity/MockERC1155');

contract('ERC721BurnRedeemSet', function ([creator, ...accounts]) {
    const name = 'Token';
    const symbol = 'NFT';
    const minter = creator;
    const [
           owner,
           newOwner,
           another,
           anyone,
           ] = accounts;

    describe('ERC721BurnRedeemSet', function() {
        var creator;
        var redeem;
        var mock721;
        var mock721Other;
        var mock1155;

        beforeEach(async function () {
            creator = await ERC721Creator.new(name, symbol, {from:owner});
            redeem = await ERC721BurnRedeemSet.new(creator.address, [], 1, {from:owner});
            await creator.registerExtension(redeem.address, "https://redeem", {from:owner})
            mock721 = await MockERC721.new('721', '721', {from:owner});
            mock721Other = await MockERC721.new('721Other', '721Other', {from:owner});
            mock1155 = await MockERC1155.new('1155uri', {from:owner});
        });

        it('access test', async function () {
            await truffleAssert.reverts(redeem.setERC721Recoverable(anyone, 1, anyone, {from:anyone}), "AdminControl: Must be owner or admin");
        });

        it('ERC721 recovery test', async function () {
            var tokenId = 721;
            await mock721.mint(another, tokenId);
            assert.equal(await mock721.balanceOf(another), 1);
            
            await mock721.transferFrom(another, redeem.address, tokenId, {from:another});
            assert.equal(await mock721.balanceOf(another), 0);
            assert.equal(await mock721.balanceOf(redeem.address), 1);

            await truffleAssert.reverts(redeem.recoverERC721(mock721.address, tokenId, {from:another}), "BurnRedeem: Permission denied");

            await truffleAssert.reverts(redeem.setERC721Recoverable(anyone, tokenId, anyone, {from:owner}), "BurnRedeem: Must implement IERC721");
            await redeem.setERC721Recoverable(mock721.address, tokenId, anyone, {from:owner});
            
            await truffleAssert.reverts(redeem.recoverERC721(mock721.address, tokenId, {from:another}), "BurnRedeem: Permission denied");
            await redeem.recoverERC721(mock721.address, tokenId, {from:anyone});
            assert.equal(await mock721.balanceOf(another), 0);
            assert.equal(await mock721.balanceOf(anyone), 1);
            assert.equal(await mock721.balanceOf(redeem.address), 0);
        });

        it('core functionality test ERC721', async function () {
            var redemptionMax = 2;
            redeem = await ERC721BurnRedeemSet.new(creator.address, [[mock721.address, 1, 10],[mock721.address, 11, 20]], redemptionMax, {from:owner});
            await creator.registerExtension(redeem.address, "https://redeem", {from:owner})

            assert.equal(await redeem.redemptionRemaining(), redemptionMax);

            var tokenId1 = 1;
            var tokenId2 = 2;
            var tokenId3 = 11;
            var tokenId4 = 12;
            var tokenId5 = 3;
            var tokenId6 = 13;
            await mock721.mint(another, tokenId1);
            await mock721.mint(another, tokenId2);
            await mock721.mint(another, tokenId3);
            await mock721.mint(another, tokenId4);
            await mock721.mint(another, tokenId5);
            await mock721.mint(another, tokenId6);

            // Check failure cases
            await truffleAssert.reverts(redeem.redeemERC721([mock721.address], [tokenId1, tokenId2]), "BurnRedeem: Invalid parameters"); 
            await truffleAssert.reverts(redeem.redeemERC721([mock721.address], [tokenId1]), "Incorrect number of NFTs being redeemed");
            await truffleAssert.reverts(redeem.redeemERC721([mock721.address, mock721.address, mock721.address], [tokenId1, tokenId2, tokenId3]), "Incorrect number of NFTs being redeemed");
            await truffleAssert.reverts(redeem.redeemERC721([mock721.address, mock721.address], [tokenId1, tokenId2]), "BurnRedeem: Incomplete set");
            await truffleAssert.reverts(redeem.redeemERC721([mock721.address, mock721.address], [tokenId1, tokenId3], {from:anyone}), "BurnRedeem: Caller must own NFTs");
            await truffleAssert.reverts(redeem.redeemERC721([mock721.address, mock721.address], [tokenId1, tokenId3], {from:another}), "BurnRedeem: Contract must be given approval to burn NFT");

            // Approve to redeem
            await mock721.approve(redeem.address, tokenId1, {from:another});
            await mock721.approve(redeem.address, tokenId3, {from:another});
            await redeem.redeemERC721([mock721.address, mock721.address], [tokenId1, tokenId3], {from:another});

            assert.equal(await mock721.balanceOf(another), 4);
            assert.equal(await creator.balanceOf(another), 1);
            assert.equal(await redeem.redemptionRemaining(), redemptionMax-1);
            
            await mock721.setApprovalForAll(redeem.address, true, {from:another});
            await redeem.redeemERC721([mock721.address, mock721.address], [tokenId2, tokenId4], {from:another});
            
            assert.equal(await mock721.balanceOf(another), 2);
            assert.equal(await creator.balanceOf(another), 2);
            assert.equal(await redeem.redemptionRemaining(), 0);
            
            await truffleAssert.reverts(redeem.redeemERC721([mock721.address, mock721.address], [tokenId5, tokenId6], {from:another}), "Redeem: No redemptions remaining");

        });

        it('core functionality test ERC1155', async function () {
            var redemptionMax = 2;
            redeem = await ERC721BurnRedeemSet.new(creator.address, [[mock1155.address, 1, 10],[mock1155.address, 11, 20]], redemptionMax, {from:owner});
            await creator.registerExtension(redeem.address, "https://redeem", {from:owner})

            var tokenId1 = 1;
            var tokenId2 = 2;
            var tokenId3 = 11;

            await mock1155.mint(another, tokenId1, 9);
            await mock1155.mint(another, tokenId2, 6);
            await mock1155.mint(another, tokenId3, 6);

            // Check failure cases
            await truffleAssert.reverts(mock1155.safeTransferFrom(another, redeem.address, tokenId1, 1, "0x0", {from:another}), "BurnRedeem: Incomplete set"); 
            await truffleAssert.reverts(mock1155.safeBatchTransferFrom(another, redeem.address, [tokenId1], [3], "0x0", {from:another}), "BurnRedeem: Can only use one of each token"); 
            await truffleAssert.reverts(mock1155.safeBatchTransferFrom(another, redeem.address, [tokenId1,tokenId2], [1,1], "0x0", {from:another}), "BurnRedeem: Incomplete set");

            await mock1155.safeBatchTransferFrom(another, redeem.address, [tokenId1, tokenId3], [1, 1], "0x0", {from:another});
            assert.equal(await creator.balanceOf(another), 1);
            assert.equal(await mock1155.balanceOf(another, tokenId1), 8);
            assert.equal(await mock1155.balanceOf(another, tokenId2), 6);
            assert.equal(await mock1155.balanceOf(another, tokenId3), 5);

            await mock1155.safeBatchTransferFrom(another, redeem.address, [tokenId1, tokenId3], [1, 1], "0x0", {from:another});
            assert.equal(await creator.balanceOf(another), 2);
            assert.equal(await mock1155.balanceOf(another, tokenId1), 7);
            assert.equal(await mock1155.balanceOf(another, tokenId2), 6);
            assert.equal(await mock1155.balanceOf(another, tokenId3), 4);

            await truffleAssert.reverts(mock1155.safeBatchTransferFrom(another, redeem.address, [tokenId1, tokenId3], [1,1], "0x0", {from:another}), "Redeem: No redemptions remaining");

        });
    });

});