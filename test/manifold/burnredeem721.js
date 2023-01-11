const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721BurnRedeem = artifacts.require("ERC721BurnRedeem");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const ethers = require('ethers');

contract('ERC721BurnRedeem', function ([...accounts]) {
  const [owner, anotherOwner, anyone1, anyone2, anyone3, anyone4, anyone5, anyone6, anyone7] = accounts;
  describe('BurnRedeem', function () {
    let creator, burnRedeem, burnable721;
    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", {from:owner});
      burnRedeem = await ERC721BurnRedeem.new({from:owner});
      burnable721 = await ERC721Creator.new("Test", "TEST", {from:owner});
      burnable721_2 = await ERC721Creator.new("Test", "TEST", {from:owner});
      
      // Must register with empty prefix in order to set per-token uri's
      await creator.registerExtension(burnRedeem.address, {from:owner});
    });


    it('access test', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      // Must be admin
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
          identical: true,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [],
        },
        {from:anyone1}
      ), "Wallet is not an admin");

      // Succeeds because admin
      await truffleAssert.passes(await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
          identical: true,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [],
        },
        {from:owner}
      ));
    });

    it('initializeBurnRedeem input sanitization test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp; // seconds since unix epoch
      let later = now + 1000;

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: now,
          totalSupply: 10,
          identical: true,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [],
        },
        {from:owner}
      ), "startDate after endDate");

      // Cannot update non-existant burn redeem
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
          identical: true,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [],
        },
        {from:owner}
      ), "Burn redeem not initialized");
    });

    it('updateBurnRedeem input sanitization test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp; // seconds since unix epoch
      let later = now + 1000;

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
          identical: true,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [],
        },
        {from:owner}
      );

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: now,
          totalSupply: 10,
          identical: true,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [],
        },
        {from:owner}
      ), "startDate after endDate");
    });

    it('tokenURI test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
          identical: true,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 1,
                  contractAddress: burnable721.address,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {from:owner}
      );

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });

      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 1, 0, []]);
      await burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1});

      assert.equal('XXX', await creator.tokenURI(1));

      await burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
          identical: false,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 1,
                  contractAddress: burnable721.address,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {from:owner}
      );

      assert.equal('XXX/1', await creator.tokenURI(1));
    });

    it('onERC721Received test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 1, 0, []]);

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });
      await burnable721_2.mintBase(anyone1, { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(1, balance);
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
          identical: false,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 1,
                  contractAddress: burnable721.address,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {from:owner}
      );

      // Reverts due to wrong contract
      await truffleAssert.reverts(burnable721_2.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}), "Invalid burn token");

      // Passes with right token id
      await truffleAssert.passes(burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/minted
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(1, balance);
    });

    it('burnRedeem test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      for (let i = 0; i < 3; i++) {
        await burnable721.mintBase(anyone1, { from: owner });
        await burnable721_2.mintBase(anyone1, { from: owner });
      }

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(3, balance);
      balance = await burnable721_2.balanceOf(anyone1);
      assert.equal(3, balance);

      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['uint256'], [3]));
      merkleElements.push(ethers.utils.solidityPack(['uint256'], [10]));
      merkleElements.push(ethers.utils.solidityPack(['uint256'], [15]));
      merkleElements.push(ethers.utils.solidityPack(['uint256'], [20]));
      merkleTreeWithValues = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
          identical: false,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 1,
                  contractAddress: burnable721.address,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            },
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 2,
                  contractAddress: burnable721_2.address,
                  minTokenId: 1,
                  maxTokenId: 2,
                  merkleRoot: ethers.utils.formatBytes32String("")
                },
                {
                  validationType: 3,
                  contractAddress: burnable721_2.address,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: merkleTreeWithValues.getHexRoot()
                }
              ]
            }
          ],
        },
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});
      await burnable721_2.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Reverts due to unmet requirements
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          {from:anyone1}
        ),
        "Invalid number of tokens"
      );

      // Reverts due to too many tokens
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable721_2.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable721_2.address,
              id: 2,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1}
        ),
        "Invalid number of tokens"
      );

      // Reverts when token ID out of range
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable721_2.address,
              id: 3,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1}
        ),
        "Invalid token ID"
      );

      // Reverts with invalid merkle proof
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 1,
              contractAddress: burnable721_2.address,
              id: 3,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1}
        ),
        "Invalid merkle proof"
      );

      // Passes with met requirements - range
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable721_2.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1}
        )
      );

      // Passes with met requirements - merkle proof
      const merkleLeaf = keccak256(ethers.utils.solidityPack(['uint256'], [3]));
      const merkleProof = merkleTreeWithValues.getHexProof(merkleLeaf);
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 2,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 1,
              contractAddress: burnable721_2.address,
              id: 3,
              merkleProof: merkleProof
            },
          ],
          {from:anyone1}
        )
      );

      // Ensure tokens are burned/minted
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(1, balance);
      balance = await burnable721_2.balanceOf(anyone1);
      assert.equal(1, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(2, balance);
    });
  });
});
