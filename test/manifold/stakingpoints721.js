const truffleAssert = require("truffle-assertions");
const ERC721Creator = artifacts.require("@manifoldxyz/creator-core-extensions-solidity/ERC721Creator");
const ERC721StakingPoints = artifacts.require("ERC721StakingPoints");
const ERC1155Creator = artifacts.require("@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator");
const keccak256 = require("keccak256");
const ethers = require("ethers");
const MockManifoldMembership = artifacts.require("MockManifoldMembership");
const ERC721 = artifacts.require("MockERC721");
const ERC1155 = artifacts.require("MockERC1155");

const STAKE_FEE = ethers.BigNumber.from("690000000000000");
const MULTI_STAKE_FEE = ethers.BigNumber.from("990000000000000");

contract("ERC721StakingPoints", function ([...accounts]) {
  const [owner, anotherOwner, anyone1, anyone2] = accounts;

  describe("StakingPoints", function () {
    let creator, fee;

    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", { from: owner });
      stakingPoints721 = await ERC721StakingPoints.new({ from: owner });
      manifoldMembership = await MockManifoldMembership.new({ from: owner });
      await stakingPoints721.setMembershipAddress(manifoldMembership.address);

      mock721 = await ERC721Creator.new("721", "721", { from: owner });
      mock721_2 = await ERC721Creator.new("721_2", "721_2", { from: owner });
      mock1155 = await ERC1155Creator.new("1155.com", { from: owner });

      await mock721.mintBase(anyone1, { from: owner });
      await mock721.mintBase(anyone2, { from: owner });
      await mock721.mintBase(anyone2, { from: owner });
      await mock721.mintBase(anyone1, { from: owner });
      await mock721_2.mintBase(anyone1, { from: owner });
      await mock721_2.mintBase(anyone2, { from: owner });
      await mock721_2.mintBase(anotherOwner, { from: owner });

      await creator.registerExtension(stakingPoints721.address, { from: owner });
    });
    // edge cases - can user withdraw points without unstaking?
    // non-creator or owner cannot change rules
    // can admin update the rules / rates while there is an affected token(?)

    it("Admin creates new stakingpoints with rate", async function () {
      // must be an admin
      await truffleAssert.reverts(
        stakingPoints721.initializeStakingPoints(
          creator.address,
          1,
          {
            paymentReceiver: owner,
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRate: 1234,
                timeUnit: 100000,
                startTime: 1674768875,
                endTime: 1682541275,
              },
            ],
          },
          { from: anyone1 }
        ),
        "Wallet is not an admin"
      );
      // has invalid staking rule (missing pointsRate value)
      await truffleAssert.reverts(
        stakingPoints721.initializeStakingPoints(
          creator.address,
          1,
          {
            paymentReceiver: owner,
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRate: 0,
                timeUnit: 100000,
                startTime: 1674768875,
                endTime: 1682541275,
              },
            ],
          },
          { from: owner }
        ),
        "Staking rule: Invalid points rate"
      );
      // has invalid staking rule (missing timeUnit value)
      await truffleAssert.reverts(
        stakingPoints721.initializeStakingPoints(
          creator.address,
          1,
          {
            paymentReceiver: owner,
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRate: 1234,
                timeUnit: 0,
                startTime: 1674768875,
                endTime: 1682541275,
              },
            ],
          },
          { from: owner }
        ),
        "Staking rule: Invalid timeUnit"
      );
      // has invalid staking rule (endTime is less than startTime)
      await truffleAssert.reverts(
        stakingPoints721.initializeStakingPoints(
          creator.address,
          1,
          {
            paymentReceiver: owner,
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRate: 1234,
                timeUnit: 100000,
                startTime: 1682541275,
                endTime: 1674768875,
              },
            ],
          },
          { from: owner }
        ),
        "Staking rule: Invalid time range"
      );
      // has valid staking rule (token spec is not erc721)

      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        {
          paymentReceiver: owner,
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRate: 1234,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
            },
          ],
        },
        { from: owner }
      );
      stakingPointsInstance = await stakingPoints721.getStakingPointsInstance(creator.address, 1);
      assert.equal(stakingPointsInstance.stakingRules.length, 1);
    });
    // TODO:
    // it("Admin creates new stakingpoints with intial rate, updates rate", function () {});
    // it("Can get stakers", function () {});

    it("Will not stake if not owned or approved", async function () {
      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        {
          paymentReceiver: owner,
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRate: 1234,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
            },
            {
              tokenAddress: mock721.address,
              pointsRate: 125,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
            },
          ],
        },
        { from: owner }
      );
      await truffleAssert.reverts(
        stakingPoints721.stakeTokens(
          1,
          [
            {
              tokenAddress: mock721.address,
              tokenId: 1,
            },
          ],
          { from: owner }
        ),
        "Token not owned or not approved"
      );
    });
    it("Stakes if owned and approved", async function () {
      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        {
          paymentReceiver: owner,
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRate: 1234,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
            },
            {
              tokenAddress: mock721.address,
              pointsRate: 125,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
            },
            {
              tokenAddress: mock721_2.address,
              pointsRate: 125,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
            },
          ],
        },
        { from: owner }
      );
      await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await stakingPoints721.stakeTokens(
        1,
        [
          {
            tokenAddress: mock721.address,
            tokenId: 2,
          },
          {
            tokenAddress: mock721.address,
            tokenId: 3,
          },
          {
            tokenAddress: mock721_2.address,
            tokenId: 2,
          },
        ],
        { from: anyone2 }
      );

      let stakerDetails1 = await stakingPoints721.getStakerDetails(1, anyone2);

      assert.equal(stakerDetails1.stakersTokens.length, 3);
      assert.equal(stakerDetails1.stakersTokens[0].tokenId, 2);
      assert.equal(stakerDetails1.stakersTokens[1].tokenId, 3);
      assert.equal(stakerDetails1.stakersTokens[1].contractAddress, mock721.address);
      assert.equal(stakerDetails1.stakersTokens[2].tokenId, 2);
      assert.equal(stakerDetails1.stakersTokens[2].contractAddress, mock721_2.address);
    });
    it("Stakes and unstakes", async function () {
      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        {
          paymentReceiver: owner,
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRate: 1234,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
            },
            {
              tokenAddress: mock721.address,
              pointsRate: 125,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
            },
            {
              tokenAddress: mock721_2.address,
              pointsRate: 125,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
            },
          ],
        },
        { from: owner }
      );
      await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await stakingPoints721.stakeTokens(
        1,
        [
          {
            tokenAddress: mock721.address,
            tokenId: 2,
          },
          {
            tokenAddress: mock721.address,
            tokenId: 3,
          },
          {
            tokenAddress: mock721_2.address,
            tokenId: 2,
          },
        ],
        { from: anyone2 }
      );

      let stakerDetails1 = await stakingPoints721.getStakerDetails(1, anyone2);

      assert.equal(stakerDetails1.stakersTokens.length, 3);
      assert.equal(stakerDetails1.stakersTokens[0].tokenId, 2);
      assert.equal(stakerDetails1.stakersTokens[1].tokenId, 3);
      assert.equal(stakerDetails1.stakersTokens[1].contractAddress, mock721.address);
      assert.equal(stakerDetails1.stakersTokens[2].tokenId, 2);
      assert.equal(stakerDetails1.stakersTokens[2].contractAddress, mock721_2.address);

      // unstake #1
      await truffleAssert.reverts(
        stakingPoints721.unstakeTokens(
          1,
          [
            {
              tokenAddress: mock721.address,
              tokenId: 2,
            },
            {
              tokenAddress: mock721.address,
              tokenId: 3,
            },
            {
              tokenAddress: mock721_2.address,
              tokenId: 2,
            },
          ],
          { from: anyone1 }
        ),
        "No sender address or not the original staker"
      );

      await stakingPoints721.unstakeTokens(
        1,
        [
          {
            tokenAddress: mock721.address,
            tokenId: 2,
          },
          {
            tokenAddress: mock721_2.address,
            tokenId: 2,
          },
        ],
        { from: anyone2 }
      );

      let stakerDetails = await stakingPoints721.getStakerDetails(1, anyone2);
      assert.equal(stakerDetails.stakersTokens.length, 3);
      let token = await stakingPoints721.getUserStakedToken(anyone2, mock721.address, 2);
      assert.equal(token.timeUnstaked !== 0, true);
      let token2 = await stakingPoints721.getUserStakedToken(anyone2, mock721.address, 3);
      assert.equal(token2.timeUnstaked, 0);
      let token3 = await stakingPoints721.getUserStakedToken(anyone2, mock721_2.address, 2);
      assert.equal(token3.timeUnstaked !== 0, true);
      assert.equal(stakerDetails.stakersTokens[0].timeUnstaked, token.timeUnstaked);
      assert.equal(stakerDetails.stakersTokens[1].timeUnstaked, token2.timeUnstaked);
      assert.equal(stakerDetails.stakersTokens[2].timeUnstaked, token3.timeUnstaked);
    });

    // it("Redeems points", async function () {
    //   await stakingPoints721.initializeStakingPoints(
    //     creator.address,
    //     1,
    //     {
    //       paymentReceiver: owner,
    //       stakingRules: [
    //         {
    //           tokenAddress: manifoldMembership.address,
    //           pointsRate: 1234,
    //           timeUnit: 100000,
    //           startTime: 1674768875,
    //           endTime: 1682541275,
    //         },
    //         {
    //           tokenAddress: mock721.address,
    //           pointsRate: 125,
    //           timeUnit: 100000,
    //           startTime: 1674768875,
    //           endTime: 1682541275,
    //         },
    //         {
    //           tokenAddress: mock721_2.address,
    //           pointsRate: 125,
    //           timeUnit: 100000,
    //           startTime: 1674768875,
    //           endTime: 1682541275,
    //         },
    //       ],
    //     },
    //     { from: owner }
    //   );
    //   await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
    //   await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
    //   await stakingPoints721.stakeTokens(
    //     1,
    //     [
    //       {
    //         tokenAddress: mock721.address,
    //         tokenId: 2,
    //       },
    //       {
    //         tokenAddress: mock721.address,
    //         tokenId: 3,
    //       },
    //       {
    //         tokenAddress: mock721_2.address,
    //         tokenId: 2,
    //       },
    //     ],
    //     { from: anyone2 }
    //   );
    // });
  });
});
