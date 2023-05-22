const truffleAssert = require('truffle-assertions');
const ERC721BurnRedeem = artifacts.require("ERC721BurnRedeem");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const ethers = require('ethers');
const MockManifoldMembership = artifacts.require('MockManifoldMembership');
const ERC721 = artifacts.require('MockERC721');
const ERC1155 = artifacts.require('MockERC1155');
const ERC721Burnable = artifacts.require('MockERC721Burnable');
const ERC1155Burnable = artifacts.require('MockERC1155Burnable');

const BURN_FEE = ethers.BigNumber.from('690000000000000');
const MULTI_BURN_FEE = ethers.BigNumber.from('990000000000000');

contract('ERC721BurnRedeem', function ([...accounts]) {
  const [owner, burnRedeemOwner, anyone1, anyone2] = accounts;
  describe('BurnRedeem', function () {
    let creator, burnRedeem, burnable721, burnable721_2, burnable1155, burnable1155_2;
    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", {from:owner});
      burnRedeem = await ERC721BurnRedeem.new(burnRedeemOwner, {from:owner});
      manifoldMembership = await MockManifoldMembership.new({from:owner});
      await burnRedeem.setMembershipAddress(manifoldMembership.address);
      burnable721 = await ERC721Creator.new("Test", "TEST", {from:owner});
      burnable721_2 = await ERC721Creator.new("Test", "TEST", {from:owner});
      burnable1155 = await ERC1155Creator.new("Test", "TEST", {from:owner});
      burnable1155_2 = await ERC1155Creator.new("Test", "TEST", {from:owner});
      oz721 = await ERC721.new("Test", "TEST", {from:owner});
      oz1155 = await ERC1155.new("test.com", {from:owner});
      oz721Burnable = await ERC721Burnable.new("Test", "TEST", {from:owner});
      oz1155Burnable = await ERC1155Burnable.new("test.com", {from:owner});
      
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
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        true,
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
          burnSet: [],
        },
        true,
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
          paymentReceiver: owner,
          burnSet: [],
        },
        true,
        {from:anyone1}
      ), "Wallet is not an admin");

      // Fails because not admin
      await truffleAssert.reverts(burnRedeem.updateTokenURI(
        creator.address,
        1,
        1,
        "",
        true,
        {from:anyone1}
      ), "Wallet is not an admin");
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
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        true,
        {from:owner}
      ), "startDate after endDate");

      // Fails due to non-mod-0 redeemAmount
      await truffleAssert.reverts(burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: 0,
          endDate: now,
          redeemAmount: 3,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        true,
        {from:owner}
      ), "Remainder left from totalSupply");

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
          burnSet: [],
        },
        true,
        {from:owner}
      ), "Burn redeem not initialized");

      // Cannot have amount == 0 on ERC1155 burn item
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
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ]
        },
        false,
        {from:owner}
      ), "Invalid input");

      // Cannot have ValidationType == INVALID on burn item
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
          paymentReceiver: owner,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 0,
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
          ]
        },
        false,
        {from:owner}
      ), "Invalid input");

      // Cannot have TokenSpec == INVALID on burn item
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
          paymentReceiver: owner,
          burnSet: [
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 1,
                  contractAddress: burnable1155.address,
                  tokenSpec: 0,
                  burnSpec: 1,
                  amount: 1,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ]
        },
        false,
        {from:owner}
      ), "Invalid input");

      // Cannot have requiredCount == 0 on burn group
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
          paymentReceiver: owner,
          burnSet: [
            {
              requiredCount: 0,
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
          ]
        },
        false,
        {from:owner}
      ), "Invalid input");

      // Cannot have requiredCount > items.length on burn group
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
          paymentReceiver: owner,
          burnSet: [
            {
              requiredCount: 2,
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
          ]
        },
        false,
        {from:owner}
      ), "Invalid input");
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
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        true,
        {from:owner}
      );

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
          burnSet: [],
        },
        true,
        {from:owner}
      ), "startDate after endDate");

      // Fails due to non-mod-0 redeemAmount
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: 0,
          endDate: now,
          redeemAmount: 3,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        true,
        {from:owner}
      ), "Remainder left from totalSupply");

      await burnRedeem.burnRedeem(creator.address, 1, 2, [], {from:owner, value: BURN_FEE.mul(2)});

      // Fails due to non-mod-0 redeemAmount after redemptions
      await truffleAssert.reverts(burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: 0,
          endDate: now,
          redeemAmount: 3,
          totalSupply: 9,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        true,
        {from:owner}
      ), "Invalid amount");

      // totalSupply = redeemedCount if updated below redeemedCount
      await burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: 0,
          endDate: now,
          redeemAmount: 1,
          totalSupply: 1,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        true,
        {from:owner}
      )
      let burnRedeemInstance = await burnRedeem.getBurnRedeem(creator.address, 1);
      assert.equal(burnRedeemInstance.totalSupply, 2);

      // totalSupply = 0 if updated to 0 and redeemedCount > 0
      await burnRedeem.updateBurnRedeem(
        creator.address,
        1,
        {
          startDate: 0,
          endDate: now,
          redeemAmount: 1,
          totalSupply: 0,
          storageProtocol: 1,
          location: "XXX",
          cost: 0,
          paymentReceiver: owner,
          burnSet: [],
        },
        true,
        {from:owner}
      )
      burnRedeemInstance = await burnRedeem.getBurnRedeem(creator.address, 1);
      assert.equal(burnRedeemInstance.totalSupply, 0);
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
          redeemAmount: 1,
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
        true,
        {from:owner}
      );

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      await burnRedeem.burnRedeem(
        creator.address,
        1,
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
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      assert.equal('XXX/1', await creator.tokenURI(1));
    });

    it('tokenURI test - mint between burns', async function () {
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
        false,
        {from:owner}
      );

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });
      await burnable721.mintBase(anyone1, { from: owner });
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Redeem first token
      await burnRedeem.burnRedeem(
        creator.address,
        1,
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

      assert.equal('XXX/1', await creator.tokenURI(1));

      // Mint another token on creator contract
      await creator.mintBase(anyone1, {from:owner});

      // Redeem another token
      await burnRedeem.burnRedeem(
        creator.address,
        1,
        1,
        [
          {
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: burnable721.address,
            id: 2,
            merkleProof: [ethers.utils.formatBytes32String("")]
          },
        ],
        {from:anyone1, value: BURN_FEE}
      )

      assert.equal('XXX/2', await creator.tokenURI(3));
    });

    it('burnRedeem test - burn 721', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      for (let i = 0; i < 4; i++) {
        await burnable721.mintBase(anyone1, { from: owner });
        await burnable721_2.mintBase(anyone1, { from: owner });
      }

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(4, balance);
      balance = await burnable721_2.balanceOf(anyone1);
      assert.equal(4, balance);

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
          redeemAmount: 1,
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
        false,
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
        "Invalid amount"
      );

      // Reverts when msg.sender is not token owner, but tokens are approved
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
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
          {from:anyone2, value: MULTI_BURN_FEE}
        ),
        "Sender is not owner"
      );

      // Reverts with burnCount > 1
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          2,
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
          {from:anyone1, value: MULTI_BURN_FEE.mul(2)}
        ),
        "Invalid burn count"
      );

      await truffleAssert.reverts(
        burnRedeem.getBurnRedeemForToken(
          creator.address,
          1
        ),
        "Token does not exist"
      )

      // Passes with met requirements - range
      await burnRedeem.burnRedeem(
        creator.address,
        1,
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
      );

      // Get burn redeem for token, should succeed
      const burnRedeemInfo = await burnRedeem.getBurnRedeemForToken(creator.address, 1)
      assert.equal(burnRedeemInfo[0], 1);
      const burnRedeemForToken = burnRedeemInfo[1];
      assert.equal(burnRedeemForToken.contractVersion, 3);

      // Grab gas cost
      let tx = await burnRedeem.burnRedeem(
        creator.address,
        1,
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
            itemIndex: 0,
            contractAddress: burnable721_2.address,
            id: 2,
            merkleProof: [ethers.utils.formatBytes32String("")]
          },
        ],
        {from:anyone1, value: MULTI_BURN_FEE}
      );

      console.log("Gas cost:\tBurn 2 721s (range validation) through burnRedeem:\t"+ tx.receipt.gasUsed);

      // Passes with met requirements - merkle proof
      const merkleLeaf = keccak256(ethers.utils.solidityPack(['uint256'], [3]));
      const merkleProof = merkleTreeWithValues.getHexProof(merkleLeaf);
      tx = await burnRedeem.burnRedeem(
        creator.address,
        1,
        1,
        [
          {
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: burnable721.address,
            id: 3,
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
      );

      console.log("Gas cost:\tBurn 2 721s (range and merkle validation) through burnRedeem:\t"+ tx.receipt.gasUsed);

      // Ensure tokens are burned/minted
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(1, balance);
      balance = await burnable721_2.balanceOf(anyone1);
      assert.equal(1, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(3, balance);
    });

    it('burnRedeem test - burn 721 - burnSpec = NONE', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      for (let i = 0; i < 3; i++) {
        await oz721.mint(anyone1, i + 1, { from: owner });
      }

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await oz721.balanceOf(anyone1);
      assert.equal(3, balance);
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
                  contractAddress: oz721.address,
                  tokenSpec: 1,
                  burnSpec: 0,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ]
        },
        false,
        {from:owner}
      );

      // Set approvals
      await oz721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Passes
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: oz721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1, value: BURN_FEE}
        )
      );

      // Ensure tokens are burned/minted
      balance = await oz721.balanceOf(anyone1);
      assert.equal(2, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(1, balance);
    });

    it('burnRedeem test - burn 721 - burnSpec = OPENZEPPELIN', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      for (let i = 0; i < 3; i++) {
        await oz721Burnable.mint(anyone1, i + 1, { from: owner });
      }

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await oz721Burnable.balanceOf(anyone1);
      assert.equal(3, balance);
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
                  contractAddress: oz721Burnable.address,
                  tokenSpec: 1,
                  burnSpec: 2,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ]
        },
        false,
        {from:owner}
      );

      // Set approvals
      await oz721Burnable.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Passes
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: oz721Burnable.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1, value: BURN_FEE}
        )
      );

      // Ensure tokens are burned/minted
      balance = await oz721Burnable.balanceOf(anyone1);
      assert.equal(2, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(1, balance);
    });

    it('burnRedeem test - burn 1155', async function() {
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [10], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [10], [""], { from: owner });
      await burnable1155_2.mintBaseNew([anyone1], [10], [""], { from: owner });
      await burnable721.mintBase(anyone1, { from: owner });

      const merkleElements = [];
      merkleElements.push(ethers.utils.solidityPack(['uint256'], [2]));
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
          redeemAmount: 1,
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
                  contractAddress: burnable1155_2.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 2,
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
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 1,
                  minTokenId: 1,
                  maxTokenId: 2,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            },
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 3,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 1,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: merkleTreeWithValues.getHexRoot()
                },
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
        false,
        {from:owner}
      );

      // Set approvals
      await burnable1155.setApprovalForAll(burnRedeem.address, true, {from:anyone1});
      await burnable1155_2.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      const merkleLeaf = keccak256(ethers.utils.solidityPack(['uint256'], [2]));
      const merkleProof = merkleTreeWithValues.getHexProof(merkleLeaf);

      // Reverts with burnCount > 1 if 721 is in burnTokens
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          3,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable1155_2.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 1,
              itemIndex: 0,
              contractAddress: burnable1155.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
            {
              groupIndex: 2,
              itemIndex: 1,
              contractAddress: burnable721.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1, value: MULTI_BURN_FEE.mul(3)}
        ),
        "Invalid burn count"
      );

      // Passes with burnCount > 1
      let tx = await burnRedeem.burnRedeem(
        creator.address,
        1,
        3,
        [
          {
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: burnable1155_2.address,
            id: 1,
            merkleProof: [ethers.utils.formatBytes32String("")]
          },
          {
            groupIndex: 1,
            itemIndex: 0,
            contractAddress: burnable1155.address,
            id: 1,
            merkleProof: [ethers.utils.formatBytes32String("")]
          },
          {
            groupIndex: 2,
            itemIndex: 0,
            contractAddress: burnable1155.address,
            id: 2,
            merkleProof: merkleProof
          },
        ],
        {from:anyone1, value: MULTI_BURN_FEE.mul(3)}
      );

      console.log("Gas cost:\tBurn 3 1155s x3 (contract, range and merkle validation) through burnRedeem:\t"+ tx.receipt.gasUsed);

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(7, balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(7, balance);
      balance = await burnable1155_2.balanceOf(anyone1, 1);
      assert.equal(4, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(3, balance);
    });

    it('burnRedeem test - burn 1155 - burnSpec = NONE', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      await oz1155.mint(anyone1, 1, 3, { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await oz1155.balanceOf(anyone1, 1);
      assert.equal(3, balance);
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
                  contractAddress: oz1155.address,
                  tokenSpec: 2,
                  burnSpec: 0,
                  amount: 1,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ]
        },
        false,
        {from:owner}
      );

      // Set approvals
      await oz1155.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Passes
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: oz1155.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1, value: BURN_FEE}
        )
      );

      // Ensure tokens are burned/minted
      balance = await oz1155.balanceOf(anyone1, 1);
      assert.equal(2, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(1, balance);
    });

    it('burnRedeem test - burn 1155 - burnSpec = OPENZEPPELIN', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      await oz1155Burnable.mint(anyone1, 1, 3, { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await oz1155Burnable.balanceOf(anyone1, 1);
      assert.equal(3, balance);
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
                  contractAddress: oz1155Burnable.address,
                  tokenSpec: 2,
                  burnSpec: 2,
                  amount: 1,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ]
        },
        false,
        {from:owner}
      );

      // Set approvals
      await oz1155Burnable.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Passes
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: oz1155Burnable.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            },
          ],
          {from:anyone1, value: BURN_FEE}
        )
      );

      // Ensure tokens are burned/minted
      balance = await oz1155Burnable.balanceOf(anyone1, 1);
      assert.equal(2, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(1, balance);
    });

    it('burnRedeem test - redeemAmount > 1', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });

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
          redeemAmount: 3,
          totalSupply: 9,
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
        false,
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Passes with met requirements - range
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
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
      );

      // Ensure tokens are burned/minted
      balance = await burnable721.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(3, balance);
    });

    it('burnRedeem test - malicious sender reverts', async function() {
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
          redeemAmount: 1,
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
                  burnSpec: 0,
                  amount: 0,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        false,
        {from:owner}
      );
      // Burn #2
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        2,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
                  burnSpec: 0,
                  amount: 1,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        false,
        {from:owner}
      );
      // Burn #3
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        3,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
                  amount: 1,
                  minTokenId: 0,
                  maxTokenId: 0,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        false,
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});
      await burnable1155.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Reverts when msg.sender is not token owner, but tokens are approved
      // 721 with no burn
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
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
          {from:anyone2, value: BURN_FEE}
        ),
        "ERC721: transfer from incorrect owner"
      );
      // 1155 with no burn
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          2,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable1155.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          {from:anyone2, value: BURN_FEE}
        ),
        "ERC1155: caller is not token owner or approved."
      );
      // 1155 with burn
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          3,
          1,
          [
            {
              groupIndex: 0,
              itemIndex: 0,
              contractAddress: burnable1155.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          {from:anyone2, value: BURN_FEE}
        ),
        "Caller is not owner or approved."
      );
    });

    it('burnRedeem test - burnRedeem.cost', async function() {
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      const cost = ethers.BigNumber.from('1000000000000000000');

      // Mint burnable token
      await burnable721.mintBase(anyone1, { from: owner });
      await burnable1155.mintBaseNew([anyone1], [10], [""], { from: owner });
      
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
                },
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
        false,
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});
      await burnable1155.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      // Reverts due to invalid value
      await truffleAssert.reverts(
        burnRedeem.burnRedeem(
          creator.address,
          1,
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
        "Invalid amount"
      );

      let creatorBalanceBefore = await web3.eth.getBalance(owner);

      // Passes with propper value
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
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
      let creatorBalanceAfter = await web3.eth.getBalance(owner);
      assert.equal(ethers.BigNumber.from(creatorBalanceBefore).add(cost).toString(), creatorBalanceAfter);

      creatorBalanceBefore = await web3.eth.getBalance(owner);

      // Passes with burnCount > 1
      await truffleAssert.passes(
        burnRedeem.burnRedeem(
          creator.address,
          1,
          5,
          [
            {
              groupIndex: 0,
              itemIndex: 1,
              contractAddress: burnable1155.address,
              id: 1,
              merkleProof: [ethers.utils.formatBytes32String("")]
            }
          ],
          {from:anyone1, value: BURN_FEE.mul(5).add(cost.mul(5))}
        )
      );

      // Check that cost was sent to creator
      creatorBalanceAfter = await web3.eth.getBalance(owner);
      assert.equal(ethers.BigNumber.from(creatorBalanceBefore).add(cost.mul(5)).toString(), creatorBalanceAfter);
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
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Passes with no fee
      let tx = await burnRedeem.burnRedeem(
        creator.address,
        1,
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
      );

      console.log("Gas cost:\tBurn 1 721 (contract validation) through burnRedeem:\t"+ tx.receipt.gasUsed);
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
          redeemAmount: 1,
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
        false,
        {from:owner}
      );
      // Burn #2
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        2,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      // Set approvals
      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});
      await burnable1155.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      const addresses = [creator.address, creator.address];
      const indexes = [1, 2];
      const burnCounts = [1, 2];
      const burnTokens = [
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
      ];

      // Reverts with insufficient fee
      await truffleAssert.reverts(burnRedeem.methods['burnRedeem(address[],uint256[],uint32[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        addresses,
        indexes,
        burnCounts,
        burnTokens,
        {from:anyone1, value: BURN_FEE}
      ), "Invalid amount");

      // Reverts with mismatching lengths
      await truffleAssert.reverts(burnRedeem.methods['burnRedeem(address[],uint256[],uint32[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        [creator.address],
        indexes,
        burnCounts,
        burnTokens,
        {from:anyone1, value: BURN_FEE}
      ), "Invalid calldata");
      await truffleAssert.reverts(burnRedeem.methods['burnRedeem(address[],uint256[],uint32[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        addresses,
        [1],
        burnCounts,
        burnTokens,
        {from:anyone1, value: BURN_FEE}
      ), "Invalid calldata");
      await truffleAssert.reverts(burnRedeem.methods['burnRedeem(address[],uint256[],uint32[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        addresses,
        indexes,
        [1],
        burnTokens,
        {from:anyone1, value: BURN_FEE}
      ), "Invalid calldata");
      await truffleAssert.reverts(burnRedeem.methods['burnRedeem(address[],uint256[],uint32[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        addresses,
        indexes,
        burnCounts,
        [burnTokens[0]],
        {from:anyone1, value: BURN_FEE}
      ), "Invalid calldata");

      // Reverts with burnCount > 1 for 721
      await truffleAssert.reverts(burnRedeem.methods['burnRedeem(address[],uint256[],uint32[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        addresses,
        indexes,
        [2, 2],
        burnTokens,
        {from:anyone1, value: BURN_FEE.mul(4)}
      ), "Invalid burn count");

      const userBalanceBefore = await web3.eth.getBalance(anyone1);

      // Passes with multiple redemptions, burnCount > 1 for 1155
      const tx = await burnRedeem.methods['burnRedeem(address[],uint256[],uint32[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        addresses,
        indexes,
        burnCounts,
        burnTokens,
        {from:anyone1, value: BURN_FEE.mul(3)}
      );

      console.log("Gas cost:\tBatch (burn 1 721), (burn 1 1155 x2) (contract validation) through burnRedeem:\t"+ tx.receipt.gasUsed);

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
      const gasFee = tx.receipt.gasUsed * (await web3.eth.getTransaction(tx.tx)).gasPrice
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
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      // Reverts without membership
      await truffleAssert.reverts(burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}), "Invalid input");

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Reverts due to wrong contract
      await truffleAssert.reverts(burnable721_2.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}), "Invalid burn token");

      // Passes with right token id
      let tx = await burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1});

      console.log("Gas cost:\tBurn 1 721 (contract validation) through 721 receiver:\t"+ tx.receipt.gasUsed);

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
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint32", "uint256", "bytes32[]"], [creator.address, 1, 1, 0, []]);

      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [3], [""], { from: owner });
      await burnable1155_2.mintBaseNew([anyone1], [3], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(3, balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      // Reverts without membership
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}), "Invalid input");

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Reverts due to wrong contract
      await truffleAssert.reverts(burnable1155_2.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1}), "Invalid burn token");

      // Reverts with invalid amount
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 3, burnRedeemData, {from:anyone1}), "Invalid input");

      // Passes with right token id
      let tx = await burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 2, burnRedeemData, {from:anyone1});

      console.log("Gas cost:\tBurn 2 1155s (contract validation) through 1155 receiver:\t"+ tx.receipt.gasUsed);

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(1, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(1, balance);
    });

    it('onERC1155Received test - multiple redemptions', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint32", "uint256", "bytes32[]"], [creator.address, 1, 2, 0, []]);

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
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Passes with value == 2 * burnItem.amount (2 redemptions)
      let tx = await burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 4, burnRedeemData, {from:anyone1});

      console.log("Gas cost:\tBurn 2 1155s x2 (contract validation) through 1155 receiver:\t"+ tx.receipt.gasUsed);

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(6, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(2, balance);

      // Passes with value == 2 * burnItem.amount (2 redemptions), but only 1 redemption left
      await truffleAssert.passes(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 4, burnRedeemData, {from:anyone1}));

      // Ensure tokens are burned/returned/minted
      balance = await creator.balanceOf(anyone1);
      assert.equal(3, balance);
      // Only 1 redemption left, so 2 tokens are returned
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(4, balance);

      // Reverts with no redemptions left
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 4, burnRedeemData, {from:anyone1}), "No tokens available");
    });

    it('onERC1155BatchReceived test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(
        ["address", "uint256", "uint32", {
          "BurnToken[]": {
            "groupIndex": "uint48",
            "itemIndex": "uint48",
            "contractAddress": "address",
            "id": "uint256",
            "merkleProof": "bytes32[]"
          }
        }],
        [creator.address, 1, 1,
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
      await burnable1155.mintBaseNew([anyone1], [10], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [10], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [10], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(10, balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(10, balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      // Reverts without membership
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [2, 2], burnRedeemData, {from:anyone1}), "Invalid input");

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Reverts without mismatching token ids
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 3], [2, 2], burnRedeemData, {from:anyone1}), "Invalid token");

      // Reverts without mismatching values
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [1, 1], burnRedeemData, {from:anyone1}), "Invalid amount");

      // Reverts with extra tokens
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2, 3], [2, 2, 2], burnRedeemData, {from:anyone1}), "Invalid input");

      // Passes with right token id
      let tx = await burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [2, 2], burnRedeemData, {from:anyone1});

      console.log("Gas cost:\tBurn 4 1155s (contract validation) through 1155 batch receiver:\t"+ tx.receipt.gasUsed);

      // burnCount > 1
      burnRedeemData = web3.eth.abi.encodeParameters(
        ["address", "uint256", "uint32", {
          "BurnToken[]": {
            "groupIndex": "uint48",
            "itemIndex": "uint48",
            "contractAddress": "address",
            "id": "uint256",
            "merkleProof": "bytes32[]"
          }
        }],
        [creator.address, 1, 4,
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
      // Reverts with insufficient values
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [2, 2], burnRedeemData, {from:anyone1}), "Invalid amount");

      // Passes with right values
      tx = await burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [8, 8], burnRedeemData, {from:anyone1});

      console.log("Gas cost:\tBurn 4 1155s x4 (contract validation) through 1155 batch receiver:\t"+ tx.receipt.gasUsed);

      // Ensure tokens are burned/minted
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 2);
      assert.equal(0, balance);
      balance = await creator.balanceOf(anyone1);
      assert.equal(5, balance);
    });

    it('receiver invalid input test', async function() {
      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let cost = ethers.BigNumber.from('1000000000000000000');

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });
      await burnable1155.mintBaseNew([anyone1], [1], [""], { from: owner });
      await burnable1155.mintBaseNew([anyone1], [1], [""], { from: owner });

      // Burn #1
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
        false,
        {from:owner}
      );
      // Burn #2
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        2,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
        false,
        {from:owner}
      );
      // Burn #3
      await burnRedeem.initializeBurnRedeem(
        creator.address,
        3,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
          totalSupply: 10,
          storageProtocol: 1,
          location: "XXX",
          cost: cost,
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
                  amount: 1,
                  minTokenId: 1,
                  maxTokenId: 1,
                  merkleRoot: ethers.utils.formatBytes32String("")
                },
                {
                  validationType: 2,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 1,
                  minTokenId: 2,
                  maxTokenId: 2,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        false,
        {from:owner}
      );

      // Receivers revert on burns with cost
      // onERC721Received
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 1, 0, []]);
      await truffleAssert.reverts(burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}), "Invalid input");
      // onERC1155Received
      burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint32", "uint256", "bytes32[]"], [creator.address, 2, 1, 0, []]);
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "Invalid input");
      // onERC1155BatchReceived
      burnRedeemData = web3.eth.abi.encodeParameters(
        ["address", "uint256", "uint32", {
          "BurnToken[]": {
            "groupIndex": "uint48",
            "itemIndex": "uint48",
            "contractAddress": "address",
            "id": "uint256",
            "merkleProof": "bytes32[]"
          }
        }],
        [creator.address, 1, 1,
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
      await truffleAssert.reverts(burnable1155.methods['safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)'](anyone1, burnRedeem.address, [1, 2], [1, 1], burnRedeemData, {from:anyone1}), "Invalid input");

      // Single receivers revert on single set burns with requiredCount > 1
      // Burn #3
      await burnRedeem.updateBurnRedeem(
        creator.address,
        3,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
                  amount: 1,
                  minTokenId: 1,
                  maxTokenId: 1,
                  merkleRoot: ethers.utils.formatBytes32String("")
                },
                {
                  validationType: 2,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 1,
                  minTokenId: 2,
                  maxTokenId: 2,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        false,
        {from:owner}
      );
      // onERC721Received
      burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 3, 0, []]);
      await truffleAssert.reverts(burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}), "Invalid input");
      // onERC1155Received
      burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint32", "uint256", "bytes32[]"], [creator.address, 3, 1, 0, []]);
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "Invalid input");

      // Single receivers revert when burnSets.length > 1
      await burnRedeem.updateBurnRedeem(
        creator.address,
        3,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
                  validationType: 2,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 1,
                  minTokenId: 1,
                  maxTokenId: 1,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            },
            {
              requiredCount: 1,
              items: [
                {
                  validationType: 2,
                  contractAddress: burnable1155.address,
                  tokenSpec: 2,
                  burnSpec: 1,
                  amount: 1,
                  minTokenId: 2,
                  maxTokenId: 2,
                  merkleRoot: ethers.utils.formatBytes32String("")
                }
              ]
            }
          ],
        },
        false,
        {from:owner}
      );
      // onERC721Received
      burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 3, 0, []]);
      await truffleAssert.reverts(burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}), "Invalid input");
      // onERC1155Received
      burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint32", "uint256", "bytes32[]"], [creator.address, 3, 1, 0, []]);
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "Invalid input");
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
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      const addresses = [];
      const indexes = [];
      const burnTokens = [];
      const burnCounts = [];

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
        burnCounts.push(1);
      }

      await burnable721.setApprovalForAll(burnRedeem.address, true, {from:anyone1});

      await burnRedeem.methods['burnRedeem(address[],uint256[],uint32[],(uint48,uint48,address,uint256,bytes32[])[][])'](
        addresses,
        indexes,
        burnCounts,
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
      const gasFee = tx.receipt.gasUsed * (await web3.eth.getTransaction(tx.tx)).gasPrice
      assert.equal(ethers.BigNumber.from(ownerBalanceBefore).add(BURN_FEE.mul(10)).sub(gasFee).toString(), ownerBalanceAfter);
    });

    it('misconfiguration - onERC721Received test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint256", "bytes32[]"], [creator.address, 1, 0, []]);

      // Mint burnable tokens
      await burnable721.mintBase(anyone1, { from: owner });

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
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Reverts due to misconfiguration
      await truffleAssert.reverts(burnable721.methods['safeTransferFrom(address,address,uint256,bytes)'](anyone1, burnRedeem.address, 1, burnRedeemData, {from:anyone1}), "Invalid input");
    });

    it('misconfiguration - onERC1155Received test', async function() {

      // Test initializing a new burn redeem
      let start = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let end = start + 300;
      let burnRedeemData = web3.eth.abi.encodeParameters(["address", "uint256", "uint32", "uint256", "bytes32[]"], [creator.address, 1, 1, 0, []]);
      
      // Mint burnable tokens
      await burnable1155.mintBaseNew([anyone1], [1], [""], { from: owner });

      // Ensure that the creator contract state is what we expect before mints
      let balance = await creator.balanceOf(anyone1);
      assert.equal(0, balance);
      balance = await burnable1155.balanceOf(anyone1, 1);
      assert.equal(1, balance);

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: start,
          endDate: end,
          redeemAmount: 1,
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
        false,
        {from:owner}
      );

      // Receiver functions require membership
      await manifoldMembership.setMember(anyone1, true, {from:owner});

      // Reverts due to misconfiguration
      await truffleAssert.reverts(burnable1155.methods['safeTransferFrom(address,address,uint256,uint256,bytes)'](anyone1, burnRedeem.address, 1, 1, burnRedeemData, {from:anyone1}), "Invalid input");
    });

    it('airdrop test', async function() {
      let now = (await web3.eth.getBlock('latest')).timestamp-30; // seconds since unix epoch
      let later = now + 1000;

      await burnRedeem.initializeBurnRedeem(
        creator.address,
        1,
        {
          startDate: now,
          endDate: later,
          redeemAmount: 2,
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
        false,
        {from:owner}
      );

      // First airdrop
      await burnRedeem.airdrop(creator.address, 1, [anyone1, anyone2], [1, 1], {from:owner});

      // redeemedCount updated
      let burnRedeemInstance = await burnRedeem.getBurnRedeem(creator.address, 1);
      assert.equal(burnRedeemInstance.redeemedCount, 4);
      assert.equal(burnRedeemInstance.totalSupply, 10);

      // Check tokenURI
      assert.equal(await creator.tokenURI(1), "XXX/1");
      assert.equal(await creator.tokenURI(2), "XXX/2");

      // Tokens minted
      let balance = await creator.balanceOf(anyone1);
      assert.equal(balance, 2);
      balance = await creator.balanceOf(anyone2);
      assert.equal(balance, 2);

      // Second airdrop
      await burnRedeem.airdrop(creator.address, 1, [anyone1, anyone2], [9, 9], {from:owner});

      // Check tokenURI
      assert.equal(await creator.tokenURI(3), "XXX/3");
      assert.equal(await creator.tokenURI(4), "XXX/4");

      // Total supply updated to redeemedCount
      burnRedeemInstance = await burnRedeem.getBurnRedeem(creator.address, 1);
      assert.equal(burnRedeemInstance.redeemedCount, 40);
      assert.equal(burnRedeemInstance.totalSupply, 40);

      // Tokens minted
      balance = await creator.balanceOf(anyone1);
      assert.equal(balance, 20);
      balance = await creator.balanceOf(anyone2);
      assert.equal(balance, 20);

      // Reverts when redeemedCount would exceed max uint32
      await truffleAssert.reverts(
        burnRedeem.airdrop(creator.address, 1, [anyone1], [2147483647]),
        "Invalid amount"
      )
    });
  });
});
