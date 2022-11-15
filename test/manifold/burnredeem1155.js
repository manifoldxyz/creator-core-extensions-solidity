const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC1155BurnRedeem = artifacts.require("ERC1155BurnRedeem");
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator');
const MockERC1155 = artifacts.require('@manifoldxyz/creator-core-solidity/MockERC1155');
const MockERC721 = artifacts.require('@manifoldxyz/creator-core-solidity/MockERC721');
const ethers = require('ethers');

contract('ERC1155BurnRedeem', function ([...accounts]) {
  const [owner, anotherOwner, anyone1, anyone2, anyone3, anyone4, anyone5, anyone6, anyone7] = accounts;
  describe('BurnRedeem', function () {
    let creator, burnRedeem, burnable1155;
    beforeEach(async function () {
      creator = await ERC1155Creator.new({from:owner});
      burnRedeem = await ERC1155BurnRedeem.new({from:owner});
      burnable1155 = await ERC1155Creator.new({from:owner});
      
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
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:anyone1}
      ), "Wallet is not an admin");

      // Succeeds because admin
      await truffleAssert.passes(await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      ));
    });

    it('initializeBurnRedeem input sanitization test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp; // seconds since unix epoch
      let later = now + 1000;

      // Fails due to non 1155 address
      const mock721 = await MockERC721.new('Test', 'TEST', {from:owner});
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: mock721.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      ), "burnToken must be ERC1155Creator");

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: now,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      ), "startDate after endDate");

      // Cannot update non-existant burn redeem
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
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
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );
      
      // Fails due to non multiple of totalSupply
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 2,
          totalSupply: 9,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      ), "Remainder left from totalSupply");

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: now,
          storageProtocol: 1,
          location: "XXX",
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
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });

      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1]);
      await burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1});

      assert.equal('XXX', await creator.uri(1));
    });

    it('functionality test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp+100; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1]);

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });

      // Should fail to initialize if non-admin wallet is used
      truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 3,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:anotherOwner}
      ), "Wallet is not an admin");

      // Should fail before initialization
      await truffleAssert.reverts(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "Token not eligible");

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 3,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );

      // Overwrite the claim with parameters changed
      await burnRedeem.updateBurnRedeem(
        creator.address,
        1, // the index of the burn redeem we want to edit
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 3,
          startDate: start,
          endDate: end + 1,
          storageProtocol: 2,
          location: "arweaveHash1",
        },
        {from:owner}
      );

      // Initialize a second claim - with optional parameters disabled
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        2,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 0,
          startDate: 0,
          endDate: 0,
          storageProtocol: 2,
          location: "arweaveHash1",
        },
        {from:owner}
      );
    
      // Burn redeem should have expected info
      const initializedBurnRedeem = await burnRedeem.getBurnRedeem(creator.address, 1, {from:owner});
      assert.equal(initializedBurnRedeem.storageProtocol, 2);
      assert.equal(initializedBurnRedeem.location, "arweaveHash1");
      assert.equal(initializedBurnRedeem.totalSupply, 3);
      assert.equal(initializedBurnRedeem.startDate, start);
      assert.equal(initializedBurnRedeem.endDate, end + 1);

      // Burn/redeem
      await truffleAssert.reverts(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "Transaction before start date");
      await helper.advanceTimeAndBlock(start+1-(await web3.eth.getBlock('latest')).timestamp+1);
      // index 1
      await burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1});


      // Now ensure that the creator contract state is what we expect after mints
      let balance = await creator.balanceOf(anyone1, 1);
      assert.equal(1,balance);
      let tokenURI = await creator.uri(1);
      assert.equal('https://arweave.net/arweaveHash1', tokenURI);

      // Additionally test that tokenURIs are dynamic
      await burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 3,
          startDate: start,
          endDate: end + 1,
          storageProtocol: 1,
          location: "test.com",
        },
        {from:owner}
      );

      let newTokenURI = await creator.uri(1);
      assert.equal('test.com', newTokenURI);

      // end period
      await helper.advanceTimeAndBlock(end+2-(await web3.eth.getBlock('latest')).timestamp+1);
      // Reverts due to end of mint period
      await truffleAssert.reverts(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "Transaction after end date");
    });

    it('onERC1155Received test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1]);

      // Mint 20 burnable tokens
      await burnable1155.mintBaseNew([anyone1], [20], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1, 1);
      assert.equal(0,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(0,balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(20,balance);
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 2,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 5,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );

      // Reverts due to wrong token id
      await truffleAssert.reverts(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "Token not eligible");

      await burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 5,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );

      // Passes with right token id
      await truffleAssert.passes(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(19,balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        2,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 2,
          redeemAmount: 4,
          totalSupply:  12,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256"], [anyone1, creator.address, 2, 1]);

      // Reverts due to invalid amount
      await truffleAssert.reverts(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "Invalid value sent");

      // Multiple burns in one transaction

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 2, creator.address, 2, 1]);

      // Passes with too high of an amount
      await truffleAssert.passes(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 8, burnRedeemData, {from:anyone1}));

      // Ensure excess tokens are returned
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(15,balance);

      // Passes with proper amount
      await truffleAssert.passes(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 4, burnRedeemData, {from:anyone1}));

      // Now ensure that the creator contract state and burnable contract state is what we expect after mints
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(5,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(8,balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(11,balance);

      // Reverts due to total supply reached
      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1]);
      await truffleAssert.reverts(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "None available");
    });

    it('onERC1155BatchReceived test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [20], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [20], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [20], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1, 1);
      assert.equal(0,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(0,balance);
      balance = await creator.balanceOf(anyone1, 3);
      assert.equal(0,balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(20,balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(20,balance);
      balance = await burnable1155.balanceOf(anyone1, 3);
      assert.equal(20,balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        2,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 2,
          burnAmount: 2,
          redeemAmount: 3,
          totalSupply: 9,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        3,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 3,
          burnAmount: 3,
          redeemAmount: 2,
          totalSupply: 10,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );

      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256", "address", "uint256", "uint256", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1, creator.address, 2, 1, creator.address, 3, 1]);

      // Reverts on ids/data mismatch
      await truffleAssert.reverts(burnable1155.safeBatchTransferFrom(anyone1, burnRedeem.address, [3,2,1], [3,2,1], burnRedeemData, {from:anyone1}), "Token not eligible");

      // Reverts on too little amount
      await truffleAssert.reverts(burnable1155.safeBatchTransferFrom(anyone1, burnRedeem.address, [1,2,3], [1,1,1], burnRedeemData, {from:anyone1}));

      // Passes on too large amount
      await truffleAssert.passes(burnable1155.safeBatchTransferFrom(anyone1, burnRedeem.address, [1,2,3], [1,2,4], burnRedeemData, {from:anyone1}));

      // Ensure excess tokens are returned
      balance = await burnable1155.balanceOf(anyone1, 3);
      assert.equal(17,balance);

      // Reverts on invalid token
      await truffleAssert.reverts(burnable1155.safeBatchTransferFrom(anyone1, burnRedeem.address, [1,2,2], [1,2,3], burnRedeemData, {from:anyone1}), "Token not eligible");

      await truffleAssert.passes(burnable1155.safeBatchTransferFrom(anyone1, burnRedeem.address, [1,2,3], [1,2,3], burnRedeemData, {from:anyone1}));

      // Now ensure that the creator contract state and burnable contract state is what we expect after mints
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(2,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(6,balance);
      balance = await creator.balanceOf(anyone1, 3);
      assert.equal(4,balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(18,balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(16,balance);
      balance = await burnable1155.balanceOf(anyone1, 3);
      assert.equal(14,balance);
    });

    it('onERC1155Received edge cases test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint 50 burnable tokens
      await burnable1155.mintBaseNew([anyone1], [50], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1, 1);
      assert.equal(0,balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(50,balance);
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 2,
          redeemAmount: 1,
          totalSupply: 5,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        2,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 2,
          redeemAmount: 1,
          totalSupply: 5,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );

      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1, creator.address, 2, 1]);

      // -- Edge case 1 --
      // Reverts due to less than valid amount

      await truffleAssert.reverts(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 3, burnRedeemData, {from:anyone1}), "Invalid value sent");

      // -- Edge case 2 --
      // Passes when one or more burn redeems are sold out

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256"], [anyone1, creator.address, 2, 5]);
      // Redeem rest of index 2
      await burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 10, burnRedeemData, {from:anyone1})
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(40,balance);

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1, creator.address, 2, 1]);

      // Passes even though 2 is sold out
      await truffleAssert.passes(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 4, burnRedeemData, {from:anyone1}));

      // Ensure tokens from sold out burn redeem are returned and correct tokens are minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(38,balance);
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(5,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(1,balance);

      // -- Edge case 3 --
      // Passes when more than required is sent

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1]);
      await truffleAssert.passes(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 10, burnRedeemData, {from:anyone1}));

      // Ensure excess tokens are returned and correct tokens are minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(36,balance);
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(5,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(2,balance);

      // -- Edge case 4 --
      // Passes when more than total supply is requested

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 5]);
      await truffleAssert.passes(burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 10, burnRedeemData, {from:anyone1}));

      // Ensure excess tokens are returned and correct tokens are minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(30,balance);
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(5,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(5,balance);
    });

    it('onERC1155BatchReceived edge case test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [50], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [50], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [50], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1, 1);
      assert.equal(0,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(0,balance);
      balance = await creator.balanceOf(anyone1, 3);
      assert.equal(0,balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(50,balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(50,balance);
      balance = await burnable1155.balanceOf(anyone1, 3);
      assert.equal(50,balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        2,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 2,
          burnAmount: 2,
          redeemAmount: 3,
          totalSupply: 9,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        3,
        {
          burnTokenAddress: burnable1155.address,
          burnTokenId: 3,
          burnAmount: 3,
          redeemAmount: 2,
          totalSupply: 10,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      );

      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1, creator.address, 2, 1]);

      // -- Edge case 1 --
      // Reverts due to less than valid amount

      await truffleAssert.reverts(burnable1155.safeBatchTransferFrom(anyone1, burnRedeem.address, [1,2], [1,1], burnRedeemData, {from:anyone1}));

      // -- Edge case 2 --
      // Passes when one or more burn redeems are sold out

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 10]);
      // Redeem rest of index 1
      await burnable1155.safeTransferFrom(anyone1, burnRedeem.address, 1, 10, burnRedeemData, {from:anyone1})
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(40,balance);

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256", "address", "uint256", "uint256"], [anyone1, creator.address, 1, 1, creator.address, 2, 1]);

      // Passes even though 1 is sold out
      await truffleAssert.passes(burnable1155.safeBatchTransferFrom(anyone1, burnRedeem.address, [1,2], [1,2], burnRedeemData, {from:anyone1}));

      // Ensure tokens from sold out burn redeem are returned and correct tokens are minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(40,balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(48,balance);
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(10,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(3,balance);

      // -- Edge case 3 --
      // Passes when more than required is sent

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256", "address", "uint256", "uint256"], [anyone1, creator.address, 2, 1, creator.address, 3, 1]);
      await truffleAssert.passes(burnable1155.safeBatchTransferFrom(anyone1, burnRedeem.address, [2,3], [4,3], burnRedeemData, {from:anyone1}));

      // Ensure excess tokens are returned and correct tokens are minted
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(46,balance);
      balance = await burnable1155.balanceOf(anyone1, 3);
      assert.equal(47,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(6,balance);
      balance = await creator.balanceOf(anyone1, 3);
      assert.equal(2,balance);

      // -- Edge case 4 --
      // Passes when more than total supply is requested

      burnRedeemData = web3.eth.abi.encodeParameters(["address", "address", "uint256", "uint256", "address", "uint256", "uint256"], [anyone1, creator.address, 2, 5, creator.address, 3, 1]);
      await truffleAssert.passes(burnable1155.safeBatchTransferFrom(anyone1, burnRedeem.address, [2,3], [10,3], burnRedeemData, {from:anyone1}));

      // Ensure excess tokens are returned and correct tokens are minted
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(44,balance);
      balance = await burnable1155.balanceOf(anyone1, 3);
      assert.equal(44,balance);
      balance = await creator.balanceOf(anyone1, 2);
      assert.equal(9,balance);
      balance = await creator.balanceOf(anyone1, 3);
      assert.equal(4,balance);
    });
  });
});
