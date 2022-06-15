const truffleAssert = require('truffle-assertions');
const ERC721LazyClaim = artifacts.require("ERC721LazyClaim");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const ethers = require('ethers');

contract('LazyClaim', function ([...accounts]) {
  const [owner, anotherOwner, anyone1, anyone2, anyone3, anyone4, anyone5, anyone6, anyone7] = accounts;
  describe('LazyClaim', function () {
    let creator, lazyClaim;
    let merkleTree;
    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", {from:owner});
      lazyClaim = await ERC721LazyClaim.new({from:owner});
      
      // Must register with empty prefix in order to set per-token uri's
      await creator.registerExtension(lazyClaim.address, {from:owner});

      const merkleElements = [owner, anotherOwner, anyone1, anyone2, anyone3, anyone4, anyone5].map(addr => {
        return ethers.utils.solidityPack(['address', 'uint32'], [addr, 0]);
      });
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });
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
          identical: true
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
          identical: true
        },
        {from:owner}
      );
    });

    it('input sanitization test', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      // Fails due to over 10k totalMax
      await truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10001,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true
        },
        {from:owner}
      ), "Cannot have totalMax greater than 10000");

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
          identical: true
        },
        {from:owner}
      ), "Cannot have startDate greater than or equal to endDate");

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
          identical: true
        },
        {from:owner}
      ), "Claim not initialized");

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
          identical: true
        },
        {from:owner}
      );

      // Fails due to modifying totalMax
      await truffleAssert.reverts(lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 11,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true
        },
        {from:owner}
      ), "Cannot modify totalMax");

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
          identical: true
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
          identical: true
        },
        {from:owner}
      ), "Cannot have startDate greater than or equal to endDate");
    });

    it('merkle values test', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      const merkleElementsWithValues = [owner, anotherOwner, anyone1, anyone2].map(addr => {
        return ethers.utils.solidityPack(['address', 'uint32'], [addr, 2]);
      });
      merkleTreeWithValues = new MerkleTree(merkleElementsWithValues, keccak256, { hashLeaves: true, sortPairs: true });

      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 2,
          walletMax: 2,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true
        },
        {from:owner}
      );

      // Attempt to mint 2 tokens to a whitelisted address
      const merkleLeaf = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 2]));
      const merkleProof = merkleTreeWithValues.getHexProof(merkleLeaf);
      await lazyClaim.mint(creator.address, 1, merkleProof, 2, {from:anyone1});
      await lazyClaim.mint(creator.address, 1, merkleProof, 2, {from:anyone1});

      // Attempt to mint a 3rd, should revert
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, merkleProof, 2, {from:anyone1}));
    });

    it('gas test - no merkle tree', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
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
          identical: true
        },
        {from:owner}
      );
      console.log("Gas cost:\tinitialize:\t"+ initializeTx.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone1, { from: owner });

      // Mint 2 tokens using the extension
      const mintTx = await lazyClaim.mint(creator.address, 1, [], 0, {from:anyone2});
      console.log("Gas cost:\tfirst mint:\t"+ mintTx.receipt.gasUsed);

      const mintTx2 = await lazyClaim.mint(creator.address, 1, [], 0, {from:anyone3});
      console.log("Gas cost:\tsecond mint:\t"+ mintTx2.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone4, { from: owner });

      // Mint 1 token using the extension
      const mintTx3 = await lazyClaim.mint(creator.address, 1, [], 0, {from:anyone5});
      console.log("Gas cost:\tthird mint:\t"+ mintTx3.receipt.gasUsed);
    });

    it('gas test - with merkle tree', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      const initializeTx = await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 11,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true
        },
        {from:owner}
      );
      console.log("Gas cost:\tinitialize:\t"+ initializeTx.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone1, { from: owner });

      // Mint 2 tokens using the extension
      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      const merkleProof1 = merkleTree.getHexProof(merkleLeaf1);
      const mintTx = await lazyClaim.mint(creator.address, 1, merkleProof1, 0, {from:anyone2});
      console.log("Gas cost:\tfirst mint:\t"+ mintTx.receipt.gasUsed);

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 0]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      const mintTx2 = await lazyClaim.mint(creator.address, 1, merkleProof2, 0, {from:anyone3});
      console.log("Gas cost:\tsecond mint:\t"+ mintTx2.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone4, { from: owner });

      // Mint 1 token using the extension
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone5, 0]));
      const merkleProof3 = merkleTree.getHexProof(merkleLeaf3);
      const mintTx3 = await lazyClaim.mint(creator.address, 1, merkleProof3, 0, {from:anyone5});
      console.log("Gas cost:\tthird mint:\t"+ mintTx3.receipt.gasUsed);
    });

    it('tokenURI test', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
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
          identical: false
        },
        {from:owner}
      );
      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone1, { from: owner });

      // Mint 2 tokens using the extension
      await lazyClaim.mint(creator.address, 1, [], 0, {from:anyone2});
      await lazyClaim.mint(creator.address, 1, [], 0, {from:anyone3});

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone4, { from: owner });

      // Mint 1 token using the extension
      await lazyClaim.mint(creator.address, 1, [], 0, {from:anyone5});

      assert.equal('XXX/1', await creator.tokenURI(2));
      assert.equal('XXX/2', await creator.tokenURI(3));
      assert.equal('XXX/3', await creator.tokenURI(5));
    });

    it('functionality test', async function() {
      // Test initializing a new claim
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      // Should fail to initialize if non-admin wallet is used
      truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "zero.com",
          totalMax: 3,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true
        },
        {from:anotherOwner}
      ), "Wallet is not an administrator for contract");

      // Cannot claim before initialization
      const merkleLeaf = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof = merkleTree.getHexProof(merkleLeaf);
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone1}), "Claim not initialized");

      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "arweaveHash1",
          totalMax: 3,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 2,
          identical: true
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
          walletMax: 1,
          startDate: now,
          endDate: later + 1,
          storageProtocol: 2,
          identical: true
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
          identical: true
        },
        {from:owner}
      );
    
      // Claim should have expected info
      const count = await lazyClaim.getClaimCount(creator.address, {from:owner});
      assert.equal(count, 2);
      const claim = await lazyClaim.getClaim(creator.address, 1, {from:owner});
      assert.equal(claim.merkleRoot, merkleTree.getHexRoot());
      assert.equal(claim.location, 'arweaveHash1');
      assert.equal(claim.totalMax, 3);
      assert.equal(claim.walletMax, 1);
      assert.equal(claim.startDate, now);
      assert.equal(claim.endDate, later + 1);

      // Test minting

      // Mint a token to random wallet
      await lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone1});

      // Minting with an invalid proof should revert
      truffleAssert.reverts(lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone2}), "Could not verify merkle proof");

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      await lazyClaim.mint(creator.address, 1, merkleProof2, 0, {from:anyone2});

      // Now ensure that the creator contract state is what we expect after mints
      let balance = await creator.balanceOf(anyone1, {from:anyone3});
      assert.equal(1,balance);
      let balance2 = await creator.balanceOf(anyone2, {from:anyone3});
      assert.equal(1,balance2);
      let tokenURI = await creator.tokenURI(1);
      assert.equal('https://arweave.net/arweaveHash1', tokenURI);
      let tokenOwner = await creator.ownerOf(1);
      assert.equal(anyone1, tokenOwner);

      // Additionally test that tokenURIs are dynamic
      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "test.com",
          totalMax: 3,
          walletMax: 1,
          startDate: now,
          endDate: later + 1,
          storageProtocol: 1,
          identical: false
        },
        {from:owner}
      );

      let newTokenURI = await creator.tokenURI(1);
      assert.equal('test.com/1', newTokenURI);

      // Try to mint again with wallet limit of 1, should revert
      truffleAssert.reverts(lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone1}), "Maximum tokens already minted for this wallet");
      // Increase wallet max to 3
      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "test.com",
          totalMax: 3,
          walletMax: 3,
          startDate: now,
          endDate: later + 1,
          storageProtocol: 1,
          identical: false
        },
        {from:owner}
      );

      // Try to mint again, should succeed
      await lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone1});
      // Try to mint again with total limit of 3, should revert due to totalMax = 3
      truffleAssert.reverts(lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone1}), "Maximum tokens already minted for this claim");

      // Optional parameters - using claim 2
      const garbageMerkleLeaf = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 0]));
      const garbageMerkleProof = merkleTree.getHexProof(garbageMerkleLeaf);
      await lazyClaim.mint(creator.address, 2, garbageMerkleProof, 0, {from:anyone1});
      await lazyClaim.mint(creator.address, 2, garbageMerkleProof, 0, {from:anyone1});
      await lazyClaim.mint(creator.address, 2, garbageMerkleProof, 0, {from:anyone2});
    });
  });
});