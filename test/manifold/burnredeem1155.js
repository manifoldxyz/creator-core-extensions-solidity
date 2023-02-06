const truffleAssert = require('truffle-assertions');
const ERC1155BurnRedeem = artifacts.require("ERC1155BurnRedeem");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator');
const ethers = require('ethers');

const MANIFOLD_FEE = ethers.BigNumber.from('690000000000000');

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
      await burnable1155.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      await burnRedeem.burnRedeem(
        creator.address,
        1,
        [
          {
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: burnable1155.address,
            id: 1,
            merkleProof: [ethers.utils.formatBytes32String("")]
          },
        ],
        {from:anyone1, value: MANIFOLD_FEE}
      )


      assert.equal('XXX', await creator.uri(1));
    });
  });
});
