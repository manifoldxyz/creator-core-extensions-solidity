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
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:anyone1}
      ), "Wallet is not an administrator for contract");

      // Succeeds because admin
      await truffleAssert.passes(await burnRedeem.initializeBurnRedeem(
        creator.address,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
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

      // Fails due to invalid storage protocol
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 0,
          location: "XXX",
        },
        {from:owner}
      ), "Cannot initialize with invalid storage protocol");

      // Fails due to non 1155 address
      const mock721 = await MockERC721.new('Test', 'TEST', {from:owner});
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        {
          burnableTokenAddress: mock721.address,
          burnableTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      ), "burnableTokenAddress must be a ERC1155Creator contract");

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: now,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      ), "Cannot have startDate greater than or equal to endDate");

      // Cannot update non-existant burn redeem
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
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
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
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

      // Fails due to invalid storage protocol
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 0,
          location: "XXX",
        },
        {from:owner}
      ), "Cannot set invalid storage protocol");

      // Fails due to modifying totalSupply
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 9,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      ), "Cannot decrease totalSupply");

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 10,
          startDate: now,
          endDate: now,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:owner}
      ), "Cannot have startDate greater than or equal to endDate");
    });

    it('tokenURI test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
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

      assert.equal('XXX', await creator.uri(1));
    });

    // // Mint a token using creator contract, to test breaking up extension's indexRange
      // await creator.mintBaseNew([anyone1], [1], [""], { from: owner });

      // // Mint burnable token
      // await burnable1155.mintBaseNew([anyone1], [1], [""], { from: owner });

      // // Approve extension
      // await burnable1155.setApprovalForAll(burnRedeem.address, true, { from: anyone1 });
      
      // // Burn redeem using the extension
      // await burnRedeem.mint(creator.address, 1, 1, {from:anyone1});

    it('functionality test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp+100; // seconds since unix epoch
      let end = start + 300;

      // Should fail to initialize if non-admin wallet is used
      truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
          burnAmount: 1,
          redeemAmount: 1,
          totalSupply: 3,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          location: "XXX",
        },
        {from:anotherOwner}
      ), "Wallet is not an administrator for contract");

      // Should fail before initialization
      await truffleAssert.reverts(burnRedeem.mint(creator.address, 1, 0, {from:anyone1}), "Burn redeem not initialized");

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
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
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
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
        {
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
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
      assert.equal(initializedBurnRedeem.location, 'arweaveHash1');
      assert.equal(initializedBurnRedeem.totalSupply, 3);
      assert.equal(initializedBurnRedeem.startDate, start);
      assert.equal(initializedBurnRedeem.endDate, end + 1);

      // Test minting

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });

      // Approve extension
      await burnable1155.setApprovalForAll(burnRedeem.address, true, { from: anyone1 });

      // Burn/redeem
      await truffleAssert.reverts(burnRedeem.mint(creator.address, 1, 0, {from:anyone1}), "Transaction before start date");
      await helper.advanceTimeAndBlock(start+1-(await web3.eth.getBlock('latest')).timestamp+1);
      // index 1
      await burnRedeem.mint(creator.address, 1, 1, {from:anyone1});


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
          burnableTokenAddress: burnable1155.address,
          burnableTokenId: 1,
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
      truffleAssert.reverts(burnRedeem.mint(creator.address, 1, 1, {from:anyone1}), "Transaction after end date");
    });
  });
});
