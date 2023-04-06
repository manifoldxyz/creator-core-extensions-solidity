const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require("truffle-assertions");
const ERC721Creator = artifacts.require("@manifoldxyz/creator-core-solidity/ERC721Creator");
const ERC721Collectible = artifacts.require("ERC721Collectible");
const { BigNumber } = require("ethers");
const MockManifoldMembership = artifacts.require("MockManifoldMembership");

const { signTransactionWithAmount, signTransaction } = require("../helpers/signatureHelpers");
const MINT_FEE = BigNumber.from("690000000000000");

contract("Collectible721", function (accounts) {
  const name = "Token";
  const symbol = "NFT";
  const [paymentReceiver, collectibleOwner, owner, signer, another, anyone1, anyone2, anyone3, anyone4, anyone5] = accounts;
  const INSTANCE_ID = 1;
  const TOKEN_ID = 3;

  describe("Collectible721", function () {
    var creator;
    var collectible;
    var tokenPrice = 100;
    var transactionLimit = 5;
    var purchaseLimit = 5;
    var presalePurchaseLimit = 3;
    var presaleTokenPrice = 50;
    let manifoldMembership;
    const initializationParameters = {
      useDynamicPresalePurchaseLimit: false,
      transactionLimit,
      purchaseMax: 10,
      purchaseRemaining: 0,
      purchaseLimit,
      presalePurchaseLimit,
      purchasePrice: tokenPrice,
      presalePurchasePrice: presaleTokenPrice,
      signingAddress: signer,
      paymentReceiver: paymentReceiver,
    };
    const activationParameters = {
      startTime: Date.now(),
      duration: 1000000,
      presaleInterval: 0,
      claimStartTime: 0,
      claimEndTime: 0,
    };

    beforeEach(async () => {
      creator = await ERC721Creator.new(name, symbol, { from: owner });
      collectible = await ERC721Collectible.new({
        from: collectibleOwner,
      });
      manifoldMembership = await MockManifoldMembership.new({ from: owner });
      await collectible.setMembershipAddress(manifoldMembership.address, { from: collectibleOwner });
      await creator.registerExtension(collectible.address, "", { from: owner });
    });

    it("access test", async function () {
      await truffleAssert.reverts(
        collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, { from: another }),
        "Wallet is not an administrator for contract"
      );
      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, { from: owner });
      await truffleAssert.reverts(
        collectible.activate(creator.address, INSTANCE_ID, activationParameters, { from: another }),
        "Wallet is not an administrator for contract"
      );
      await truffleAssert.reverts(
        collectible.deactivate(creator.address, INSTANCE_ID, { from: another }),
        "Wallet is not an administrator for contract"
      );
      await truffleAssert.reverts(
        collectible.methods["premint(address,uint256,uint16)"](creator.address, INSTANCE_ID, 1, { from: another }),
        "Wallet is not an administrator for contract"
      );
      await truffleAssert.reverts(
        collectible.methods["premint(address,uint256,address[])"](creator.address, INSTANCE_ID, [], { from: another }),
        "Wallet is not an administrator for contract"
      );
      await truffleAssert.reverts(
        collectible.setApproveTransfer(creator.address, true, { from: another }),
        "Wallet is not an administrator for contract"
      );
      await truffleAssert.reverts(
        collectible.setTransferLocked(creator.address, INSTANCE_ID, false, { from: another }),
        "Wallet is not an administrator for contract"
      );
      await truffleAssert.reverts(
        collectible.withdraw(another, 0, { from: another }),
        "AdminControl: Must be owner or admin"
      );
      await truffleAssert.reverts(
        collectible.setTokenURIPrefix(creator.address, INSTANCE_ID, "", { from: another }),
        "Wallet is not an administrator for contract"
      );
      await truffleAssert.reverts(
        collectible.updateInitializationParameters(creator.address, INSTANCE_ID, initializationParameters, {
          from: another,
        }),
        "Wallet is not an administrator for contract"
      );
      await truffleAssert.reverts(
        collectible.setMembershipAddress(manifoldMembership.address, {
          from: another,
        }),
        "AdminControl: Must be owner or admin"
      );
    });

    it("functionality test with purchase limit", async function () {
      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, {
        from: owner,
      });
      // // Transfers must be allowed while approving the collectible for transfers
      await collectible.setApproveTransfer(creator.address, true, { from: owner });
      // // Now I can turn off transfers
      await collectible.setTransferLocked(creator.address, INSTANCE_ID, true, { from: owner });

      // Activate.
      await collectible.methods["premint(address,uint256,uint16)"](creator.address, INSTANCE_ID, 2, { from: owner });
      await collectible.methods["premint(address,uint256,address[])"](creator.address, INSTANCE_ID, [anyone1, anyone2], {
        from: owner,
      });
      assert.equal(await creator.balanceOf(owner), 2);
      assert.equal(await creator.balanceOf(anyone1), 1);
      assert.equal(await creator.balanceOf(anyone2), 1);
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, "0x0", "0x0", "0x0", {
          from: anyone1,
          value: MINT_FEE.add(tokenPrice),
        }),
        "Inactive"
      );

      // Start sale at future date
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        {
          ...activationParameters,
          startTime,
        },
        { from: owner }
      );
      await truffleAssert.reverts(
        collectible.methods["premint(address,uint256,uint16)"](creator.address, INSTANCE_ID, 2, { from: owner }),
        "Already active"
      );
      await truffleAssert.reverts(
        collectible.methods["premint(address,uint256,address[])"](creator.address, INSTANCE_ID, [anyone1, anyone2], {
          from: owner,
        }),
        "Already active"
      );
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, "0x0", "0x0", "0x0", {
          from: anyone1,
          value: MINT_FEE.add(tokenPrice),
        }),
        "Purchasing not active"
      );
      await helper.advanceTimeAndBlock(100);
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, purchaseLimit + 1, "0x0", "0x0", "0x0", {
          from: anyone3,
          value: MINT_FEE.add(tokenPrice).mul(purchaseLimit + 1),
        }),
        "Too many requested"
      );

      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, purchaseLimit, "0x0", "0x0", "0x0", {
          from: anyone3,
          value: MINT_FEE.add(tokenPrice),
        }),
        "Invalid purchase amount sent"
      );

      // Test data signing.  IRL, the following message/signature generation would happen server side
      let nonce = web3.utils.padLeft("0x24356e65", 64);
      let { message, signature } = await signTransaction(anyone3, nonce, signer);

      let badSig = (await signTransaction(anyone3, nonce, owner)).signature;

      // Not allowed to steal someone else's request
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
          from: anyone1,
          value: MINT_FEE.add(tokenPrice),
        }),
        "Malformed message"
      );
      // Bad signature
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, message, badSig, nonce, {
          from: anyone3,
          value: MINT_FEE.add(tokenPrice),
        }),
        "Invalid signature"
      );
      // Ok
      var tx = await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(tokenPrice),
      });
      assert.equal(await creator.balanceOf(anyone3), 1);
      // Cannot replay
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
          from: anyone3,
          value: MINT_FEE.add(tokenPrice),
        }),
        "Cannot replay transaction"
      );
      assert.equal(true, await collectible.nonceUsed(creator.address, INSTANCE_ID, nonce));

      nonce = web3.utils.padLeft("0x24356e66", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await collectible.purchase(creator.address, INSTANCE_ID, purchaseLimit - 1, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(tokenPrice).mul(purchaseLimit - 1),
      });

      nonce = web3.utils.padLeft("0x24356e67", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, "0x0", "0x0", "0x0", {
          from: anyone3,
          value: MINT_FEE.add(tokenPrice),
        }),
        "Too many requested"
      );

      // Buy the rest of the tokens
      nonce = web3.utils.padLeft("0x24356e68", 64);
      ({ message, signature } = await signTransaction(anyone4, nonce, signer));
      const tokensRemaining = await collectible.purchaseRemaining(creator.address, INSTANCE_ID);
      await collectible.purchase(creator.address, INSTANCE_ID, tokensRemaining, message, signature, nonce, {
        from: anyone4,
        value: MINT_FEE.add(tokenPrice).mul(tokensRemaining.toNumber()),
      });

      // Sold out
      nonce = web3.utils.padLeft("0x24356e69", 64);
      ({ message, signature } = await signTransaction(anyone5, nonce, signer));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, "0x0", "0x0", "0x0", {
          from: anyone5,
          value: MINT_FEE.add(tokenPrice),
        }),
        "Too many requested"
      );
      // Transfers are locked so this reverts
      await truffleAssert.reverts(
        creator.safeTransferFrom(anyone1, anyone4, TOKEN_ID, { from: anyone1 }),
        "Extension approval failure"
      );

      // Renable transfers
      await collectible.setTransferLocked(creator.address, INSTANCE_ID, false, { from: owner });

      // Transfers work because they are enabled
      await creator.safeTransferFrom(anyone1, anyone4, TOKEN_ID, { from: anyone1 });
      await creator.safeTransferFrom(anyone4, anyone1, TOKEN_ID, { from: anyone4 });
    });

    it("withdraw test", async function () {
      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, {
        from: owner,
      });
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        {
          ...activationParameters,
          startTime,
        },
        { from: owner }
      );
      await helper.advanceTimeAndBlock(100);

      let nonce = web3.utils.padLeft("0x24356e65", 64);
      let { message, signature } = await signTransaction(anyone3, nonce, signer);

      const creatorBalanceBefore = await web3.eth.getBalance(paymentReceiver);
      await collectible.purchase(creator.address, INSTANCE_ID, 2, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(tokenPrice).mul(2),
      });
      const creatorBalanceAfter = await web3.eth.getBalance(paymentReceiver);
      assert(
        BigNumber.from(creatorBalanceAfter.toString())
          .sub(creatorBalanceBefore.toString())
          .eq(BigNumber.from(tokenPrice).mul(2))
      );
      await truffleAssert.reverts(
        collectible.withdraw(collectibleOwner, MINT_FEE.add(tokenPrice).mul(2), {
          from: anyone3,
        }),
        "AdminControl: Must be owner or admin"
      );

      // request too many
      await truffleAssert.reverts(
        collectible.withdraw(anyone4, MINT_FEE.add(tokenPrice).mul(100), {
          from: collectibleOwner,
        }),
        "Failed to transfer to receiver"
      );

      const contractBalance = await web3.eth.getBalance(collectible.address);
      assert.equal(BigNumber.from(contractBalance.toString()).toString(), MINT_FEE.mul(2).toString());
      const balanceBefore = await web3.eth.getBalance(anyone1);
      await collectible.withdraw(anyone1, MINT_FEE.mul(2), {
        from: collectibleOwner,
      });
      const balanceAfter = await web3.eth.getBalance(anyone1);
      assert.equal(
        BigNumber.from(balanceAfter.toString()).sub(balanceBefore.toString()).toString(),
        MINT_FEE.mul(2).toString()
      );
    });

    it("membership test", async function () {
      await manifoldMembership.setMember(anyone1, true, { from: owner });
      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, {
        from: owner,
      });
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        {
          ...activationParameters,
          startTime,
        },
        { from: owner }
      );
      await helper.advanceTimeAndBlock(100);

      let nonce = web3.utils.padLeft("0x24356e65", 64);
      let { message, signature } = await signTransaction(anyone1, nonce, signer);

      await collectible.purchase(creator.address, INSTANCE_ID, 2, message, signature, nonce, {
        from: anyone1,
        value: tokenPrice * 2,
      });
      assert.equal(await creator.balanceOf(anyone1), 2);
    });

    it("transaction limit test", async function () {
      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, {
        from: owner,
      });

      // Start sale at future date
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        {
          ...activationParameters,
          startTime,
        },
        { from: owner }
      );
      await helper.advanceTimeAndBlock(100);

      let nonce = web3.utils.padLeft("0x24356e65", 64);
      let { message, signature } = await signTransaction(anyone3, nonce, signer);

      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, transactionLimit + 1, message, signature, nonce, {
          from: anyone3,
          value: MINT_FEE.add(tokenPrice).mul(transactionLimit + 1),
        }),
        "Too many requested"
      );
      // Ok
      var tx = await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(tokenPrice),
      });
      console.log("purchase gas cost:", tx.receipt.gasUsed);
      assert.equal(await creator.balanceOf(anyone3), 1);
    });

    it("claim test", async function () {
      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, {
        from: owner,
      });
      // Start sale at future date
      var latestBlock = (await web3.eth.getBlock("latest")).timestamp;
      var claimStartTime = latestBlock + 10;
      var claimEndTime = latestBlock + 50;
      var startTime = latestBlock + 100;
      var duration = 1000;

      await truffleAssert.reverts(
        collectible.activate(
          creator.address,
          INSTANCE_ID,
          {
            ...activationParameters,
            startTime,
            duration,
            claimStartTime: startTime - 50,
            claimEndTime: startTime - 100,
          },
          { from: owner }
        ),
        "Invalid claim times"
      );
      await truffleAssert.reverts(
        collectible.activate(
          creator.address,
          INSTANCE_ID,
          {
            ...activationParameters,
            startTime,
            duration,
            claimStartTime: startTime - 50,
            claimEndTime: startTime + 1,
          },
          { from: owner }
        ),
        "Invalid claim times"
      );
      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        {
          ...activationParameters,
          startTime,
          duration,
          claimStartTime,
          claimEndTime,
        },
        {
          from: owner,
        }
      );

      let nonce = web3.utils.padLeft("0x24356e65", 64);
      let amount = 5;
      let { signature, message } = await signTransactionWithAmount(anyone3, nonce, signer, amount);
      await truffleAssert.reverts(
        collectible.claim(creator.address, INSTANCE_ID, amount, message, signature, nonce, {
          from: anyone3,
          value: MINT_FEE.mul(amount),
        }),
        "Outside claim period"
      );
      await helper.advanceTimeAndBlock(10);
      await truffleAssert.reverts(
        collectible.claim(creator.address, INSTANCE_ID, amount + 1, message, signature, nonce, {
          from: anyone3,
          value: MINT_FEE.mul(amount + 1),
        }),
        "Malformed message"
      );

      // Ok
      var tx = await collectible.claim(creator.address, INSTANCE_ID, amount, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.mul(amount),
      });
      console.log("claim gas cost:", tx.receipt.gasUsed);
      assert.equal(await creator.balanceOf(anyone3), 5);
    });

    it("presale test", async function () {
      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, {
        from: owner,
      });
      // Start sale at future date
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      var presaleInterval = 100;
      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        { ...activationParameters, startTime, presaleInterval },
        { from: owner }
      );
      await helper.advanceTimeAndBlock(110);
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, presalePurchaseLimit + 1, "0x0", "0x0", "0x0", {
          from: anyone3,
          value: MINT_FEE.add(presaleTokenPrice).mul(presalePurchaseLimit + 1),
        }),
        "Too many requested"
      );
      // Test data signing.  IRL, the following message/signature generation would happen server side
      let nonce = web3.utils.padLeft("0x24356e65", 64);
      let { message, signature } = await signTransaction(anyone3, nonce, signer);
      let badSig = (await signTransaction(anyone3, nonce, owner)).signature;
      await collectible.purchase(creator.address, INSTANCE_ID, presalePurchaseLimit - 1, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(presaleTokenPrice).mul(presalePurchaseLimit - 1),
      });
      assert.equal(await creator.balanceOf(anyone3), presalePurchaseLimit - 1);
      // Can make another purchase during presale
      nonce = web3.utils.padLeft("0x24356e66", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(presaleTokenPrice),
      });
      // Cannot make purchase over limit during presale
      nonce = web3.utils.padLeft("0x24356e67", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
          from: anyone3,
          value: MINT_FEE.add(presaleTokenPrice),
        }),
        "Too many requested"
      );
      // Can make purchase after presale
      await helper.advanceTimeAndBlock(presaleInterval - 10 + 1);
      await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(tokenPrice),
      });
      assert.equal(await creator.balanceOf(anyone3), presalePurchaseLimit + 1);
    });

    it("presale test - no limit", async function () {
      // Start sale at future date
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      var presaleInterval = 100;

      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, {
        from: owner,
      });
      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        { ...activationParameters, startTime, presaleInterval },
        { from: owner }
      );
      await helper.advanceTimeAndBlock(110);

      // Test data signing.  IRL, the following message/signature generation would happen server side
      let nonce = web3.utils.padLeft("0x24356e65", 64);
      let { message, signature } = await signTransaction(anyone3, nonce, signer);
      let badSig = (await signTransaction(anyone3, nonce, owner)).signature;

      await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(presaleTokenPrice),
      });
      assert.equal(await creator.balanceOf(anyone3), 1);

      // Can make another purchase during presale
      nonce = web3.utils.padLeft("0x24356e66", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(presaleTokenPrice),
      });
    });

    it("presale test - dynamic limit", async function () {
      // Start sale at future date
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      var presaleInterval = 500;

      await collectible.initializeCollectible(
        creator.address,
        INSTANCE_ID,
        { ...initializationParameters, useDynamicPresalePurchaseLimit: true },
        {
          from: owner,
        }
      );
      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        { ...activationParameters, startTime, presaleInterval },
        { from: owner }
      );
      await helper.advanceTimeAndBlock(110);

      // Can purchase
      let nonce = web3.utils.padLeft("0x24356e65", 64);
      ({ signature, message } = await signTransactionWithAmount(anyone1, nonce, signer, 2));
      await collectible.purchase(creator.address, INSTANCE_ID, 2, message, signature, nonce, {
        from: anyone1,
        value: MINT_FEE.add(presaleTokenPrice).mul(2),
      });
      assert.equal(await creator.balanceOf(anyone1), 2);
      // Can purchase beyond static presale purchase limit
      nonce = web3.utils.padLeft("0x24356e66", 64);
      ({ signature, message } = await signTransactionWithAmount(anyone2, nonce, signer, presalePurchaseLimit + 1));
      await collectible.purchase(creator.address, INSTANCE_ID, presalePurchaseLimit + 1, message, signature, nonce, {
        from: anyone2,
        value: MINT_FEE.add(presaleTokenPrice).mul(presalePurchaseLimit + 1),
      });
      assert.equal(await creator.balanceOf(anyone2), presalePurchaseLimit + 1);

      // Cannot purchase without including amount in message
      nonce = web3.utils.padLeft("0x24356e67", 64);
      ({ signature, message } = await signTransaction(anyone3, nonce, signer));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 2, message, signature, nonce, {
          from: anyone3,
          value: MINT_FEE.add(presaleTokenPrice).mul(2),
        }),
        "Malformed message"
      );

      // Can purchase after presale without including amount in message
      await helper.advanceTimeAndBlock(presaleInterval - 10 + 1);
      nonce = web3.utils.padLeft("0x24356e68", 64);
      ({ signature, message } = await signTransaction(anyone4, nonce, signer));
      await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone4,
        value: MINT_FEE.add(tokenPrice),
      });
      assert.equal(await creator.balanceOf(anyone4), 1);

      // Cannot purchase after presale including amount in message
      nonce = web3.utils.padLeft("0x24356e69", 64);
      ({ signature, message } = await signTransactionWithAmount(anyone5, nonce, signer, 1));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
          from: anyone5,
          value: MINT_FEE.add(tokenPrice),
        }),
        "Malformed message"
      );
    });

    it("modify sale properties", async function () {
      var transactionLimit = 5;
      let [
        purchasePrice,
        _transactionLimit,
        purchaseLimit,
        presalePurchasePrice,
        presalePurchaseLimit,
        useDynamicPresalePurchaseLimit,
      ] = [tokenPrice, tokenPrice, transactionLimit, transactionLimit, transactionLimit, false];

      await collectible.initializeCollectible(
        creator.address,
        INSTANCE_ID,
        {
          ...initializationParameters,
          purchasePrice,
          presalePurchasePrice,
          presalePurchaseLimit,
          transactionLimit: _transactionLimit,
          useDynamicPresalePurchaseLimit,
        },
        {
          from: owner,
        }
      );
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      var presaleInterval = 100;
      purchasePrice -= 1;
      _transactionLimit -= 1;
      purchaseLimit -= 1;
      presalePurchasePrice -= 1;
      presalePurchaseLimit -= 1;
      useDynamicPresalePurchaseLimit = !useDynamicPresalePurchaseLimit;

      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        { ...activationParameters, startTime, presaleInterval },
        { from: owner }
      );
      await truffleAssert.reverts(
        collectible.updateInitializationParameters(
          creator.address,
          INSTANCE_ID,
          {
            ...initializationParameters,
            purchasePrice,
            purchaseLimit,
            transactionLimit: _transactionLimit,
            presalePurchasePrice,
            presalePurchaseLimit,
            useDynamicPresalePurchaseLimit,
          },
          {
            from: owner,
          }
        ),
        "Already active"
      );
      await collectible.deactivate(creator.address, INSTANCE_ID, { from: owner });
      await collectible.updateInitializationParameters(
        creator.address,
        INSTANCE_ID,
        {
          ...initializationParameters,
          purchasePrice,
          purchaseLimit,
          transactionLimit: _transactionLimit,
          presalePurchasePrice,
          presalePurchaseLimit,
          useDynamicPresalePurchaseLimit,
        },
        {
          from: owner,
        }
      );
      const state = await collectible.state(creator.address, INSTANCE_ID);

      assert.equal(state.purchasePrice, purchasePrice);
      assert.equal(state.purchaseLimit, purchaseLimit);
      assert.equal(state.transactionLimit, _transactionLimit);
      assert.equal(state.presalePurchasePrice, presalePurchasePrice);
      assert.equal(state.presalePurchaseLimit, presalePurchaseLimit);
      assert.equal(state.useDynamicPresalePurchaseLimit, useDynamicPresalePurchaseLimit);
    });

    it("token URI tests", async function () {
      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, {
        from: owner,
      });

      // Start sale at future date
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      await collectible.activate(
        creator.address,
        INSTANCE_ID,
        {
          ...activationParameters,
          startTime,
        },
        { from: owner }
      );
      await helper.advanceTimeAndBlock(100);
      let amount = 2;
      let nonce = web3.utils.padLeft("0x24356e65", 64);
      let { message, signature } = await signTransaction(anyone3, nonce, signer);
      await collectible.purchase(creator.address, INSTANCE_ID, amount, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(tokenPrice).mul(amount),
      });

      await collectible.setTokenURIPrefix(creator.address, INSTANCE_ID, "collectible-extension-prefix/", { from: owner });

      assert.equal(await creator.tokenURI(1), `collectible-extension-prefix/1`);
      assert.equal(await creator.tokenURI(2), `collectible-extension-prefix/2`);
      await creator.mintBase(anyone1, { from: owner });
      await creator.mintBase(anyone1, { from: owner });
      await creator.mintBase(anyone1, { from: owner });
      assert.equal(await creator.tokenURI(3), `3`);
      assert.equal(await creator.tokenURI(4), `4`);
      assert.equal(await creator.tokenURI(5), `5`);
      nonce = web3.utils.padLeft("0x24356e66", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await collectible.purchase(creator.address, INSTANCE_ID, amount, message, signature, nonce, {
        from: anyone3,
        value: MINT_FEE.add(tokenPrice).mul(amount),
      });
      assert.equal(await creator.tokenURI(6), `collectible-extension-prefix/3`);
      assert.equal(await creator.tokenURI(7), `collectible-extension-prefix/4`);
    });
  });
});
