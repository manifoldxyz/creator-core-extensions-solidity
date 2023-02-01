const truffleAssert = require('truffle-assertions');
const ERC1155BurnRedeem = artifacts.require("ERC1155BurnRedeem");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator');
const ethers = require('ethers');

contract('ERC1155BurnRedeem', function ([...accounts]) {
  const [owner, anyone1] = accounts;
  describe('BurnRedeem', function () {
    let creator, burnRedeem, burnable1155;
    beforeEach(async function () {
      creator = await ERC1155Creator.new("Test", "TEST", {from:owner});
      burnRedeem = await ERC1155BurnRedeem.new("Test", "TEST", {from:owner});
      burnable1155 = await ERC1155Creator.new("Test", "TEST", {from:owner});
      burnable1155_2 = await ERC1155Creator.new("Test", "TEST", {from:owner});
      burnable721 = await ERC721Creator.new("Test", "TEST", {from:owner});
      burnable721_2 = await ERC721Creator.new("Test", "TEST", {from:owner});
      
      // Must register with empty prefix in order to set per-token uri's
      await creator.registerExtension(burnRedeem.address, {from:owner});
    });


    it('access test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      // Must be admin
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: []
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
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
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: []
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
        },
        {from:owner}
      ));
    });

    it('initializeBurnRedeem input sanitization test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: now,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: []
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
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
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: []
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
        },
        {from:owner}
      ), "Burn redeem not initialized");
    });

    it('updateBurnRedeem input sanitization test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: []
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
        },
        {from:owner}
      );
      
      // Fails due to non multiple of totalSupply
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: []
        },
        {
          redeemAmount: 3,
          redeemTokenId: 0,
        },
        {from:owner}
      ), "Remainder left from totalSupply");

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: now,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: []
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
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
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 1,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 1,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
        },
        {from:owner}
      );

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });

      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 1, 0, []]);
      await burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1});

      assert.equal('XXX', await creator.uri(1));
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
      let balance = await creator.balanceOf(anyone1, 1);
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
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
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
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(1, balance);
    });

    it('onERC11555Received test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 1, 0, []]);

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });
      await burnable1155_2.mintBaseNew([anyone1], [2], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1, 1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(2, balance);
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 1,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 2,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
        },
        {from:owner}
      );

      // Reverts due to wrong contract
      await truffleAssert.reverts(burnable1155_2.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}), "Invalid burn token");

      // Passes with right token id
      await truffleAssert.passes(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(0, balance);
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(1, balance);
    });

    it('onERC11555BatchReceived test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(
        ["address", "uint256", {
          "BurnToken[]": {
            "groupIndex": "uint48",
            "itemIndex": "uint48",
            "contractAddress": "address",
            "id": "uint256",
            "merkleProof": "bytes32[]"
          }
        }],
        [creator.address, 1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable1155.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 0,
              itemIndex: 1,
              contractAddress: burnable1155.address,
              id: 2,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ]
        ]
      );

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1, 1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(2, balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(2, balance);
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          burnSet: [
            {
              requiredCount: 2,
              items: [
                {
                  validationType: 2,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 2,
                  minTokenId: 1,
                  maxTokenId: 1,
                  merkleRoot: ethers.utils.formatBytes32String("")
                },
                {
                  validationType: 2,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 2,
                  minTokenId: 2,
                  maxTokenId: 2,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          redeemAmount: 1,
          redeemTokenId: 0,
        },
        {from:owner}
      );

      // Passes with right token id
      await truffleAssert.passes(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [2, 2], burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(0, balance);
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(1, balance);
    });
  });
});
