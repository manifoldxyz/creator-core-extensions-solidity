const truffleAssert = require('truffle-assertions');
const ERC721BurnRedeem = artifacts.require("ERC721BurnRedeem");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const ethers = require('ethers');
const MockManifoldMembership = artifacts.require('MockManifoldMembership');

const BURN_FEE = ethers.BigNumber.from('690000000000000');
const MULTI_BURN_FEE = ethers.BigNumber.from('990000000000000');

contract('ERC721BurnRedeem', function ([...accounts]) {
  const [owner, anyone1] = accounts;
  describe('BurnRedeem', function () {
    let creator, burnRedeem, burnable721, burnable721_2, burnable1155, burnable1155_2;
    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", {from:owner});
      burnRedeem = await ERC721BurnRedeem.new({from:owner});
      manifoldMembership = await MockManifoldMembership.new({from:owner});
      await burnRedeem.setMembershipAddress(manifoldMembership.address);
      burnable721 = await ERC721Creator.new("Test", "TEST", {from:owner});
      burnable721_2 = await ERC721Creator.new("Test", "TEST", {from:owner});
      burnable1155 = await ERC1155Creator.new("Test", "TEST", {from:owner});
      burnable1155_2 = await ERC1155Creator.new("Test", "TEST", {from:owner});
      
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
          startDate: now,
          endDate: later,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        {
          identical: true,
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
          paymentReceiver: owner,
          burnSet: [],
        },
        {
          identical: true,
        },
        {from:owner}
      ));
    });

    it('initializeBurnRedeem input sanitization test', async function () {
      let now = (await web3.eth.getBlock('latest')).timestamp; // seconds since unix epoch
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
          paymentReceiver: owner,
          burnSet: [],
        },
        {
          identical: true,
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
          paymentReceiver: owner,
          burnSet: [],
        },
        {
          identical: true,
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
          startDate: now,
          endDate: later,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        {
          identical: true,
        },
        {from:owner}
      );

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
          paymentReceiver: owner,
          burnSet: [],
        },
        {
          identical: true,
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
          paymentReceiver: anyone1,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 1,
                  contractAddress: burnable721.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          identical: true,
        },
        {from:owner}
      );

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      await burnRedeem.burnRedeem(
        creator.address,
        1,
        [
          {
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: burnable721.address,
            id: 1,
            merkleProof: [ethers.utils.formatBytes32String("")]
          },
        ],
        {from:anyone1, value: BURN_FEE}
      )

      assert.equal('XXX', await creator.tokenURI(1));

      await burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          totalSupply: 10,
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
                  contractAddress: burnable721.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );

      assert.equal('XXX/1', await creator.tokenURI(1));
    });

    it('burnRedeem test - burn 721', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      for (let i = 0; i < 3; i++) {
        await burnable721.mintBase(anyone1, { from: owner });
        await burnable721_2.mintBase(anyone1, { from: owner });
      }

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(3, balance);
      balance = await burnable721_2.balanceOf(anyone1);
      assert.equal(3, balance);

      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['uint256'], [3]));
      merkleElements.push(ethers.utils.solidityPack(['uint256'], [10]));
      merkleElements.push(ethers.utils.solidityPack(['uint256'], [15]));
      merkleElements.push(ethers.utils.solidityPack(['uint256'], [20]));
      merkleTreeWithValues = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
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
                  contractAddress: burnable721.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            },
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 2,
                  contractAddress: burnable721_2.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 1,
                  maxTokenId: 2,
                  merkleRoot: ethers.utils.formatBytes32String("")
                },
                {
                  validationType: 3,
                  contractAddress: burnable721_2.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: merkleTreeWithValues.getHexRoot()
                }
              ]
            }
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});
      await burnable721_2.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Reverts due to unmet requirements
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          {from:anyone1, value: BURN_FEE}
        ),
        "Invalid number of tokens"
      );

      // Reverts due to too many tokens
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable721_2.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable721_2.address,
              id: 2,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1, value: MULTI_BURN_FEE}
        ),
        "Invalid number of tokens"
      );

      // Reverts when token ID out of range
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable721_2.address,
              id: 3,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1, value: MULTI_BURN_FEE}
        ),
        "Invalid token ID"
      );

      // Reverts with invalid merkle proof
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 1,
              contractAddress: burnable721_2.address,
              id: 3,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1, value: MULTI_BURN_FEE}
        ),
        "Invalid merkle proof"
      );

      // Reverts due to no fee
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable721_2.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1}
        ),
        "Invalid value"
      );

      // Passes with met requirements - range
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable721_2.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1, value: MULTI_BURN_FEE}
        )
      );

      // Passes with met requirements - merkle proof
      const merkleLeaf = keccak256(ethers.utils.solidityPack(['uint256'], [3]));
      const merkleProof = merkleTreeWithValues.getHexProof(merkleLeaf);
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 2,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 1,
              contractAddress: burnable721_2.address,
              id: 3,
              merkleProof: merkleProof
            },
          ],
          {from:anyone1, value: MULTI_BURN_FEE}
        )
      );

      // Ensure tokens are burned/minted
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(1, balance);
      balance = await burnable721_2.balanceOf(anyone1);
      assert.equal(1, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(2, balance);
    });

    it('burnRedeem test - burnRedeem.cost', async function() {
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      const cost = ethers.BigNumber.from('1000000000000000000');

      // Mint burnable token
      await burnable721.mintBase(anyone1, { from: owner });
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: cost,
          paymentReceiver: owner,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 1,
                  contractAddress: burnable721.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Reverts due to invalid value
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          {from:anyone1, value: BURN_FEE}
        ),
        "Invalid value"
      );

      const creatorBalanceBefore = await web3.eth.getBalance(owner);

      // Passes with propper value
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          {from:anyone1, value: BURN_FEE.add(cost)}
        )
      );

      // Check that cost was sent to creator
      const creatorBalanceAfter = await web3.eth.getBalance(owner);
      assert.equal(ethers.BigNumber.from(creatorBalanceBefore).add(cost).toString(), creatorBalanceAfter);
    });

    it('burnRedeem test - with membership', async function() {
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable token
      await burnable721.mintBase(anyone1, { from: owner });
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
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
                  contractAddress: burnable721.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Passes with no fee
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          {from:anyone1}
        )
      );
    });

    it('burnRedeem test - multiple redemptions', async function() {
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });
      
      // Burn #1
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
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
                  contractAddress: burnable721.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );
      // Burn #2
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        2,
        {
          startDate: start,
          endDate: end,
          totalSupply: 1,
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
        {
          identical: false,
        },
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});
      await burnable1155.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      const userBalanceBefore = await web3.eth.getBalance(anyone1);

      // Passes with multiple redemptions
      const tx = await burnRedeem.methods['burnRedeem(address[],uint256[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        [creator.address, creator.address, creator.address],
        [1, 2, 2],
        [
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable1155.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable1155.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ]
        ],
        {from:anyone1, value: BURN_FEE.mul(3)}
      );

      const userBalanceAfter = await web3.eth.getBalance(anyone1);

      let balance = await burnable721.balanceOf(anyone1);
      assert.equal(0, balance);
      // 1 token burned for Burn #2 (sold out thereafter), the second should not be burned
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(1, balance);
      // Only 2 redemptions should have gone through
      balance = await creator.balanceOf(anyone1);
      assert.equal(2, balance);

      // User should only be charged for 2 burn redeems
      const cost = BURN_FEE.mul(2);
      const gasFee = tx.receipt.gasUsed * tx.receipt.effectiveGasPrice;
      assert.equal(ethers.BigNumber.from(userBalanceBefore).sub(cost).sub(gasFee).toString(), userBalanceAfter);
    });

    it('onERC721Received test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 1, 0, []]);

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });
      await burnable721_2.mintBase(anyone1, { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(1, balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
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
                  contractAddress: burnable721.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );

      // Reverts without membership
      await truffleAssert.reverts(burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}), "Not an active member");

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Reverts due to wrong contract
      await truffleAssert.reverts(burnable721_2.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}), "Invalid burn token");

      // Passes with right token id
      await truffleAssert.passes(burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/minted
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(1, balance);
    });

    it('onERC1155Received test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 1, 0, []]);

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });
      await burnable1155_2.mintBaseNew([anyone1], [2], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(2, balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
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
                  amount: 2,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );

      // Reverts without membership
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}), "Not an active member");

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Reverts due to wrong contract
      await truffleAssert.reverts(burnable1155_2.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}), "Invalid burn token");

      // Passes with right token id
      await truffleAssert.passes(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(0, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(1, balance);
    });

    it('onERC1155Received test - multiple redemptions', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 1, 0, []]);

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [10], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(10, balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 3,
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
                  amount: 2,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Passes with value == 2 * burnItem.amount (2 redemptions)
      await truffleAssert.passes(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 4, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(6, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(2, balance);

      // Passes with value == 2 * burnItem.amount (2 redemptions), but only 1 redemption left
      await truffleAssert.passes(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 4, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/returned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      // Only 1 redemption left, so 2 tokens are returned
      assert.equal(4, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(3, balance);

      // Reverts with no redemptions left
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}), "No tokens available");
    });

    it('onERC1155BatchReceived test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(
        ["address", "uint256", {
          "BurnToken[]": {
            "groupIndex": "uint48",
            "itemIndex": "uint48",
            "contractAddress": "address",
            "id": "uint256",
            "merkleProof": "bytes32[]"
          }
        }],
        [creator.address, 1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable1155.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 0,
              itemIndex: 1,
              contractAddress: burnable1155.address,
              id: 2,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ]
        ]
      );

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [2], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(2, balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(2, balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [
            {
              requiredCount: 2,
              items: [
                {
                  validationType: 2,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 2,
                  minTokenId: 1,
                  maxTokenId: 1,
                  merkleRoot: ethers.utils.formatBytes32String("")
                },
                {
                  validationType: 2,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 2,
                  minTokenId: 2,
                  maxTokenId: 2,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );

      // Reverts without membership
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [2, 2], burnRedeemData, {from:anyone1}), "Not an active member");

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Reverts without mismatching token ids
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 3], [2, 2], burnRedeemData, {from:anyone1}), "Invalid token");

      // Reverts without mismatching values
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [1, 1], burnRedeemData, {from:anyone1}), "Invalid amount");

      // Reverts with extra tokens
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2, 3], [2, 2, 2], burnRedeemData, {from:anyone1}), "Invalid number of burn tokens");

      // Passes with right token id
      await truffleAssert.passes(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [2, 2], burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(0, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(1, balance);
    });

    it('withdraw test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      for (let i = 0; i < 10; i++) {
        await burnable721.mintBase(anyone1, { from: owner });
      }
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          totalSupply: 10,
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
                  contractAddress: burnable721.address,
                  tokenSpec: 1,
                  burnSpec: 1,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            },
          ],
        },
        {
          identical: false,
        },
        {from:owner}
      );

      const addresses = [];
      const indexes = [];
      const burnTokens = [];

      for (let i = 0; i < 10; i++) {
        addresses.push(creator.address);
        indexes.push(1);
        burnTokens.push([
          {
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: burnable721.address,
            id: i + 1,
            merkleProof: [ethers.utils.formatBytes32String("")]
          }
        ]);
      }

      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      await burnRedeem.methods['burnRedeem(address[],uint256[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        addresses,
        indexes,
        burnTokens,
        {from:anyone1, value: BURN_FEE.mul(10)}
      );

      // Reverts when non admin tries to withdraw
      await truffleAssert.reverts(burnRedeem.withdraw(anyone1, BURN_FEE.mul(10), {from:anyone1}), "AdminControl: Must be owner or admin");

      // Reverts with too large of a withdrawal
      await truffleAssert.reverts(burnRedeem.withdraw(owner, BURN_FEE.mul(200), {from:owner}), "Failed to transfer to recipient");

      const ownerBalanceBefore = await web3.eth.getBalance(owner);

      // Passes with valid withdrawal amount from owner
      const tx = await burnRedeem.withdraw(owner, BURN_FEE.mul(10), {from:owner});

      const ownerBalanceAfter = await web3.eth.getBalance(owner);
      const gasFee = tx.receipt.gasUsed * tx.receipt.effectiveGasPrice;
      assert.equal(ethers.BigNumber.from(ownerBalanceBefore).add(BURN_FEE.mul(10)).sub(gasFee).toString(), ownerBalanceAfter);
    });
  });
});
