const truffleAssert = require('truffle-assertions');
const ERC721Soulbound = artifacts.require('ERC721SoulboundExtension');
const ERC721Creator = artifacts.require('MockERC721Creator');
const zeroAddress = '0x0000000000000000000000000000000000000000';

contract('ERC721Soulbound', (accounts) => {
    let creator;
    let soulboundExtension;
    const [owner, recipient, anotherRecipient] = accounts;

    before(async () => {
        creator = await ERC721Creator.new("gm", "GM", { from: owner, gas: 9000000 });
        soulboundExtension = await ERC721Soulbound.new();
        await creator.registerExtension(soulboundExtension.address, "https://example.com/tokenURI/", { from: owner });
    });

    it('Should mint a new Soulbound token to the recipient', async () => {
        await soulboundExtension.mintToken(creator.address, recipient, 'https://example.com/tokenURI/1', { from: owner });

        const balance = await creator.balanceOf(recipient, { from: owner });
        assert.equal(balance.toString(), '1', 'Balance should be 1 after minting');
    });

    it('Should mint Soulbound tokens to multiple recipients', async () => {
        const recipients = [recipient, anotherRecipient];
        const uris = ['https://example.com/tokenURI/1', 'https://example.com/tokenURI/2'];

        await soulboundExtension.mintTokens(creator.address, recipients, uris, { from: owner });

        const balance1 = await creator.balanceOf(recipient);
        assert.equal(balance1.toString(), '2', 'Expected balance should be 2 after minting');

        const balance2 = await creator.balanceOf(anotherRecipient);
        assert.equal(balance2.toString(), '1', 'Expected balance should be 1 after minting');
    });

    it('Should return soulbound owners', async () => {
        const soulboundOwners = await soulboundExtension.getSoulboundOwners(creator.address, { from: owner });

        assert.equal(soulboundOwners.length, 2, 'Expected 2 soulbound owners');
        assert.equal(soulboundOwners[0], recipient, 'Expected first owner to match recipient');
        assert.equal(soulboundOwners[1], anotherRecipient, 'Expected second owner should match anotherRecipient');
    });

    describe('Soulbound Transfer Behavior Tests', () => {
        let tokenId;

        before(async () => {
            await soulboundExtension.mintToken(creator.address, recipient, 'https://example.com/tokenURI/3', { from: owner });
            const events = await creator.getPastEvents("Transfer");
            const event = events.find((event) => event.returnValues.to === recipient);
            tokenId = event.returnValues.tokenId;
        });

        it('Should return true if a tokenId is Soulbound', async () => {
            const isSoulbound = await soulboundExtension.isSoulboundToken(creator.address, tokenId);

            assert.equal(isSoulbound, true, 'Expected token to be Soulbound');
        });

        it('Should not allow token to be transferred', async () => {
            await truffleAssert.reverts(
                creator.transferFrom(recipient, anotherRecipient, tokenId, { from: recipient })
            );
        });

        describe('Transfer Approval Extension Disabled Tests', () => {
            it('Should disable the approve transfer extension and make the token Non-Soulbound', async () => {
                await soulboundExtension.setApproveTransfer(creator.address, false);

                const approveExtensionAddress = await creator.getApproveTransfer();
                assert.equal(approveExtensionAddress, zeroAddress, 'Expected extension state should be zero address after setting');
            });

            it('Should allow transfers to any address if the approval extension is not set', async () => {
                await creator.transferFrom(recipient, anotherRecipient, tokenId, { from: recipient });
                const owner = await creator.ownerOf(tokenId);

                assert.equal(owner, anotherRecipient, 'Expected owner to match anotherRecipient');
            });
        });

        describe('Transfer Approval Extension Enabled Tests', () => {
            before(async () => {
                // Re-enable the Approval Extension, so the Token is Soulbound again
                await soulboundExtension.setApproveTransfer(creator.address, true);
            });

            it('Should allow transfers if the transfer to address is the zero address', async () => {
                await creator.burn(tokenId, { from: anotherRecipient });
                await truffleAssert.reverts(
                    creator.ownerOf(tokenId),
                );
            })
        });
    });
});
