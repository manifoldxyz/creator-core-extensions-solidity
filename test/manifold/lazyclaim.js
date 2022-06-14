const truffleAssert = require('truffle-assertions');
const ERC721LazyClaim = artifacts.require("ERC721LazyClaim");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const ethers = require('ethers');

contract('LazyClaim', function ([...accounts]) {
  const [owner, owner2, creatorCore, marketplace, anyone1, anyone2, anyone3, anyone4, anyone5, anyone6, anyone7] = accounts;
  describe('LazyClaim', function () {
    let creator, lazyClaim;
    let merkleTree;
    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", {from:owner});
      lazyClaim = await ERC721LazyClaim.new({from:owner});
      
      // Must register with empty prefix in order to set per-token uri's
      await creator.registerExtension(lazyClaim.address, {from:owner});

      const merkleElements = [owner, owner2, anyone1, anyone2].map(addr => {
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
      ));

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
      ));

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
      ));

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
      await truffleAssert.reverts(lazyClaim.overwriteClaim(
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
      ));

      // Fails due to decreasing walletMax
      await truffleAssert.reverts(lazyClaim.overwriteClaim(
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
      ));

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(lazyClaim.overwriteClaim(
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
      ));
    });

    it('merkle values test', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      const merkleElementsWithValues = [owner, owner2, anyone1, anyone2].map(addr => {
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

    it('gas test', async function () {
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
      // Giving all assertions a 10k gas buffer
      assert(initializeTx.receipt.gasUsed < 118616, "Initialize gas too high");

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone1, { from: owner });

      // Mint 2 tokens using the extension
      const garbageMerkleLeaf = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 0]));
      const garbageMerkleProof = merkleTree.getHexProof(garbageMerkleLeaf);
      const mintTx = await lazyClaim.mint(creator.address, 1, garbageMerkleProof, 0, {from:anyone1});
      console.log("Gas cost:\tfirst mint:\t"+ mintTx.receipt.gasUsed);
      assert(mintTx.receipt.gasUsed < 230588, "First mint gas too high");

      const mintTx2 = await lazyClaim.mint(creator.address, 1, garbageMerkleProof, 0, {from:anyone1});
      console.log("Gas cost:\tsecond mint:\t"+ mintTx2.receipt.gasUsed);
      assert(mintTx2.receipt.gasUsed < 133993, "Second mint gas too high");

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone1, { from: owner });

      // Mint 1 token using the extension
      const mintTx3 = await lazyClaim.mint(creator.address, 1, garbageMerkleProof, 0, {from:anyone1});
      console.log("Gas cost:\tthird mint:\t"+ mintTx3.receipt.gasUsed);
      assert(mintTx3.receipt.gasUsed < 174070, "Third mint gas too high");
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
        {from:owner2}
      ));

      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "one.com",
          totalMax: 3,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true
        },
        {from:owner}
      );

      // Overwrite the claim with parameters changed
      await lazyClaim.overwriteClaim(
        creator.address,
        1, // the index of the claim we want to edit
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "one.com",
          totalMax: 3,
          walletMax: 1,
          startDate: now,
          endDate: later + 1,
          storageProtocol: 1,
          identical: false
        },
        {from:owner}
      );

      // Initialize a second claim - with optional parameters disabled
      await lazyClaim.initializeClaim(
        creator.address,
        {
          merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
          location: "two.com",
          totalMax: 0,
          walletMax: 0,
          startDate: 0,
          endDate: 0,
          storageProtocol: 1,
          identical: true
        },
        {from:owner}
      );
    
      // Claim should have expected info
      const count = await lazyClaim.getClaimCount(creator.address, {from:owner});
      assert.equal(count, 2);
      const claim = await lazyClaim.getClaim(creator.address, 1, {from:owner});
      assert.equal(claim.merkleRoot, merkleTree.getHexRoot());
      assert.equal(claim.location, 'one.com');
      assert.equal(claim.totalMax, 3);
      assert.equal(claim.walletMax, 1);
      assert.equal(claim.startDate, now);
      assert.equal(claim.endDate, later + 1);

      // Test minting

      // Mint a token to random wallet
      const merkleLeaf = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof = merkleTree.getHexProof(merkleLeaf);
      const mintTx = await lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone1});

      // Minting with an invalid proof should revert
      truffleAssert.reverts(lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone2}));

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      await lazyClaim.mint(creator.address, 1, merkleProof2, 0, {from:anyone2});

      // Now ensure that the creator contract state is what we expect after mints
      let balance = await creator.balanceOf(anyone1, {from:anyone3});
      assert.equal(1,balance);
      let balance2 = await creator.balanceOf(anyone2, {from:anyone3});
      assert.equal(1,balance2);
      let tokenURI = await creator.tokenURI(1);
      assert.equal('one.com/1', tokenURI);
      let tokenOwner = await creator.ownerOf(1);
      assert.equal(anyone1, tokenOwner);

      // Additionally test that tokenURIs are dynamic
      await lazyClaim.overwriteClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "three.com",
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
      assert.equal('three.com/1', newTokenURI);

      // Try to mint again with wallet limit of 1, should revert
      const w1 = await lazyClaim.getWalletMinted(creator.address, 1, anyone1, {from:anyone1});
      console.log('W1:', w1.toString());
      truffleAssert.reverts(lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone1}), undefined, 'FFFFF2');
      // Increase wallet max to 3

      const w2 = await lazyClaim.getWalletMinted(creator.address, 1, anyone1, {from:anyone1});
      console.log('W2:', w2.toString());
      await lazyClaim.overwriteClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "three.com",
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
      const claim2 = await lazyClaim.getClaim(creator.address, 1, {from:owner});
      console.log('Claim2 total:', claim2.total);
      console.log('BBB');
      try {
        await lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone1});
      } catch (e) {
        console.error(e);
        throw e;
      }
      console.log('AAA');
      // Try to mint again with total limit of 3, should revert due to totalMax = 3
      const claim3 = await lazyClaim.getClaim(creator.address, 1, {from:owner});
      console.log('Claim3 total:', claim3.total);
      // assert.equal(claim.merkleRoot, merkleTree.getHexRoot());
      truffleAssert.reverts(lazyClaim.mint(creator.address, 1, merkleProof, 0, {from:anyone1}), undefined, 'FFFFF');

      console.log('Mint 4 completed');

      // Optional parameters - using claim 2
      const garbageMerkleLeaf = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 0]));
      const garbageMerkleProof = merkleTree.getHexProof(garbageMerkleLeaf);
      await lazyClaim.mint(creator.address, 2, garbageMerkleProof, 0, {from:anyone1});
      await lazyClaim.mint(creator.address, 2, garbageMerkleProof, 0, {from:anyone1});
      await lazyClaim.mint(creator.address, 2, garbageMerkleProof, 0, {from:anyone2});
    });
  });
});