const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721LazyPayableClaim = artifacts.require("ERC721LazyPayableClaim");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const DelegationRegistry = artifacts.require('DelegationRegistry');
const MockETHReceiver = artifacts.require('MockETHReceiver');
const MockManifoldMembership = artifacts.require('MockManifoldMembership');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const ethers = require('ethers');

contract('LazyPayableClaim721', function ([...accounts]) {
  const [owner, lazyClaimOwner, anotherOwner, anyone1, anyone2, anyone3, anyone4, anyone5, anyone6, anyone7] = accounts;
  describe('LazyPayableClaim721', function () {
    let creator, lazyClaim;
    let fee, merkleFee;
    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", {from:owner});
      delegationRegistry = await DelegationRegistry.new();
      lazyClaim = await ERC721LazyPayableClaim.new(lazyClaimOwner, delegationRegistry.address, {from:owner});
      manifoldMembership = await MockManifoldMembership.new({from:owner});
      lazyClaim.setMembershipAddress(manifoldMembership.address, {from:lazyClaimOwner});
      fee = ethers.BigNumber.from((await lazyClaim.MINT_FEE()).toString());
      merkleFee = ethers.BigNumber.from((await lazyClaim.MINT_FEE_MERKLE()).toString());

      // Must register with empty prefix in order to set per-token uri's
      await creator.registerExtension(lazyClaim.address, {from:owner});
    });

    it('access test', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      // Must be admin
      await truffleAssert.reverts(lazyClaim.withdraw(anyone1, 20, {from: anyone1}), "AdminControl: Must be owner or admin")
      await truffleAssert.reverts(lazyClaim.setMembershipAddress(anyone1, {from: anyone1}), "AdminControl: Must be owner or admin")

      // Must be admin
      await truffleAssert.reverts(lazyClaim.initializeClaim(
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
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:anyone1}
      ), "Wallet is not an administrator for contract");

      // Succeeds because admin
      await lazyClaim.initializeClaim(
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
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
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
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 1,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 0,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      ), "Cannot initialize with invalid storage protocol");

      // Fails due to endDate <= startDate
      await truffleAssert.reverts(lazyClaim.initializeClaim(
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
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      ), "Cannot have startDate greater than or equal to endDate");

      // Fails due to merkle root being set with walletMax
      await truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String("0x0"),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      ), "Cannot provide both walletMax and merkleRoot");

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
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      ), "Claim not initialized");
    });

    it('updateClaim input sanitization test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
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
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
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
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      ), "Cannot set invalid storage protocol");

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
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      ), "Cannot have startDate greater than or equal to endDate");

      // Fails due to change in erc20
      await truffleAssert.reverts(lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: now,
          endDate: now+1,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000001',
        },
        {from:owner}
      ), "Cannot change payment token");
    });

    it('merkle mint test - with cost', async function () {
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
        1,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 3,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof1 = merkleTreeWithValues.getHexProof(merkleLeaf1);

      // Merkle validation failure
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 1, merkleProof1, anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)}), "Could not verify merkle proof");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(merkleFee)}), "Could not verify merkle proof");

      await lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)});
      // Cannot mint with same mintIndex again
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)}), "Already minted");

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      const merkleProof2 = merkleTreeWithValues.getHexProof(merkleLeaf2);
      await lazyClaim.mint(creator.address, 1, 1, merkleProof2, anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(merkleFee)});
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 2]));
      const merkleProof3 = merkleTreeWithValues.getHexProof(merkleLeaf3);
      await lazyClaim.mint(creator.address, 1, 2, merkleProof3, anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(merkleFee)});

      const merkleLeaf4 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 3]));
      const merkleProof4 = merkleTreeWithValues.getHexProof(merkleLeaf4);
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 3, merkleProof4, anyone3, {from:anyone3, value: ethers.BigNumber.from('1').add(merkleFee)}), "Maximum tokens already minted for this claim");

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
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      )
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 3, merkleProof4, anyone3, {from:anyone3, value: ethers.BigNumber.from('1')}), "Invalid amount");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 3, merkleProof4, anyone3, {from:anyone3, value: ethers.BigNumber.from('1').add(fee)}), "Invalid amount");
      await lazyClaim.mint(creator.address, 1, 3, merkleProof4, anyone3, {from:anyone3, value: ethers.BigNumber.from('1').add(merkleFee)});
    });

    it('merkle mint test - free mint', async function () {
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
        1,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 3,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: false,
          cost: ethers.BigNumber.from('0'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof1 = merkleTreeWithValues.getHexProof(merkleLeaf1);

      // Merkle validation failure
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 1, merkleProof1, anyone1, {from:anyone1, value: merkleFee}), "Could not verify merkle proof");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone2, {from:anyone2, value: merkleFee}), "Could not verify merkle proof");

      await lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone1, {from:anyone1, value: merkleFee});
      // Cannot mint with same mintIndex again
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone1, {from:anyone1, value: merkleFee}), "Already minted");

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      const merkleProof2 = merkleTreeWithValues.getHexProof(merkleLeaf2);
      await lazyClaim.mint(creator.address, 1, 1, merkleProof2, anyone2, {from:anyone2, value: merkleFee});
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 2]));
      const merkleProof3 = merkleTreeWithValues.getHexProof(merkleLeaf3);
      await lazyClaim.mint(creator.address, 1, 2, merkleProof3, anyone2, {from:anyone2, value: merkleFee});

      const merkleLeaf4 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 3]));
      const merkleProof4 = merkleTreeWithValues.getHexProof(merkleLeaf4);
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 3, merkleProof4, anyone3, {from:anyone3, value: merkleFee}), "Maximum tokens already minted for this claim");

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
          identical: false,
          cost: ethers.BigNumber.from('0'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      )
      await lazyClaim.mint(creator.address, 1, 3, merkleProof4, anyone3, {from:anyone3, value: merkleFee});
    });

    it('merkle mint test - batch with cost', async function () {
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
        1,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 3,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof1 = merkleTreeWithValues.getHexProof(merkleLeaf1);

      // Merkle validation failure
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [0], [merkleProof1], anyone1, {from:anyone1, value: ethers.BigNumber.from('2').add(merkleFee.mul(2))}), "Invalid input");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [0, 0], [merkleProof1], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)}), "Invalid input");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [0], [merkleProof1, merkleProof1], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)}), "Invalid input");

      await lazyClaim.mintBatch(creator.address, 1, 1, [0], [merkleProof1], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)});
      // Cannot mint with same mintIndex again
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [0], [merkleProof1], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)}), "Already minted");

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      const merkleProof2 = merkleTreeWithValues.getHexProof(merkleLeaf2);
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 2]));
      const merkleProof3 = merkleTreeWithValues.getHexProof(merkleLeaf3);
      const merkleLeaf4 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 3]));
      const merkleProof4 = merkleTreeWithValues.getHexProof(merkleLeaf4);
      const merkleLeaf5 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 4]));
      const merkleProof5 = merkleTreeWithValues.getHexProof(merkleLeaf5);

      // Cannot steal someone else's merkleproof
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [1,3], [merkleProof2,merkleProof4], anyone2, {from:anyone2, value: ethers.BigNumber.from('2').add(merkleFee.mul(2))}), "Could not verify merkle proof");

      const mintTx = await lazyClaim.mintBatch(creator.address, 1, 2, [1,2], [merkleProof2,merkleProof3], anyone2, {from:anyone2, value: ethers.BigNumber.from('2').add(merkleFee.mul(2))});
      console.log("Gas cost:\tBatch mint 2:\t"+ mintTx.receipt.gasUsed);

      // base mint something in between
      await creator.mintBase(anyone5, {from: owner});

      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [3], [merkleProof4], anyone3, {from:anyone3, value: ethers.BigNumber.from('1').add(merkleFee)}), "Too many requested for this claim");

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
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      )
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [3,4], [merkleProof4,merkleProof5], anyone3, {from:anyone3, value: ethers.BigNumber.from('2').add(merkleFee.mul(2))}), "Too many requested for this claim");

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
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      )
      // Cannot mint with same mintIndex again
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 1, merkleProof2, anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(merkleFee)}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 2, merkleProof3, anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(merkleFee)}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [1,2], [merkleProof2,merkleProof3], anyone2, {from:anyone2, value: ethers.BigNumber.from('2').add(merkleFee.mul(2))}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [3,4], [merkleProof4,merkleProof5], anyone3, {from:anyone3, value: ethers.BigNumber.from('2').add(merkleFee)}), "Invalid amount");
      await lazyClaim.mintBatch(creator.address, 1, 2, [3,4], [merkleProof4,merkleProof5], anyone3, {from:anyone3, value: ethers.BigNumber.from('2').add(merkleFee.mul(2))});

      let balance1 = await creator.balanceOf(anyone1);
      assert.equal(1,balance1);
      let balance2 = await creator.balanceOf(anyone2);
      assert.equal(2,balance2);
      let balance3 = await creator.balanceOf(anyone3);
      assert.equal(2,balance3);

      // Check URI's
      assert.equal(await creator.tokenURI(1), 'XXX/1');
      assert.equal(await creator.tokenURI(2), 'XXX/2');
      assert.equal(await creator.tokenURI(3), 'XXX/3');
      assert.equal(await creator.tokenURI(5), 'XXX/4');
      assert.equal(await creator.tokenURI(6), 'XXX/5');
    });

    it('merkle mint test - batch free mint', async function () {
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
        1,
        {
          merkleRoot: merkleTreeWithValues.getHexRoot(),
          location: "XXX",
          totalMax: 3,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: false,
          cost: ethers.BigNumber.from('0'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof1 = merkleTreeWithValues.getHexProof(merkleLeaf1);

      // Merkle validation failure
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [0], [merkleProof1], anyone1, {from:anyone1, value: merkleFee.mul(2)}), "Invalid input");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [0, 0], [merkleProof1], anyone1, {from:anyone1, value: merkleFee}), "Invalid input");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [0], [merkleProof1, merkleProof1], anyone1, {from:anyone1, value: merkleFee}), "Invalid input");

      await lazyClaim.mintBatch(creator.address, 1, 1, [0], [merkleProof1], anyone1, {from:anyone1, value: merkleFee});
      // Cannot mint with same mintIndex again
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone1, {from:anyone1}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [0], [merkleProof1], anyone1, {from:anyone1, value: merkleFee}), "Already minted");

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      const merkleProof2 = merkleTreeWithValues.getHexProof(merkleLeaf2);
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 2]));
      const merkleProof3 = merkleTreeWithValues.getHexProof(merkleLeaf3);
      const merkleLeaf4 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 3]));
      const merkleProof4 = merkleTreeWithValues.getHexProof(merkleLeaf4);
      const merkleLeaf5 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 4]));
      const merkleProof5 = merkleTreeWithValues.getHexProof(merkleLeaf5);

      // Cannot steal someone else's merkleproof
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [1,3], [merkleProof2,merkleProof4], owner, {value: merkleFee.mul(2)}), "Could not verify merkle proof");

      const mintTx = await lazyClaim.mintBatch(creator.address, 1, 2, [1,2], [merkleProof2,merkleProof3], anyone2, {from:anyone2, value: merkleFee.mul(2)});
      console.log("Gas cost:\tBatch mint 2:\t"+ mintTx.receipt.gasUsed);

      // base mint something in between
      await creator.mintBase(anyone5, {from: owner});

      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [3], [merkleProof4], anyone3, {from:anyone3, value: merkleFee}), "Too many requested for this claim");

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
          identical: true,
          cost: ethers.BigNumber.from('0'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      )
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [3,4], [merkleProof4,merkleProof5], anyone3, {from:anyone3, value: merkleFee.mul(2)}), "Too many requested for this claim");

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
          identical: false,
          cost: ethers.BigNumber.from('0'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      )
      // Cannot mint with same mintIndex again
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 1, merkleProof2, anyone2, {from:anyone2, value: merkleFee}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 2, merkleProof3, anyone2, {from:anyone2, value: merkleFee.mul(2)}), "Already minted");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [1,2], [merkleProof2,merkleProof3], anyone2, {from:anyone2, value: merkleFee.mul(2)}), "Already minted");
      
      await lazyClaim.mintBatch(creator.address, 1, 2, [3,4], [merkleProof4,merkleProof5], anyone3, {from:anyone3, value: merkleFee.mul(2)});

      let balance1 = await creator.balanceOf(anyone1);
      assert.equal(1,balance1);
      let balance2 = await creator.balanceOf(anyone2);
      assert.equal(2,balance2);
      let balance3 = await creator.balanceOf(anyone3);
      assert.equal(2,balance3);

      // Check URI's
      assert.equal(await creator.tokenURI(1), 'XXX/1');
      assert.equal(await creator.tokenURI(2), 'XXX/2');
      assert.equal(await creator.tokenURI(3), 'XXX/3');
      assert.equal(await creator.tokenURI(5), 'XXX/4');
      assert.equal(await creator.tokenURI(6), 'XXX/5');
    });

    it('non-merkle mint test - batch', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 5,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 4, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('4').add(fee.mul(4))}), "Too many requested for this wallet");
      await lazyClaim.mintBatch(creator.address, 1, 3, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('3').add(fee.mul(3))});
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 1, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)}), "Too many requested for this wallet");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 3, [], [], anyone2, {from:anyone2, value: ethers.BigNumber.from('3').add(fee.mul(3))}), "Too many requested for this claim");
      await lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone2, {from:anyone2, value: ethers.BigNumber.from('2').add(fee.mul(2))});

    });

    it('non-merkle mint test - not pay enough', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 5,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('2')}), "Invalid amount");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 3, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('2').add(fee.mul(2))}), "Invalid amount");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 4, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('4').add(fee.mul(4))}), "Too many requested for this wallet");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: fee}), "Invalid amount");
      
      // update mint price
      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 5,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('2'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('2').add(fee)}), "Invalid amount");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('4')}), "Invalid amount");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)}), "Invalid amount");
    });


    it('non-merkle mint test - check balance', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 5,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      let beforeBalance =  await web3.eth.getBalance(owner)

      await lazyClaim.mintBatch(creator.address, 1, 1, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)});
      await lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone2, {from:anyone2, value: ethers.BigNumber.from('2').add(fee.mul(2))});
      await lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)});

      let afterBalance = await web3.eth.getBalance(owner)
      assert.equal(ethers.BigNumber.from(4).toNumber(), (ethers.BigNumber.from(afterBalance).sub(ethers.BigNumber.from(beforeBalance)).toNumber()));

      // update mint price
      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 8,
          walletMax: 4,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('2'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );
      
      beforeBalance =  await web3.eth.getBalance(owner)

      await lazyClaim.mintBatch(creator.address, 1, 1, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('2').add(fee)});
      await lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone2, {from:anyone2, value: ethers.BigNumber.from('4').add(fee.mul(2))});
      await lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: ethers.BigNumber.from('2').add(fee)});

      afterBalance = await web3.eth.getBalance(owner)
      assert.equal(ethers.BigNumber.from(8).toNumber(), (ethers.BigNumber.from(afterBalance).sub(ethers.BigNumber.from(beforeBalance)).toNumber()));
    });

    it('non-merkle mint test - check balance of different payment receiver address', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 5,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: anyone4,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      let beforeBalance =  await web3.eth.getBalance(anyone4)

      await lazyClaim.mintBatch(creator.address, 1, 1, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)});
      await lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone2, {from:anyone2, value: ethers.BigNumber.from('2').add(fee.mul(2))});
      await lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)});

      let afterBalance = await web3.eth.getBalance(anyone4)
      assert.equal(ethers.BigNumber.from(4).toNumber(), (ethers.BigNumber.from(afterBalance).sub(ethers.BigNumber.from(beforeBalance)).toNumber()));

      // update mint price
      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 8,
          walletMax: 4,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('2'),
          paymentReceiver: anyone4,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );
      
      beforeBalance =  await web3.eth.getBalance(anyone4)

      await lazyClaim.mintBatch(creator.address, 1, 1, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('2').add(fee)});
      await lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone2, {from:anyone2, value: ethers.BigNumber.from('4').add(fee.mul(2))});
      await lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: ethers.BigNumber.from('2').add(fee)});

      afterBalance = await web3.eth.getBalance(anyone4)
      assert.equal(ethers.BigNumber.from(8).toNumber(), (ethers.BigNumber.from(afterBalance).sub(ethers.BigNumber.from(beforeBalance)).toNumber()));
    });

    it('non-merkle mint test - free mint', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 5,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('0'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 3, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('2')}), "Invalid amount");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 4, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('4')}), "Too many requested for this wallet");
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1')}), "Invalid amount");

      let beforeBalance =  await web3.eth.getBalance(owner)

      await lazyClaim.mintBatch(creator.address, 1, 1, [], [], anyone1, {from:anyone1, value: fee});
      await lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone2, {from:anyone2, value: fee.mul(2)});
      await lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: fee});

      let afterBalance = await web3.eth.getBalance(owner)
      assert.equal(ethers.BigNumber.from(0).toNumber(), (ethers.BigNumber.from(afterBalance).sub(ethers.BigNumber.from(beforeBalance)).toNumber()));

      // update mint price
      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 8,
          walletMax: 4,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );
      
      beforeBalance =  await web3.eth.getBalance(owner)

      await lazyClaim.mintBatch(creator.address, 1, 1, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)});
      await lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone2, {from:anyone2, value: ethers.BigNumber.from('2').add(fee.mul(2))});
      await lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)});

      afterBalance = await web3.eth.getBalance(owner)
      assert.equal(ethers.BigNumber.from(4).toNumber(), (ethers.BigNumber.from(afterBalance).sub(ethers.BigNumber.from(beforeBalance)).toNumber()));
    });

    it('gas test - no merkle tree', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      const initializeTx = await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 11,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );
      console.log("Gas cost:\tinitialize:\t"+ initializeTx.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone1, { from: owner });

      // Mint 2 tokens using the extension
      const mintTx = await lazyClaim.mint(creator.address, 1, 0, [], anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(fee)});
      console.log("Gas cost:\tfirst mint:\t"+ mintTx.receipt.gasUsed);

      const mintTx2 = await lazyClaim.mint(creator.address, 1, 0, [], anyone3, {from:anyone3, value: ethers.BigNumber.from('1').add(fee)});
      console.log("Gas cost:\tsecond mint:\t"+ mintTx2.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone4, { from: owner });

      // Mint 1 token using the extension
      const mintTx3 = await lazyClaim.mint(creator.address, 1, 0, [], anyone5, {from:anyone5, value: ethers.BigNumber.from('1').add(fee)});
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
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 0,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );
      console.log("Gas cost:\tinitialize:\t"+ initializeTx.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone1, { from: owner });

      // Mint 2 tokens using the extension
      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      const merkleProof1 = merkleTree.getHexProof(merkleLeaf1);
      const mintTx = await lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(merkleFee)});
      console.log("Gas cost:\tfirst mint:\t"+ mintTx.receipt.gasUsed);

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 1]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      const mintTx2 = await lazyClaim.mint(creator.address, 1, 1, merkleProof2, anyone3, {from:anyone3, value: ethers.BigNumber.from('1').add(merkleFee)});
      console.log("Gas cost:\tsecond mint:\t"+ mintTx2.receipt.gasUsed);

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone4, { from: owner });

      // Mint 1 token using the extension
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone5, 2]));
      const merkleProof3 = merkleTree.getHexProof(merkleLeaf3);
      const mintTx3 = await lazyClaim.mint(creator.address, 1, 2, merkleProof3, anyone5, {from:anyone5, value: ethers.BigNumber.from('1').add(merkleFee)});
      console.log("Gas cost:\tthird mint:\t"+ mintTx3.receipt.gasUsed);

      // Mint 1 token using the extension
      const merkleLeaf4 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone6, 256]));
      const merkleProof4 = merkleTree.getHexProof(merkleLeaf4);
      const mintTx4 = await lazyClaim.mint(creator.address, 1, 256, merkleProof4, anyone6, {from:anyone6, value: ethers.BigNumber.from('1').add(merkleFee)});
      console.log("Gas cost:\tfourth mint:\t"+ mintTx4.receipt.gasUsed);
    });

    it('tokenURI test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 11,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      await lazyClaim.initializeClaim(
        creator.address,
        2,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "YYY",
          totalMax: 11,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );
      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone1, { from: owner });

      // Mint 2 tokens using extension 1
      await lazyClaim.mint(creator.address, 1, 0, [], anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(fee)});
      await lazyClaim.mint(creator.address, 1, 0, [], anyone3, {from:anyone3, value: ethers.BigNumber.from('1').add(fee)});
      
      // Mint 1 tokens using extension 2
      await lazyClaim.mint(creator.address, 2, 0, [], anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(fee)});

      // Mint a token using creator contract, to test breaking up extension's indexRange
      await creator.mintBase(anyone4, { from: owner });

      // Mint 1 token using extension 1
      await lazyClaim.mint(creator.address, 1, 0, [], anyone5, {from:anyone5, value: ethers.BigNumber.from('1').add(fee)});

      // Mint 2 tokens using extension 2
      await lazyClaim.mintBatch(creator.address, 2, 2, [], [], anyone5, {from:anyone5, value: ethers.BigNumber.from('2').add(fee.mul(2))});

      assert.equal('XXX/1', await creator.tokenURI(2));
      assert.equal('XXX/2', await creator.tokenURI(3));
      assert.equal('YYY/1', await creator.tokenURI(4));
      assert.equal('XXX/3', await creator.tokenURI(6));
      assert.equal('YYY/2', await creator.tokenURI(7));
      assert.equal('YYY/3', await creator.tokenURI(8));
    });

    it('walletMax test', async function() {

      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 2]));
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });

      // Test initializing a new claim
      let start = (await web3.eth.getBlock('latest')).timestamp-100; // seconds since unix epoch
      let end = start + 300;

      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 3,
          walletMax: 1,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      // Test minting
      await lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)});
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, [], anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(fee)}), "Maximum tokens already minted for this wallet");
      await truffleAssert.reverts(lazyClaim.mintBatch(creator.address, 1, 2, [], [], anyone2, {from:anyone2, value: ethers.BigNumber.from('3').add(fee.mul(2))}), "Too many requested for this wallet");
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
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "zero.com",
          totalMax: 3,
          walletMax: 1,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:anotherOwner}
      ), "Wallet is not an administrator for contract");

      // Cannot claim before initialization
      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof1 = merkleTree.getHexProof(merkleLeaf1);
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)}), "Claim not initialized");

      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "arweaveHash1",
          totalMax: 3,
          walletMax: 0,
          startDate: start,
          endDate: end,
          storageProtocol: 2,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      truffleAssert.reverts(lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "arweaveHash1",
          totalMax: 3,
          walletMax: 1,
          startDate: start,
          endDate: end,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:anotherOwner}
      ), "Wallet is not an administrator for contract");

      truffleAssert.reverts(lazyClaim.updateTokenURIParams(
        creator.address,
        1,
        2,
        true,
        "",
        {from:anotherOwner}
      ), "Wallet is not an administrator for contract");

      truffleAssert.reverts(lazyClaim.extendTokenURI(
        creator.address,
        1,
        "",
        {from:anotherOwner}
      ), "Wallet is not an administrator for contract");

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
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      // Initialize a second claim - with optional parameters disabled
      await lazyClaim.initializeClaim(
        creator.address,
        2,
        {
          merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
          location: "arweaveHash2",
          totalMax: 0,
          walletMax: 0,
          startDate: 0,
          endDate: 0,
          storageProtocol: 2,
          identical: true,
          cost: ethers.BigNumber.from('0'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );
    
      // Claim should have expected info
      let claim = await lazyClaim.getClaim(creator.address, 1);
      assert.equal(claim.merkleRoot, merkleTree.getHexRoot());
      assert.equal(claim.location, 'arweaveHash1');
      assert.equal(claim.totalMax, 3);
      assert.equal(claim.walletMax, 0);
      assert.equal(claim.startDate, start);
      assert.equal(claim.endDate, end + 1);
      assert.equal(claim.cost, 1);
      assert.equal(claim.paymentReceiver, owner);

      // Test minting
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)}), "Claim inactive");
      await helper.advanceTimeAndBlock(start+1-(await web3.eth.getBlock('latest')).timestamp+1);
      // Mint a token to random wallet
      await lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone1, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)});
      claim = await lazyClaim.getClaim(creator.address, 1);
      assert.equal(claim.total, 1);

      // claim by tokenId should have expected info
      let claimInfo = await lazyClaim.getClaimForToken(creator.address, 1);
      assert.equal(claimInfo[0], 1);
      let claimByToken = claimInfo[1];
      assert.equal(claimByToken.merkleRoot, merkleTree.getHexRoot());
      assert.equal(claimByToken.location, 'arweaveHash1');
      assert.equal(claimByToken.totalMax, 3);
      assert.equal(claimByToken.walletMax, 0);
      assert.equal(claimByToken.startDate, start);
      assert.equal(claimByToken.endDate, end + 1);
      assert.equal(claimByToken.cost, 1);
      assert.equal(claimByToken.paymentReceiver, owner);

      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      await lazyClaim.mint(creator.address, 1, 1, merkleProof2, anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(merkleFee)});

      // Now ensure that the creator contract state is what we expect after mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(1,balance);
      let balance2 = await creator.balanceOf(anyone2);
      assert.equal(1,balance2);
      let tokenURI = await creator.tokenURI(1);
      assert.equal('https://arweave.net/arweaveHash1', tokenURI);
      let tokenOwner = await creator.ownerOf(1);
      assert.equal(anyone1, tokenOwner);

      // Update just the uri params
      await lazyClaim.updateTokenURIParams(creator.address, 1, 2, false, 'arweaveHash3', {from:owner});
      assert.equal('https://arweave.net/arweaveHash3/1', await creator.tokenURI(1));
      // Extend uri
      await truffleAssert.reverts(lazyClaim.extendTokenURI(creator.address, 1, '', {from:owner}), "Invalid storage protocol");
      await lazyClaim.updateTokenURIParams(creator.address, 1, 1, true, 'part1', {from:owner});
      await lazyClaim.extendTokenURI(creator.address, 1, 'part2', {from:owner});
      assert.equal('part1part2', await creator.tokenURI(1));

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
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      let newTokenURI = await creator.tokenURI(1);
      assert.equal('test.com/1', newTokenURI);

      // Optional parameters - using claim 2
      // Cannot mint for someone else
      await truffleAssert.reverts(lazyClaim.mint(creator.address, 2, 0, [], anyone2, {from:anyone1, value:fee}), "Invalid input");
      await lazyClaim.mint(creator.address, 2, 0, [], anyone1, {from:anyone1, value: fee});
      await lazyClaim.mint(creator.address, 2, 0, [], anyone1, {from:anyone1, value: fee});
      await lazyClaim.mint(creator.address, 2, 0, [], anyone2, {from:anyone2, value: fee});

      // end claim period
      await helper.advanceTimeAndBlock(end+2-(await web3.eth.getBlock('latest')).timestamp+1);
      // Reverts due to end of mint period
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 2]));
      const merkleProof3 = merkleTree.getHexProof(merkleLeaf3);
      truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 2, merkleProof3, anyone3, {from:anyone3, value: ethers.BigNumber.from('1').add(merkleFee)}), "Claim inactive");

      const ownerBalanceBefore = await web3.eth.getBalance(lazyClaimOwner);

      // Passes with valid withdrawal amount from owner
      const tx = await lazyClaim.withdraw(lazyClaimOwner, fee, {from:lazyClaimOwner});
      const ownerBalanceAfter = await web3.eth.getBalance(lazyClaimOwner);
      const gasFee = tx.receipt.gasUsed * (await web3.eth.getTransaction(tx.tx)).gasPrice
      assert.equal(ethers.BigNumber.from(ownerBalanceBefore).add(fee).sub(gasFee).toString(), ownerBalanceAfter);
    });

    it('airdrop test', async function () {
      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 1]));
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });

      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      const initializeTx = await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 0,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      // Perform an airdrop
      await lazyClaim.airdrop(creator.address, 1, [anyone1], [1], { from: owner });

      // Make sure totalMax has not changed
      let claim = await lazyClaim.getClaim(creator.address, 1);
      assert.equal(claim.totalMax, 0);

      // Check tokenURI
      assert.equal(await creator.tokenURI(1), "XXX/1");

      // Mint
      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      const merkleProof1 = merkleTree.getHexProof(merkleLeaf1);
      await lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone2, {from:anyone2, value: ethers.BigNumber.from('1').add(merkleFee)});
      claim = await lazyClaim.getClaim(creator.address, 1);
      assert.equal(claim.total, 2);

      // Update totalMax to 1, will actually set to 2 because there are two
      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 1,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      )
      claim = await lazyClaim.getClaim(creator.address, 1);
      assert.equal(claim.totalMax, 2);

      // Perform another airdrop after minting
      await lazyClaim.airdrop(creator.address, 1, [anyone1, anyone2], [1, 5], { from: owner });
      claim = await lazyClaim.getClaim(creator.address, 1);
      assert.equal(claim.total, 8);
      assert.equal(claim.totalMax, 8);

      // Update totalMax back to 0
      await lazyClaim.updateClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 0,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      )
      claim = await lazyClaim.getClaim(creator.address, 1);
      assert.equal(claim.totalMax, 0);

      // Mint again after second airdrop
      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 1]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      await lazyClaim.mint(creator.address, 1, 1, merkleProof2, anyone3, {from:anyone3, value: ethers.BigNumber.from('1').add(merkleFee)});

      // Check balances
      let balance1 = await creator.balanceOf(anyone1);
      assert.equal(2,balance1);
      let balance2 = await creator.balanceOf(anyone2);
      assert.equal(6,balance2);
      let balance3 = await creator.balanceOf(anyone3);
      assert.equal(1,balance3);

      // Check tokenIds
      assert.equal(await creator.tokenURI(1), 'XXX');
      assert.equal(await creator.tokenURI(2), 'XXX');
      assert.equal(await creator.tokenURI(3), 'XXX');

      assert.equal(await creator.tokenURI(7), 'XXX');
      assert.equal(await creator.tokenURI(8), 'XXX');
      assert.equal(await creator.tokenURI(9), 'XXX');

      truffleAssert.reverts(creator.tokenURI(10));
    });

    it('airdrop uri test', async function () {
      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone3, 1]));
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });

      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      const initializeTx = await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 0,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: false,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      // Perform an airdrop
      await lazyClaim.airdrop(creator.address, 1, [anyone1], [1], { from: owner });

      // Make sure totalMax has not changed
      let claim = await lazyClaim.getClaim(creator.address, 1);
      assert.equal(claim.totalMax, 0);

      // Check tokenURI
      assert.equal(await creator.tokenURI(1), "XXX/1");

      // Perform another airdrop
      await lazyClaim.airdrop(creator.address, 1, [anyone1], [1], { from: owner });
      assert.equal(await creator.tokenURI(2), "XXX/2");

      // Perform another airdrop
      await lazyClaim.airdrop(creator.address, 1, [anyone1, anyone1], [1, 1], { from: owner });
      assert.equal(await creator.tokenURI(3), "XXX/3");
      assert.equal(await creator.tokenURI(4), "XXX/4");

      // Perform another airdrop
      await lazyClaim.airdrop(creator.address, 1, [anyone1, anyone1], [1, 1], { from: owner });
      assert.equal(await creator.tokenURI(5), "XXX/5");
      assert.equal(await creator.tokenURI(6), "XXX/6");

      // Perform another aidrop
      await lazyClaim.airdrop(creator.address, 1, [anyone2], [2], { from: owner });
      assert.equal(await creator.tokenURI(7), "XXX/7");
      assert.equal(await creator.tokenURI(8), "XXX/8");
    });

    it('delegate minting test', async function () {
      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone4, 1]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone6, 2]));
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });

      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      const initializeTx = await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 0,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      // Set delegations
      await delegationRegistry.delegateForAll(anyone1, true, { from: anyone2 });
      await delegationRegistry.delegateForContract(anyone3, lazyClaim.address, true, { from: anyone4 });

      // Mint with wallet-level delegate
      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      const merkleProof1 = merkleTree.getHexProof(merkleLeaf1);
      const mintTx = await lazyClaim.mint(creator.address, 1, 0, merkleProof1, anyone2, {from:anyone1, value: ethers.BigNumber.from('1').add(merkleFee)});
      assert.equal(await creator.balanceOf(anyone1), 1);
      assert.equal(await creator.balanceOf(anyone2), 0);

      // Mint with contract-level delegate
      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone4, 1]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      const mintTx2 = await lazyClaim.mint(creator.address, 1, 1, merkleProof2, anyone4, {from:anyone3, value: ethers.BigNumber.from('1').add(merkleFee)});

      // Fail to mint when no delegate is set
      const merkleLeaf3 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone6, 2]));
      const merkleProof3 = merkleTree.getHexProof(merkleLeaf2);
      truffleAssert.reverts(lazyClaim.mint(creator.address, 1, 1, merkleProof2, anyone6, {from:anyone5, value: ethers.BigNumber.from('1').add(merkleFee)}), 'Invalid delegate');
    });

    it('delegate registry address test', async function () {
      lazyClaim = await ERC721LazyPayableClaim.new(lazyClaimOwner, '0x00000000b1BBFe1BF5C5934c4bb9c30FEF15E57A', {from:owner});
      
      const onChainRegistryAddress = await lazyClaim.DELEGATION_REGISTRY();
      assert.equal('0x00000000b1BBFe1BF5C5934c4bb9c30FEF15E57A', onChainRegistryAddress);
    });

    it('allow recipient to be a contract', async function () {
      // Construct a contract receiver
      const mockETHReceiver = await MockETHReceiver.new({ from: owner });

      let now = (await web3.eth.getBlock('latest')).timestamp-30;
      let later = now + 1000;

      // Initialize the claim with the contract as its receiver
      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 5,
          walletMax: 3,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: mockETHReceiver.address,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      // Perform a mint on the claim
      const mintTx = await lazyClaim.mintBatch(creator.address, 1, 3, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('3').add(fee.mul(3))});
      console.log("Gas cost:\tmint w/ contract receiver:\t"+ mintTx.receipt.gasUsed);
      let claim = await lazyClaim.getClaim(creator.address, 1);
      assert.equal(claim.total, 3);
    });

    it('membership mint', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp-30;
      let later = now + 1000;
  
      // Initialize the claim
      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 1]));
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });

      // Initialize the claim (merkle)
      await lazyClaim.initializeClaim(
        creator.address,
        2,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 5,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      await manifoldMembership.setMember(anyone1, true, {from:owner});
      // Perform a mint on the claim
      await lazyClaim.mintBatch(creator.address, 1, 3, [], [], anyone1, {from:anyone1, value: ethers.BigNumber.from('3')});
      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 0]));
      const merkleProof1 = merkleTree.getHexProof(merkleLeaf1);
      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone1, 1]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      await lazyClaim.mintBatch(creator.address, 2, 2, [0, 1], [merkleProof1, merkleProof2], anyone1, {from:anyone1, value: ethers.BigNumber.from('2')});
    
    });

    it('proxy mint', async function () {  
      let now = (await web3.eth.getBlock('latest')).timestamp-30;
      let later = now + 1000;
  
      // Initialize the claim
      await lazyClaim.initializeClaim(
        creator.address,
        1,
        {
          merkleRoot: ethers.utils.formatBytes32String(""),
          location: "XXX",
          totalMax: 10,
          walletMax: 10,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      merkleElements.push(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });
      // Initialize the claim (merkle)
      await lazyClaim.initializeClaim(
        creator.address,
        3,
        {
          merkleRoot: merkleTree.getHexRoot(),
          location: "XXX",
          totalMax: 5,
          walletMax: 0,
          startDate: now,
          endDate: later,
          storageProtocol: 1,
          identical: true,
          cost: ethers.BigNumber.from('1'),
          paymentReceiver: owner,
          erc20: '0x0000000000000000000000000000000000000000',
        },
        {from:owner}
      );

      // The sender is a member, but proxy minting will ignore the fact they are a member
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Perform a mint on the claim
      const startingBalance = await web3.eth.getBalance(anyone1);
      const ownerStartingBalance = await web3.eth.getBalance(owner);
      const tx = await lazyClaim.mintProxy(creator.address, 1, 3, [], [], anyone2, {from:anyone1, value: ethers.BigNumber.from('3').add(fee.mul(3))})
      const gasPrice = (await web3.eth.getTransaction(tx.tx)).gasPrice;
      assert.equal(3, await creator.balanceOf(anyone2));
      // Ensure funds taken from message sender
      assert.deepEqual(ethers.BigNumber.from(startingBalance).sub(ethers.BigNumber.from(gasPrice).mul(tx.receipt.gasUsed)).sub(ethers.BigNumber.from('3').add(fee.mul(3))), ethers.BigNumber.from(await web3.eth.getBalance(anyone1)));
      // Ensure seller got funds
      assert.deepEqual(ethers.BigNumber.from('3').add(ownerStartingBalance), ethers.BigNumber.from(await web3.eth.getBalance(owner)));

      // Mint merkle claims
      const merkleLeaf1 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 0]));
      const merkleProof1 = merkleTree.getHexProof(merkleLeaf1);
      const merkleLeaf2 = keccak256(ethers.utils.solidityPack(['address', 'uint32'], [anyone2, 1]));
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      // Should fail if standard fee is provided
      await truffleAssert.reverts(lazyClaim.mintProxy(creator.address, 3, 2, [0, 1], [merkleProof1, merkleProof2], anyone2, {from:anyone1, value: ethers.BigNumber.from('2').add(fee.mul(2))}), "Invalid amount");
      await lazyClaim.mintProxy(creator.address, 3, 2, [0, 1], [merkleProof1, merkleProof2], anyone2, {from:anyone1, value: ethers.BigNumber.from('2').add(merkleFee.mul(2))});
      assert.equal(5, await creator.balanceOf(anyone2));
    });
  });
});
