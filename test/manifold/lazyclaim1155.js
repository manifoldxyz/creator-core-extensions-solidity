const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC1155LazyClaim = artifacts.require("ERC1155LazyClaim");
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const ethers = require('ethers');

contract('LazyClaim', function ([...accounts]) {
  const [owner, anotherOwner, anyone1, anyone2, anyone3, anyone4, anyone5, anyone6, anyone7] = accounts;
  describe('LazyClaim', function () {
    let creator, lazyClaim;
    beforeEach(async function () {
      creator = await ERC1155Creator.new({from:owner});
      lazyClaim = await ERC1155LazyClaim.new({from:owner});
      
      // Must register with empty prefix in order to set per-token uri's
      await creator.registerExtension(lazyClaim.address, {from:owner});
    });


    it('access test', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      // Must be admin
      await truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:anyone1}
      ), "Wallet is not an administrator for contract");

      // Succeeds because admin
      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      );
    });

    it('initializeClaim input sanitization test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp; // seconds since unix epoch
      let later = now + 1000;

      // Fails due to invalid storage protocol
      await truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 1,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 0,
        },
        {from:owner}
      ), "Cannot initialize with invalid storage protocol");

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: now,
          storageProtocol: 1,
        },
        {from:owner}
      ), "Cannot have startDate greater than or equal to endDate");

      // Fails due to merkle root being set with walletMax
      await truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String("0x0"),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      ), "Cannot provide both mintsPerWallet and merkleRoot");

      // Cannot update non-existant claim
      await truffleAssert.reverts(lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      ), "Claim not initialized");
    });

    it('updateClaim input sanitization test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      );

      // Fails due to invalid storage protocol
      await truffleAssert.reverts(lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 0,
        },
        {from:owner}
      ), "Cannot set invalid storage protocol");

      // Fails due to modifying totalMax
      await truffleAssert.reverts(lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 9,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      ), "Cannot decrease totalMax");

      // Fails due to decreasing walletMax
      await truffleAssert.reverts(lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      ), "Cannot decrease walletMax");

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: now,
          storageProtocol: 1,
        },
        {from:owner}
      ), "Cannot have startDate greater than or equal to endDate");
    });

    it('merkle mint test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 2]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 3]));
      merkleTreeWithValues = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });

      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 3,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      );

      const balanceOfCreator = await creator.balanceOf(owner, 1)
      assert.equal(balanceOfCreator, 1);

      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof1 = merkleTreeWithValues.getHexProof(merkleLeaf1);

      // Merkle validation failure
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 1, merkleProof1, {from:anyone1}), "Could not verify merkle proof");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, {from:anyone2}), "Could not verify merkle proof");

      await lazyClaim.mint(creator.address, 1, 0, merkleProof1, {from:anyone1});
      // Cannot mint with same mintIndex again
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, {from:anyone1}), "Already minted");

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      const merkleProof2 = merkleTreeWithValues.getHexProof(merkleLeaf2);
      await lazyClaim.mint(creator.address, 1, 1, merkleProof2, {from:anyone2});
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 2]));
      const merkleProof3 = merkleTreeWithValues.getHexProof(merkleLeaf3);
      await lazyClaim.mint(creator.address, 1, 2, merkleProof3, {from:anyone2});

      const merkleLeaf4 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 3]));
      const merkleProof4 = merkleTreeWithValues.getHexProof(merkleLeaf4);
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 3, merkleProof4, {from:anyone3}), "Maximum tokens already minted for this claim");

      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 4,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      )
      await lazyClaim.mint(creator.address, 1, 3, merkleProof4, {from:anyone3});
    });

    it('merkle mint test - batch', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 2]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 3]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 4]));
      merkleTreeWithValues = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });

      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 3,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      );

      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof1 = merkleTreeWithValues.getHexProof(merkleLeaf1);

      // Merkle validation failure
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [0], [merkleProof1], {from:anyone1}), "Invalid input");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [0, 0], [merkleProof1], {from:anyone1}), "Invalid input");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [0], [merkleProof1, merkleProof1], {from:anyone1}), "Invalid input");

      await lazyClaim.mintBatch(creator.address, 1, 1, [0], [merkleProof1], {from:anyone1});
      // Cannot mint with same mintIndex again
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, {from:anyone1}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [0], [merkleProof1], {from:anyone1}), "Already minted");

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      const merkleProof2 = merkleTreeWithValues.getHexProof(merkleLeaf2);
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 2]));
      const merkleProof3 = merkleTreeWithValues.getHexProof(merkleLeaf3);
      const merkleLeaf4 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 3]));
      const merkleProof4 = merkleTreeWithValues.getHexProof(merkleLeaf4);
      const merkleLeaf5 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 4]));
      const merkleProof5 = merkleTreeWithValues.getHexProof(merkleLeaf5);

      // Cannot steal someone else's merkleproof
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [1,3], [merkleProof2,merkleProof4], {from:anyone2}), "Could not verify merkle proof");

      const mintTx = await lazyClaim.mintBatch(creator.address, 1, 2, [1,2], [merkleProof2,merkleProof3], {from:anyone2});
      console.log("Gas cost:\tBatch mint 2:\t"+ mintTx.receipt.gasUsed);

      // base mint something in between
      await creator.mintBaseNew([anyone5], [1], [""], {from: owner});

      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [3], [merkleProof4], {from:anyone3}), "Too many requested for this claim");

      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 4,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      )
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [3,4], [merkleProof4,merkleProof5], {from:anyone3}), "Too many requested for this claim");

      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 5,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      )
      // Cannot mint with same mintIndex again
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 1, merkleProof2, {from:anyone2}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 2, merkleProof3, {from:anyone2}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [1,2], [merkleProof2,merkleProof3], {from:anyone2}), "Already minted");
      
      await lazyClaim.mintBatch(creator.address, 1, 2, [3,4], [merkleProof4,merkleProof5], {from:anyone3});

      let balance1 = await creator.balanceOf(anyone1, 1);
      assert.equal(1,balance1);
      let balance2 = await creator.balanceOf(anyone2, 1);
      assert.equal(2,balance2);
      let balance3 = await creator.balanceOf(anyone3, 1);
      assert.equal(2,balance3);

      // Check URI's
      assert.equal(await creator.uri(1), 'XXX');
    });

    it('non-merkle mint test - batch', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 5,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      );

      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 4, [], [], {from:anyone1}), "Too many requested for this wallet");
      await lazyClaim.mintBatch(creator.address, 1, 3, [], [], {from:anyone1});
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [], [], {from:anyone1}), "Too many requested for this wallet");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 3, [], [], {from:anyone2}), "Too many requested for this claim");
      await lazyClaim.mintBatch(creator.address, 1, 2, [], [], {from:anyone2});

    });

    it('gas test - no merkle tree', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      const initializeTx = await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 11,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      );
      console.log("Gas cost:\tinitialize:\t"+ initializeTx.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBaseNew([anyone1], [1], [""], { from: owner });

      // Mint 2 tokens using the extension
      const mintTx = await lazyClaim.mint(creator.address, 1, 0, [], {from:anyone2});
      console.log("Gas cost:\tfirst mint:\t"+ mintTx.receipt.gasUsed);

      const mintTx2 = await lazyClaim.mint(creator.address, 1, 0, [], {from:anyone3});
      console.log("Gas cost:\tsecond mint:\t"+ mintTx2.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBaseNew([anyone4], [1], [""], { from: owner });

      // Mint 1 token using the extension
      const mintTx3 = await lazyClaim.mint(creator.address, 1, 0, [], {from:anyone5});
      console.log("Gas cost:\tthird mint:\t"+ mintTx3.receipt.gasUsed);
    });

    it('gas test - with merkle tree', async function () {
      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 1]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone5, 2]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone6, 256]));
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });

      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      const initializeTx = await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 0,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      );
      console.log("Gas cost:\tinitialize:\t"+ initializeTx.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBaseNew([anyone1], [1], [""],{ from: owner });

      // Mint 2 tokens using the extension
      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      const merkleProof1 = merkleTree.getHexProof(merkleLeaf1);
      const mintTx = await lazyClaim.mint(creator.address, 1, 0, merkleProof1, {from:anyone2});
      console.log("Gas cost:\tfirst mint:\t"+ mintTx.receipt.gasUsed);

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 1]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      const mintTx2 = await lazyClaim.mint(creator.address, 1, 1, merkleProof2, {from:anyone3});
      console.log("Gas cost:\tsecond mint:\t"+ mintTx2.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBaseNew([anyone4], [1], [""], { from: owner });

      // Mint 1 token using the extension
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone5, 2]));
      const merkleProof3 = merkleTree.getHexProof(merkleLeaf3);
      const mintTx3 = await lazyClaim.mint(creator.address, 1, 2, merkleProof3, {from:anyone5});
      console.log("Gas cost:\tthird mint:\t"+ mintTx3.receipt.gasUsed);

      // Mint 1 token using the extension
      const merkleLeaf4 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone6, 256]));
      const merkleProof4 = merkleTree.getHexProof(merkleLeaf4);
      const mintTx4 = await lazyClaim.mint(creator.address, 1, 256, merkleProof4, {from:anyone6});
      console.log("Gas cost:\tfourth mint:\t"+ mintTx4.receipt.gasUsed);
    });

    it('tokenURI test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 11,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
        },
        {from:owner}
      );
      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBaseNew([anyone1], [1], [""], { from: owner });

      // Mint 2 tokens using the extension
      await lazyClaim.mint(creator.address, 1, 0, [], {from:anyone2});
      await lazyClaim.mint(creator.address, 1, 0, [], {from:anyone3});

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBaseNew([anyone4], [1], [""], { from: owner });

      // Mint 1 token using the extension
      await lazyClaim.mint(creator.address, 1, 0, [], {from:anyone5});

      assert.equal('XXX', await creator.uri(1));
    });

    it('functionality test', async function() {

      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 2]));
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });

      // Test initializing a new claim
      let start = (await web3.eth.getBlock('latest')).timestamp+100; // seconds since unix epoch
      let end = start + 300;

      // Should fail to initialize if non-admin wallet is used
      truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "zero.com",
          totalMax: 3,
          walletMax: 1,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
        },
        {from:anotherOwner}
      ), "Wallet is not an administrator for contract");

      // Cannot claim before initialization
      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof1 = merkleTree.getHexProof(merkleLeaf1);
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, {from:anyone1}), "Claim not initialized");

      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "arweaveHash1",
          totalMax: 3,
          walletMax: 0,
          startDate: start,
          endDate: end,
          storageProtocol: 2,
        },
        {from:owner}
      );

      // Overwrite the claim with parameters changed
      await lazyClaim.updateClaim(
        creator.address,
        1, // the index of the claim we want to edit
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "arweaveHash1",
          totalMax: 3,
          walletMax: 0,
          startDate: start,
          endDate: end + 1,
          storageProtocol: 2,
        },
        {from:owner}
      );

      // Initialize a second claim - with optional parameters disabled
      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
          location: "arweaveHash2",
          totalMax: 0,
          walletMax: 0,
          startDate: 0,
          endDate: 0,
          storageProtocol: 2,
        },
        {from:owner}
      );
    
      // Claim should have expected info
      const claim = await lazyClaim.getClaim(creator.address, 1, {from:owner});
      assert.equal(claim.merkleRoot, merkleTree.getHexRoot());
      assert.equal(claim.location, 'arweaveHash1');
      assert.equal(claim.totalMax, 3);
      assert.equal(claim.walletMax, 0);
      assert.equal(claim.startDate, start);
      assert.equal(claim.endDate, end + 1);

      // Test minting

      // Mint a token to random wallet
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, {from:anyone1}), "Transaction before start date");
      await helper.advanceTimeAndBlock(start+1-(await web3.eth.getBlock('latest')).timestamp+1);
      await lazyClaim.mint(creator.address, 1, 0, merkleProof1, {from:anyone1});


      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      await lazyClaim.mint(creator.address, 1, 1, merkleProof2, {from:anyone2});

      // Now ensure that the creator contract state is what we expect after mints
      let balance = await creator.balanceOf(anyone1, 1);
      assert.equal(1,balance);
      let balance2 = await creator.balanceOf(anyone2, 1);
      assert.equal(1,balance2);
      let tokenURI = await creator.uri(1);
      assert.equal('https://arweave.net/arweaveHash1', tokenURI);

      // Additionally test that tokenURIs are dynamic
      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "test.com",
          totalMax: 3,
          walletMax: 1,
          startDate: start,
          endDate: end + 1,
          storageProtocol: 1,
        },
        {from:owner}
      );

      let newTokenURI = await creator.uri(1);
      assert.equal('test.com', newTokenURI);

      // Optional parameters - using claim 2
      await lazyClaim.mint(creator.address, 2, 0, [], {from:anyone1});
      await lazyClaim.mint(creator.address, 2, 0, [], {from:anyone1});
      await lazyClaim.mint(creator.address, 2, 0, [], {from:anyone2});

      // end claim period
      await helper.advanceTimeAndBlock(end+2-(await web3.eth.getBlock('latest')).timestamp+1);
      // Reverts due to end of mint period
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 2]));
      const merkleProof3 = merkleTree.getHexProof(merkleLeaf3);
      truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 2, merkleProof3, {from:anyone3}), "Transaction after end date");
    });
  });
});