const truffleAssert = require('truffle-assertions');
const OperatorFilter = artifacts.require("CreatorOperatorFilterer");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-solidity/ERC721Creator.sol');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-solidity/ERC1155Creator.sol');
const tokenURI = "https://example.com";

contract('CreatorOperatorFilterer', function ([...accounts]) {
  const [owner, operator, operator2, anyone1] = accounts;

  describe("ERC721", () => {
    let creator, ext;

    beforeEach(async () => {
      creator = await ERC721Creator.new("gm", "GM", { from: owner, gas: 9000000 });
      ext = await OperatorFilter.new({ from: owner });
      await creator.setApproveTransfer(ext.address);
    });

    it('access test', async function () {
      // Must be admin
      await truffleAssert.reverts(ext.configureBlockedOperators(
        creator.address,
        [],[],
        {from:anyone1}
      ), "Wallet is not an admin");

      await truffleAssert.reverts(ext.configureBlockedOperatorHashes(
        creator.address,
        [],[],
        {from:anyone1}
      ), "Wallet is not an admin");

      await truffleAssert.reverts(ext.configureBlockedOperatorsAndHashes(
        creator.address,
        [],[],[],[],
        {from:anyone1}
      ), "Wallet is not an admin");
    });

    it('should allow operators not on filtered list', async () => {
      await creator.mintBase(owner, { from: owner });
      await creator.setApprovalForAll(operator, true, { from: owner });

      await creator.safeTransferFrom(owner, anyone1, 1, { from: operator });
    });

    it('should allow if operator owns token', async () => {
      await creator.mintBase(operator, { from: owner });

      await creator.safeTransferFrom(operator, anyone1, 1, { from: operator });
    })

    it('should block filtered operators', async () => {
      await creator.mintBase(owner, { from: owner });
      await creator.setApprovalForAll(operator, true, { from: owner });

      await ext.configureBlockedOperators(creator.address, [operator], [true], { from: owner })

      await truffleAssert.reverts(creator.safeTransferFrom(owner, anyone1, 1, { from: operator }));
      await truffleAssert.reverts(creator.transferFrom(owner, anyone1, 1, { from: operator }));
      await creator.safeTransferFrom(owner, anyone1, 1, { from: owner });
    })
  });

  describe("ERC1155", () => {
    let creator, ext;

    beforeEach(async () => {
      creator = await ERC1155Creator.new("gm", "gm", { from: owner, gas: 9000000 });
      ext = await OperatorFilter.new({ from: owner });

      await creator.setApproveTransfer(ext.address);
    });

    it('should allow operators not on filtered list', async () => {
      await creator.mintBaseNew([owner], [1], [tokenURI], { from: owner });
      await creator.setApprovalForAll(operator, true, { from: owner });

      await creator.safeTransferFrom(owner, anyone1, 1, 1, "0x0", { from: operator });
    });

    it('should allow if operator owns token', async () => {
      await creator.mintBaseNew([operator], [1], [tokenURI], { from: owner });

      await creator.safeTransferFrom(operator, anyone1, 1, 1, "0x0", { from: operator });
    })

    it('should block filtered operators', async () => {
      await creator.mintBaseNew([owner], [1], [tokenURI], { from: owner });
      await creator.setApprovalForAll(operator, true, { from: owner });

      await ext.configureBlockedOperators(creator.address, [operator], [true], { from: owner })

      await truffleAssert.reverts(creator.safeTransferFrom(owner, anyone1, 1, 1, "0x0", { from: operator }));
      await creator.safeTransferFrom(owner, anyone1, 1, 1, "0x0", { from: owner });
    })
  });

});
