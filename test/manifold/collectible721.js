const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require("truffle-assertions");
const ERC721Creator = artifacts.require("@manifoldxyz/creator-core-collectibles-solidity/ERC721Creator");
const ERC721Collectible = artifacts.require("ERC721Collectible");

const { signTransactionWithAmount, signTransaction } = require("../helpers/signatureHelpers");

contract("Collectible721", function ([creator, ...accounts]) {
  const name = "Token";
  const symbol = "NFT";
  const [collectibleOwner, owner, signer, another, anyone1, anyone2, anyone3, anyone4, anyone5] = accounts;
  const INSTANCE_ID = 1;
  const TOKEN_ID = 3;

  describe("Collectible721", function () {
    var creator;
    var collectible;
    var maxTokens = 10;
    var tokenPrice = 100;
    var transactionLimit = 5;
    var purchaseLimit = 5;
    var presalePurchaseLimit = 3;
    var presaleTokenPrice = 50;
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
      paymentReceiver: anyone5,
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
        collectible.modifyInitializationParameters(creator.address, INSTANCE_ID, initializationParameters, {
          from: another,
        }),
        "Wallet is not an administrator for contract"
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
        collectible.purchase(creator.address, INSTANCE_ID, 1, "0x0", "0x0", "0x0", { from: anyone1, value: tokenPrice }),
        "Inactive"
      );

      // Start sale at future date
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      var duration = 1000;
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
        collectible.purchase(creator.address, INSTANCE_ID, 1, "0x0", "0x0", "0x0", { from: anyone1, value: tokenPrice }),
        "Purchasing not active"
      );
      await helper.advanceTimeAndBlock(100);
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, purchaseLimit + 1, "0x0", "0x0", "0x0", {
          from: anyone3,
          value: (purchaseLimit + 1) * tokenPrice,
        }),
        "Too many requested"
      );
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, purchaseLimit, "0x0", "0x0", "0x0", {
          from: anyone3,
          value: tokenPrice,
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
          value: tokenPrice,
        }),
        "Malformed message"
      );
      // Bad signature
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, message, badSig, nonce, { from: anyone3, value: tokenPrice }),
        "Invalid signature"
      );
      // Ok
      var tx = await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: tokenPrice,
      });
      assert.equal(await creator.balanceOf(anyone3), 1);
      // Cannot replay
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
          from: anyone3,
          value: tokenPrice,
        }),
        "Cannot replay transaction"
      );
      assert.equal(true, await collectible.nonceUsed(creator.address, INSTANCE_ID, nonce));

      nonce = web3.utils.padLeft("0x24356e66", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await collectible.purchase(creator.address, INSTANCE_ID, purchaseLimit - 1, message, signature, nonce, {
        from: anyone3,
        value: (purchaseLimit - 1) * tokenPrice,
      });

      nonce = web3.utils.padLeft("0x24356e67", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, "0x0", "0x0", "0x0", { from: anyone3, value: tokenPrice }),
        "Too many requested"
      );

      // Buy the rest of the tokens
      nonce = web3.utils.padLeft("0x24356e68", 64);
      ({ message, signature } = await signTransaction(anyone4, nonce, signer));
      const tokensRemaining = await collectible.purchaseRemaining(creator.address, INSTANCE_ID);
      await collectible.purchase(creator.address, INSTANCE_ID, tokensRemaining, message, signature, nonce, {
        from: anyone4,
        value: tokensRemaining * tokenPrice,
      });

      // Sold out
      nonce = web3.utils.padLeft("0x24356e69", 64);
      ({ message, signature } = await signTransaction(anyone5, nonce, signer));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, "0x0", "0x0", "0x0", { from: anyone5, value: tokenPrice }),
        "Too many requested"
      );

      // Withraw testing
      await collectible.withdraw(another, 0, { from: collectibleOwner });

      // Transfers are locked so this reverts
      await truffleAssert.reverts(
        creator.safeTransferFrom(anyone1, anyone4, TOKEN_ID, { from: anyone1 }),
        " Extension approval failure"
      );

      // Renable transfers
      await collectible.setTransferLocked(creator.address, INSTANCE_ID, false, { from: owner });

      // Transfers work because they are enabled
      await creator.safeTransferFrom(anyone1, anyone4, TOKEN_ID, { from: anyone1 });
      await creator.safeTransferFrom(anyone4, anyone1, TOKEN_ID, { from: anyone4 });
    });

    it("transaction limit test", async function () {
      await collectible.initializeCollectible(creator.address, INSTANCE_ID, initializationParameters, {
        from: owner,
      });

      // Start sale at future date
      var startTime = (await web3.eth.getBlock("latest")).timestamp + 100;
      var duration = 1000;
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
          value: tokenPrice * (transactionLimit + 1),
        }),
        "Too many requested"
      );
      // Ok
      var tx = await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: tokenPrice,
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
        collectible.claim(creator.address, INSTANCE_ID, amount, message, signature, nonce, { from: anyone3 }),
        "Outside claim period"
      );
      await helper.advanceTimeAndBlock(10);
      await truffleAssert.reverts(
        collectible.claim(creator.address, INSTANCE_ID, amount + 1, message, signature, nonce, { from: anyone3 }),
        "Malformed message"
      );

      // Ok
      var tx = await collectible.claim(creator.address, INSTANCE_ID, amount, message, signature, nonce, { from: anyone3 });
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
          value: (presalePurchaseLimit + 1) * presaleTokenPrice,
        }),
        "Too many requested"
      );
      // Test data signing.  IRL, the following message/signature generation would happen server side
      let nonce = web3.utils.padLeft("0x24356e65", 64);
      let { message, signature } = await signTransaction(anyone3, nonce, signer);
      let badSig = (await signTransaction(anyone3, nonce, owner)).signature;
      await collectible.purchase(creator.address, INSTANCE_ID, presalePurchaseLimit - 1, message, signature, nonce, {
        from: anyone3,
        value: presaleTokenPrice * (presalePurchaseLimit - 1),
      });
      assert.equal(await creator.balanceOf(anyone3), presalePurchaseLimit - 1);
      // Can make another purchase during presale
      nonce = web3.utils.padLeft("0x24356e66", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: presaleTokenPrice,
      });
      // Cannot make purchase over limit during presale
      nonce = web3.utils.padLeft("0x24356e67", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
          from: anyone3,
          value: presaleTokenPrice,
        }),
        "Too many requested"
      );
      // Can make purchase after presale
      await helper.advanceTimeAndBlock(presaleInterval - 10 + 1);
      await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: tokenPrice,
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
        value: presaleTokenPrice,
      });
      assert.equal(await creator.balanceOf(anyone3), 1);

      // Can make another purchase during presale
      nonce = web3.utils.padLeft("0x24356e66", 64);
      ({ message, signature } = await signTransaction(anyone3, nonce, signer));
      await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone3,
        value: presaleTokenPrice,
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
        value: presaleTokenPrice * 2,
      });
      assert.equal(await creator.balanceOf(anyone1), 2);
      // Can purchase beyond static presale purchase limit
      nonce = web3.utils.padLeft("0x24356e66", 64);
      ({ signature, message } = await signTransactionWithAmount(anyone2, nonce, signer, presalePurchaseLimit + 1));
      await collectible.purchase(creator.address, INSTANCE_ID, presalePurchaseLimit + 1, message, signature, nonce, {
        from: anyone2,
        value: presaleTokenPrice * (presalePurchaseLimit + 1),
      });
      assert.equal(await creator.balanceOf(anyone2), presalePurchaseLimit + 1);

      // Cannot purchase without including amount in message
      nonce = web3.utils.padLeft("0x24356e67", 64);
      ({ signature, message } = await signTransaction(anyone3, nonce, signer));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 2, message, signature, nonce, {
          from: anyone3,
          value: presaleTokenPrice * 2,
        }),
        "Malformed message"
      );

      // Can purchase after presale without including amount in message
      await helper.advanceTimeAndBlock(presaleInterval - 10 + 1);
      nonce = web3.utils.padLeft("0x24356e68", 64);
      ({ signature, message } = await signTransaction(anyone4, nonce, signer));
      await collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
        from: anyone4,
        value: tokenPrice,
      });
      assert.equal(await creator.balanceOf(anyone4), 1);

      // Cannot purchase after presale including amount in message
      nonce = web3.utils.padLeft("0x24356e69", 64);
      ({ signature, message } = await signTransactionWithAmount(anyone5, nonce, signer, 1));
      await truffleAssert.reverts(
        collectible.purchase(creator.address, INSTANCE_ID, 1, message, signature, nonce, {
          from: anyone5,
          value: tokenPrice,
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
        collectible.modifyInitializationParameters(
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
      await collectible.modifyInitializationParameters(
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
  });
});
