const helper = require("../helpers/truffleTestHelper");
const ERC1155SerendipityWithAllowlist = artifacts.require("ERC1155SerendipityWithAllowlist");
const MockERC1155CreatorCore = artifacts.require("MockERC1155CreatorCore");
const { keccak256 } = require("@ethersproject/keccak256");
const { MerkleTree } = require("merkletreejs");

contract('ERC1155SerendipityWithAllowlist', function ([...accounts]) {
    const [
        owner,
        creator,
        minter1,
        minter2,
        minter3,
        anyone
    ] = accounts;

    describe('ERC1155SerendipityWithAllowlist', function () {
        let creatorCore;
        let serendipity;
        let merkleTree;
        let merkleRoot;
        let leaf1, leaf2, leaf3;
        let proof1, proof2, proof3;

        beforeEach(async function () {
            creatorCore = await MockERC1155CreatorCore.new({ from: creator });
            serendipity = await ERC1155SerendipityWithAllowlist.new(owner, { from: owner });
            await creatorCore.registerExtension(serendipity.address, "override", { from: creator });

            // Create merkle tree for allowlist
            leaf1 = keccak256(web3.eth.abi.encodeParameters(['address', 'uint32'], [minter1, 0]));
            leaf2 = keccak256(web3.eth.abi.encodeParameters(['address', 'uint32'], [minter2, 1]));
            leaf3 = keccak256(web3.eth.abi.encodeParameters(['address', 'uint32'], [minter3, 2]));
            
            merkleTree = new MerkleTree([leaf1, leaf2, leaf3], keccak256, { sort: true });
            merkleRoot = merkleTree.getHexRoot();
            
            proof1 = merkleTree.getHexProof(leaf1);
            proof2 = merkleTree.getHexProof(leaf2);
            proof3 = merkleTree.getHexProof(leaf3);
        });

        it('should initialize claim with allowlist', async function () {
            const instanceId = 1;
            const claimParameters = {
                storageProtocol: 1, // ARWEAVE
                totalMax: 100,
                startDate: Math.floor(Date.now() / 1000) - 1000,
                endDate: Math.floor(Date.now() / 1000) + 1000,
                tokenVariations: 3,
                location: "test-location",
                paymentReceiver: creator,
                cost: web3.utils.toWei("0.01", "ether"),
                erc20: "0x0000000000000000000000000000000000000000",
                merkleRoot: merkleRoot,
                walletMax: 0 // Not used for merkle claims
            };

            await serendipity.initializeClaim(
                creatorCore.address,
                instanceId,
                claimParameters,
                { from: creator }
            );

            const claim = await serendipity.getClaim(creatorCore.address, instanceId);
            assert.equal(claim.merkleRoot, merkleRoot);
            assert.equal(claim.totalMax, 100);
        });

        it('should allow merkle minting with valid proof', async function () {
            const instanceId = 1;
            const claimParameters = {
                storageProtocol: 1,
                totalMax: 100,
                startDate: Math.floor(Date.now() / 1000) - 1000,
                endDate: Math.floor(Date.now() / 1000) + 1000,
                tokenVariations: 3,
                location: "test-location",
                paymentReceiver: creator,
                cost: web3.utils.toWei("0.01", "ether"),
                erc20: "0x0000000000000000000000000000000000000000",
                merkleRoot: merkleRoot,
                walletMax: 0
            };

            await serendipity.initializeClaim(
                creatorCore.address,
                instanceId,
                claimParameters,
                { from: creator }
            );

            const mintCost = web3.utils.toBN(web3.utils.toWei("0.01", "ether"));
            const mintFee = web3.utils.toBN("500000000000000");
            const totalCost = mintCost.add(mintFee);

            await serendipity.mintReserve(
                creatorCore.address,
                instanceId,
                0, // mintIndex
                proof1,
                1, // mintCount
                {
                    from: minter1,
                    value: totalCost
                }
            );

            // Verify mint was successful
            const claim = await serendipity.getClaim(creatorCore.address, instanceId);
            assert.equal(claim.total.toString(), "1");

            // Verify index is now used
            const isUsed = await serendipity.checkMintIndex(creatorCore.address, instanceId, 0);
            assert.equal(isUsed, true);
        });

        it('should reject invalid merkle proof', async function () {
            const instanceId = 1;
            const claimParameters = {
                storageProtocol: 1,
                totalMax: 100,
                startDate: Math.floor(Date.now() / 1000) - 1000,
                endDate: Math.floor(Date.now() / 1000) + 1000,
                tokenVariations: 3,
                location: "test-location",
                paymentReceiver: creator,
                cost: web3.utils.toWei("0.01", "ether"),
                erc20: "0x0000000000000000000000000000000000000000",
                merkleRoot: merkleRoot,
                walletMax: 0
            };

            await serendipity.initializeClaim(
                creatorCore.address,
                instanceId,
                claimParameters,
                { from: creator }
            );

            const mintCost = web3.utils.toBN(web3.utils.toWei("0.01", "ether"));
            const mintFee = web3.utils.toBN("500000000000000");
            const totalCost = mintCost.add(mintFee);

            try {
                await serendipity.mintReserve(
                    creatorCore.address,
                    instanceId,
                    0, // mintIndex for minter1
                    proof2, // but using proof for minter2
                    1,
                    {
                        from: minter1,
                        value: totalCost
                    }
                );
                assert.fail("Should have reverted");
            } catch (error) {
                assert(error.message.includes("Could not verify merkle proof"));
            }
        });

        it('should prevent double minting with same index', async function () {
            const instanceId = 1;
            const claimParameters = {
                storageProtocol: 1,
                totalMax: 100,
                startDate: Math.floor(Date.now() / 1000) - 1000,
                endDate: Math.floor(Date.now() / 1000) + 1000,
                tokenVariations: 3,
                location: "test-location",
                paymentReceiver: creator,
                cost: web3.utils.toWei("0.01", "ether"),
                erc20: "0x0000000000000000000000000000000000000000",
                merkleRoot: merkleRoot,
                walletMax: 0
            };

            await serendipity.initializeClaim(
                creatorCore.address,
                instanceId,
                claimParameters,
                { from: creator }
            );

            const mintCost = web3.utils.toBN(web3.utils.toWei("0.01", "ether"));
            const mintFee = web3.utils.toBN("500000000000000");
            const totalCost = mintCost.add(mintFee);

            // First mint should succeed
            await serendipity.mintReserve(
                creatorCore.address,
                instanceId,
                0,
                proof1,
                1,
                {
                    from: minter1,
                    value: totalCost
                }
            );

            // Second mint with same index should fail
            try {
                await serendipity.mintReserve(
                    creatorCore.address,
                    instanceId,
                    0,
                    proof1,
                    1,
                    {
                        from: minter1,
                        value: totalCost
                    }
                );
                assert.fail("Should have reverted");
            } catch (error) {
                assert(error.message.includes("Already minted"));
            }
        });

        it('should handle non-merkle claims with wallet limits', async function () {
            const instanceId = 2;
            const claimParameters = {
                storageProtocol: 1,
                totalMax: 100,
                startDate: Math.floor(Date.now() / 1000) - 1000,
                endDate: Math.floor(Date.now() / 1000) + 1000,
                tokenVariations: 3,
                location: "test-location",
                paymentReceiver: creator,
                cost: web3.utils.toWei("0.01", "ether"),
                erc20: "0x0000000000000000000000000000000000000000",
                merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000", // No merkle
                walletMax: 5
            };

            await serendipity.initializeClaim(
                creatorCore.address,
                instanceId,
                claimParameters,
                { from: creator }
            );

            const mintCost = web3.utils.toBN(web3.utils.toWei("0.01", "ether"));
            const mintFee = web3.utils.toBN("500000000000000");
            const totalCost = mintCost.add(mintFee).mul(web3.utils.toBN("3"));

            // Should be able to mint 3 tokens
            await serendipity.mintReserve(
                creatorCore.address,
                instanceId,
                3, // mintCount
                {
                    from: minter1,
                    value: totalCost
                }
            );

            const totalMints = await serendipity.getTotalMints(creatorCore.address, instanceId, minter1);
            assert.equal(totalMints.toString(), "3");
        });
    });
});