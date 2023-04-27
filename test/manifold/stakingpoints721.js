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
    let creator, stakingPoints;
    let fee;

    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", { from: owner });
      stakingPoints721 = await ERC721StakingPoints.new({ from: owner });
      manifoldMembership = await MockManifoldMembership.new({ from: owner });
      await stakingPoints721.setMembershipAddress(manifoldMembership.address);

      stakable721 = await ERC721Creator.new("Stakable NFT 1", "TEST", { from: owner });
      stakeable721_2 = await ERC721Creator.new("Stakable NFT 2", "TEST", { from: anotherOwner });
      notStakeable1155 = await ERC1155Creator.new("1155", "TEST", { from: owner });

      oz721 = await ERC721.new("Test", "TEST", { from: owner });
      oz1155 = await ERC1155.new("test.com", { from: owner });

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
          true,
          {
            paymentReceiver: owner,
            storageProtocol: 1,
            location: "XXX",
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRate: 1234,
                timeUnit: 100000,
                startTime: 1674768875,
                endTime: 1682541275,
                tokenSpec: 1,
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
          true,
          {
            paymentReceiver: owner,
            storageProtocol: 1,
            location: "XXX",
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRate: 0,
                timeUnit: 100000,
                startTime: 1674768875,
                endTime: 1682541275,
                tokenSpec: 1,
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
          true,
          {
            paymentReceiver: owner,
            storageProtocol: 1,
            location: "XXX",
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRate: 1234,
                timeUnit: 0,
                startTime: 1674768875,
                endTime: 1682541275,
                tokenSpec: 1,
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
          true,
          {
            paymentReceiver: owner,
            storageProtocol: 1,
            location: "XXX",
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRate: 1234,
                timeUnit: 100000,
                startTime: 1682541275,
                endTime: 1674768875,
                tokenSpec: 1,
              },
            ],
          },
          { from: owner }
        ),
        "Staking rule: Invalid time range"
      );
      // has invalid staking rule (token spec is not erc721)
      await truffleAssert.reverts(
        stakingPoints721.initializeStakingPoints(
          creator.address,
          1,
          true,
          {
            paymentReceiver: owner,
            storageProtocol: 1,
            location: "XXX",
            stakingRules: [
              {
                tokenAddress: manifoldMembership.address,
                pointsRate: 1234,
                timeUnit: 100000,
                startTime: 1674768875,
                endTime: 1682541275,
                tokenSpec: 2,
              },
            ],
          },
          { from: owner }
        ),
        "Staking rule: Only supports ERC721 at this time"
      );
      // has valid staking rule (token spec is not erc721)

      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        true,
        {
          paymentReceiver: owner,
          storageProtocol: 1,
          location: "XXX",
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRate: 1234,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
              tokenSpec: 1,
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
    // it("Admin updates uri", function () {});
    it("User stakes two tokens, and unstakes one redeem points for that token", async function () {
      await stakingPoints721.initializeStakingPoints(
        creator.address,
        1,
        true,
        {
          paymentReceiver: owner,
          storageProtocol: 1,
          location: "XXX",
          stakingRules: [
            {
              tokenAddress: manifoldMembership.address,
              pointsRate: 1234,
              timeUnit: 100000,
              startTime: 1674768875,
              endTime: 1682541275,
              tokenSpec: 1,
            },
          ],
        },
        { from: owner }
      );
      stakingPointsInstance = await stakingPoints721.getStakingPointsInstance(creator.address, 1);

      // stake token from ozERC1155 and have it revert
      // stake token from oz
      // stake token #2 from oz

      // unstake #1
      // assert pointsRedeemed

      // unstake #2
      // assert pointsRedeemed
    });
  });
});
