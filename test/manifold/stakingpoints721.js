const truffleAssert = require("truffle-assertions");
const ERC721Creator = artifacts.require("@manifoldxyz/creator-core-extensions-solidity/ERC721Creator");
const ERC721StakingPoints = artifacts.require("ERC721StakingPoints");
const ERC1155Creator = artifacts.require("@manifoldxyz/creator-core-extensions-solidity/ERC1155Creator");
const MockManifoldMembership = artifacts.require("MockManifoldMembership");

contract("ERC721StakingPoints", function ([...accounts]) {
  const [owner, anotherOwner, anyone1, anyone2] = accounts;

  describe("StakingPoints", function () {
    let creator;

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
                pointsRatePerDay: 1234,
                startTime: 1680680461,
                endTime: 95625733261,
              },
            ],
          },
          { from: anyone1 }
        ),
        "Wallet is not an admin"
      );
      // has invalid staking rule (missing pointsRatePerDay value)
      await truffleAssert.reverts(
        stakingPoints721.initializeStakingPoints(
          creator.address,
          1,
          {
            paymentReceiver: owner,
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRatePerDay: 0,
                startTime: 1680680461,
                endTime: 95625733261,
              },
            ],
          },
          { from: owner }
        ),
        "Staking rule: Invalid points rate"
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
                pointsRatePerDay: 1234,
                startTime: 1680680461,
                endTime: 1582541275,
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
              pointsRatePerDay: 1234,
              startTime: 1680680461,
              endTime: 95625733261,
            },
          ],
        },
        { from: owner }
      );
      stakingPointsInstance = await stakingPoints721.getStakingPointsInstance(creator.address, 1);
      assert.equal(stakingPointsInstance.stakingRules.length, 1);
    });

    it("Will update a staking points instance if there are not any stakers", async function () {
      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        {
          paymentReceiver: owner,
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRatePerDay: 2222,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721.address,
              pointsRatePerDay: 1111,
              startTime: 1680680461,
              endTime: 95625733261,
            },
          ],
        },
        { from: owner }
      );

      await truffleAssert.reverts(
        stakingPoints721.updateStakingPoints(
          creator.address,
          1,
          {
            paymentReceiver: owner,
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRatePerDay: 3333,
                startTime: 1680680461,
                endTime: 95625733261,
              },
              {
                tokenAddress: mock721.address,
                pointsRatePerDay: 4444,
                startTime: 1680680461,
                endTime: 95625733261,
              },
            ],
          },
          { from: anyone2 }
        ),
        "Wallet is not an admin"
      );

      //update
      await stakingPoints721.updateStakingPoints(
        creator.address,
        1,
        {
          paymentReceiver: owner,
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRatePerDay: 1234,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721.address,
              pointsRatePerDay: 125,
              startTime: 1680680461,
              endTime: 95625733261,
            },
          ],
        },
        { from: owner }
      );

      // someone stakes
      await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await stakingPoints721.stakeTokens(
        creator.address,
        1,
        [
          {
            tokenAddress: mock721.address,
            tokenId: 2,
          },
        ],
        { from: anyone2 }
      );

      // unable to update
      await truffleAssert.reverts(
        stakingPoints721.updateStakingPoints(
          creator.address,
          1,
          {
            paymentReceiver: owner,
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRatePerDay: 3333,
                startTime: 1680680461,
                endTime: 95625733261,
              },
              {
                tokenAddress: mock721.address,
                pointsRatePerDay: 4444,
                startTime: 1680680461,
                endTime: 95625733261,
              },
            ],
          },
          { from: owner }
        ),
        "StakingPoints cannot be updated when 1 or more wallets have staked"
      );
    });
    it("Will not stake if not owned or approved", async function () {
      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        {
          paymentReceiver: owner,
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRatePerDay: 1234,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721.address,
              pointsRatePerDay: 125,
              startTime: 1680680461,
              endTime: 95625733261,
            },
          ],
        },
        { from: owner }
      );
      await truffleAssert.reverts(
        stakingPoints721.stakeTokens(
          creator.address,
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
              pointsRatePerDay: 1234,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721.address,
              pointsRatePerDay: 125,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721_2.address,
              pointsRatePerDay: 125,
              startTime: 1680680461,
              endTime: 95625733261,
            },
          ],
        },
        { from: owner }
      );
      await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await stakingPoints721.stakeTokens(
        creator.address,
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

      let staker1 = await stakingPoints721.getStaker(creator.address, 1, anyone2);

      assert.equal(staker1.stakersTokens.length, 3);
      assert.equal(staker1.stakersTokens[0].tokenId, 2);
      assert.equal(staker1.stakersTokens[1].tokenId, 3);
      assert.equal(staker1.stakersTokens[1].contractAddress, mock721.address);
      assert.equal(staker1.stakersTokens[2].tokenId, 2);
      assert.equal(staker1.stakersTokens[2].contractAddress, mock721_2.address);

      let staker2 = await stakingPoints721.getStaker(creator.address, 1, anyone1);
      assert.equal(staker2.stakersTokens.length, 0);
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
              pointsRatePerDay: 1234,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721.address,
              pointsRatePerDay: 125,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721_2.address,
              pointsRatePerDay: 125,
              startTime: 1680680461,
              endTime: 95625733261,
            },
          ],
        },
        { from: owner }
      );
      await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await stakingPoints721.stakeTokens(
        creator.address,
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

      let staker = await stakingPoints721.getStaker(creator.address, 1, anyone2);

      assert.equal(staker.stakersTokens.length, 3);
      assert.equal(staker.stakersTokens[0].tokenId, 2);
      assert.equal(staker.stakersTokens[0].timeUnstaked, 0);
      assert.equal(staker.stakersTokens[1].tokenId, 3);
      assert.equal(staker.stakersTokens[1].contractAddress, mock721.address);
      assert.equal(staker.stakersTokens[1].timeUnstaked, 0);
      assert.equal(staker.stakersTokens[2].tokenId, 2);
      assert.equal(staker.stakersTokens[2].contractAddress, mock721_2.address);
      assert.equal(staker.stakersTokens[2].timeUnstaked, 0);
      assert.equal(staker.pointsRedeemed, 0);

      // unstake #1
      await truffleAssert.reverts(
        stakingPoints721.unstakeTokens(
          creator.address,
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
        "Cannot unstake tokens for someone who has not staked"
      );

      await stakingPoints721.unstakeTokens(
        creator.address,
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

      let staker_again = await stakingPoints721.getStaker(creator.address, 1, anyone2);
      assert.equal(staker_again.stakersTokens.length, 3);
      assert.equal(staker_again.stakersTokens[0].timeUnstaked != 0, true);
      assert.equal(staker_again.stakersTokens[1].timeUnstaked, 0);
      assert.equal(staker_again.stakersTokens[2].timeUnstaked != 0, true);
      assert.equal(staker_again.pointsRedeemed !== 0, true);
    });

    it("Redeems points", async function () {
      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        {
          paymentReceiver: owner,
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRatePerDay: 1234000,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721.address,
              pointsRatePerDay: 12500000,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721_2.address,
              pointsRatePerDay: 12000000,
              startTime: 1680680461,
              endTime: 95625733261,
            },
          ],
        },
        { from: owner }
      );
      await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anotherOwner });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anyone1 });
      await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone1 });
      await stakingPoints721.stakeTokens(
        creator.address,
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

      await stakingPoints721.stakeTokens(
        creator.address,
        1,
        [
          {
            tokenAddress: mock721_2.address,
            tokenId: 3,
          },
        ],
        { from: anotherOwner }
      );
      await stakingPoints721.stakeTokens(
        creator.address,
        1,
        [
          {
            tokenAddress: mock721.address,
            tokenId: 1,
          },
          {
            tokenAddress: mock721_2.address,
            tokenId: 1,
          },
        ],
        { from: anyone1 }
      );

      let user1 = await stakingPoints721.getStaker(creator.address, 1, anyone1);
      let user2 = await stakingPoints721.getStaker(creator.address, 1, anyone2);
      assert.equal(0, user1.pointsRedeemed);
      assert.equal(0, user2.pointsRedeemed);

      function timeout(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
      }

      await timeout(1000);

      await stakingPoints721.redeemPoints(creator.address, 1, { from: anyone1 });
      await stakingPoints721.redeemPoints(creator.address, 1, { from: anyone2 });

      let user1Updated = await stakingPoints721.getStaker(creator.address, 1, anyone1);
      let user2Updated = await stakingPoints721.getStaker(creator.address, 1, anyone2);
      assert.equal(true, user1Updated.pointsRedeemed != 0);
      assert.equal(true, user2Updated.pointsRedeemed != 0);
    });
    it("Redeems points at unstaking", async function () {
      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        {
          paymentReceiver: owner,
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRatePerDay: 1234000,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721.address,
              pointsRatePerDay: 12500000,
              startTime: 1680680461,
              endTime: 95625733261,
            },
            {
              tokenAddress: mock721_2.address,
              pointsRatePerDay: 12000000,
              startTime: 1680680461,
              endTime: 95625733261,
            },
          ],
        },
        { from: owner }
      );
      await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anyone2 });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anotherOwner });
      await mock721_2.setApprovalForAll(stakingPoints721.address, true, { from: anyone1 });
      await mock721.setApprovalForAll(stakingPoints721.address, true, { from: anyone1 });
      await stakingPoints721.stakeTokens(
        creator.address,
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

      await stakingPoints721.stakeTokens(
        creator.address,
        1,
        [
          {
            tokenAddress: mock721_2.address,
            tokenId: 3,
          },
        ],
        { from: anotherOwner }
      );
      await stakingPoints721.stakeTokens(
        creator.address,
        1,
        [
          {
            tokenAddress: mock721.address,
            tokenId: 1,
          },
          {
            tokenAddress: mock721_2.address,
            tokenId: 1,
          },
        ],
        { from: anyone1 }
      );

      let user1 = await stakingPoints721.getStaker(creator.address, 1, anyone1);
      let user2 = await stakingPoints721.getStaker(creator.address, 1, anyone2);
      assert.equal(0, user1.pointsRedeemed);
      assert.equal(0, user2.pointsRedeemed);

      function timeout(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
      }

      await timeout(5000);

      let points1 = await stakingPoints721.getPointsForWallet(creator.address, 1, anyone2);
      assert.strictEqual(points1.gt(0), true);

      await stakingPoints721.unstakeTokens(
        creator.address,
        1,
        [
          {
            tokenAddress: mock721_2.address,
            tokenId: 2,
          },
        ],
        { from: anyone2 }
      );
      await stakingPoints721.unstakeTokens(
        creator.address,
        1,
        [
          {
            tokenAddress: mock721_2.address,
            tokenId: 1,
          },
        ],
        { from: anyone1 }
      );
      await stakingPoints721.unstakeTokens(
        creator.address,
        1,
        [
          {
            tokenAddress: mock721.address,
            tokenId: 2,
          },
        ],
        { from: anyone2 }
      );
      let points = await stakingPoints721.getPointsForWallet(creator.address, 1, anyone2);
      let user1Updated = await stakingPoints721.getStaker(creator.address, 1, anyone1);
      let user2Updated = await stakingPoints721.getStaker(creator.address, 1, anyone2);
      assert.strictEqual(points.gt(points1), true);
      assert.strictEqual(true, user1Updated.pointsRedeemed != 0);
      assert.strictEqual(true, user2Updated.pointsRedeemed != 0);
    });
  });
});
