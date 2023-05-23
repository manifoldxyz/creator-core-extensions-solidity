const truffleAssert = require('truffle-assertions');
const ERC1155BurnRedeem = artifacts.require("ERC1155BurnRedeem");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator');
const ethers = require('ethers');
const MockManifoldMembership = artifacts.require('MockManifoldMembership');

const BURN_FEE = ethers.BigNumber.from('690000000000000');

contract('ERC1155BurnRedeem', function ([...accounts]) {
  const [owner, burnRedeemOwner, anyone1] = accounts;
  describe('BurnRedeem', function () {
    let creator, burnRedeem, burnable1155;
    beforeEach(async function () {
      creator = await ERC1155Creator.new("Test", "TEST", {from:owner});
      burnRedeem = await ERC1155BurnRedeem.new(burnRedeemOwner, {from:owner});
      manifoldMembership = await MockManifoldMembership.new({from:owner});
      await burnRedeem.setMembershipAddress(manifoldMembership.address);
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
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: anyone1,
          burnSet: []
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
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: []
        },
        {from:owner}
      ));

      // Fails because not admin
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: anyone1,
          burnSet: []
        },
        {from:anyone1}
      ), "Wallet is not an admin");

      // Fails because not admin
      await truffleAssert.reverts(burnRedeem.updateURI(
        creator.address,
        1,
        1,
        "",
        {from:anyone1}
      ), "Wallet is not an admin");
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
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: []
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
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: []
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
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: []
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
          redeemAmount: 3,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: []
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
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: []
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
          redeemAmount: 1,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
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
        {from:owner}
      );

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });
      await burnable1155.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      await burnRedeem.burnRedeem(
        creator.address,
        1,
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
        {from:anyone1, value: BURN_FEE}
      )


      assert.equal('XXX', await creator.uri(1));
    });

    it('onERC1155Received test - multiple redemptions', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint32", "uint256", "bytes32[]"], [creator.address, 1, 2, 0, []]);

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [10], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1, 1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(10, balance);

      await truffleAssert.reverts(
        burnRedeem.getBurnRedeemForToken(
          creator.address,
          1
        ),
        "Token does not exist"
      )

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 2,
          totalSupply: 6,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
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
        {from:owner}
      );

      // Get burn redeem for token, should succeed
      const burnRedeemInfo = await burnRedeem.getBurnRedeemForToken(creator.address, 1)
      assert.equal(burnRedeemInfo[0], 1);
      const burnRedeemForToken = burnRedeemInfo[1];
      assert.equal(burnRedeemForToken.contractVersion, 0);

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Passes with value == 2 * burnItem.amount (2 redemptions)
      await truffleAssert.passes(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(8, balance);
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(4, balance);

      // Passes with value == 2 * burnItem.amount (2 redemptions), but only 1 redemption left
      await truffleAssert.passes(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/returned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      // Only 1 redemption left, so 1 token is returned
      assert.equal(7, balance);
      balance = await creator.balanceOf(anyone1, 1);
      assert.equal(6, balance);

      // Reverts with no redemptions left
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "No tokens available");
    });
  });
});
