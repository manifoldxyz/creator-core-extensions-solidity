const truffleAssert = require('truffle-assertions');
const OperatorFilter = artifacts.require("OperatorFilterer");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-solidity/ERC721Creator.sol');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-solidity/ERC1155Creator.sol');
const MockRegistry = artifacts.require("MockRegistry");
const tokenURI = "https://example.com";

contract('OperatorFilterer', function ([...accounts]) {
  const [owner, operator, operator2, anyone1] = accounts;

  describe("ERC721", () => {
    let creator, registry, ext;

    beforeEach(async () => {
      creator = await ERC721Creator.new("gm", "GM", { from: owner, gas: 9000000 });
      registry = await MockRegistry.new({ from: owner });
      ext = await OperatorFilter.new(registry.address, '0x000000000000000000000000000000000000dEaD', { from: owner });

      await creator.setApproveTransfer(ext.address);
    });

    it('should allow operators not on filtered list', async () => {
      await registry.setBlockedOperators([operator2 /* <-- not `operator` */], { from: owner });
      await creator.mintBase(owner, { from: owner });
      await creator.setApprovalForAll(operator, true, { from: owner });

      await creator.safeTransferFrom(owner, anyone1, 1, { from: operator });
    });

    it('should allow if operator owns token', async () => {
      await registry.setBlockedOperators([operator], { from: owner });
      await creator.mintBase(operator, { from: owner });

      await creator.safeTransferFrom(operator, anyone1, 1, { from: operator });
    })

    it('should block filtered operators', async () => {
      await registry.setBlockedOperators([operator], { from: owner });
      await creator.mintBase(owner, { from: owner });
      await creator.setApprovalForAll(operator, true, { from: owner });

      await truffleAssert.reverts(creator.safeTransferFrom(owner, anyone1, 1, { from: operator }));
      await truffleAssert.reverts(creator.transferFrom(owner, anyone1, 1, { from: operator }));
      await creator.safeTransferFrom(owner, anyone1, 1, { from: owner });
    })

    it('should return registry and subscription', async () => {
      assert.equal(registry.address, await ext.OPERATOR_FILTER_REGISTRY());
      assert.equal('0x000000000000000000000000000000000000dEaD', await ext.SUBSCRIPTION());
    });
  });

  describe("ERC1155", () => {
    let creator, registry, ext;

    beforeEach(async () => {
      creator = await ERC1155Creator.new("gm", "gm", { from: owner, gas: 9000000 });
      registry = await MockRegistry.new({ from: owner });
      ext = await OperatorFilter.new(registry.address, '0x000000000000000000000000000000000000dEaD', { from: owner });

      await creator.setApproveTransfer(ext.address);
    });

    it('should allow operators not on filtered list', async () => {
      await registry.setBlockedOperators([operator2 /* <-- not `operator` */], { from: owner });
      await creator.mintBaseNew([owner], [1], [tokenURI], { from: owner });
      await creator.setApprovalForAll(operator, true, { from: owner });

      await creator.safeTransferFrom(owner, anyone1, 1, 1, "0x0", { from: operator });
    });

    it('should allow if operator owns token', async () => {
      await registry.setBlockedOperators([operator], { from: owner });
      await creator.mintBaseNew([operator], [1], [tokenURI], { from: owner });

      await creator.safeTransferFrom(operator, anyone1, 1, 1, "0x0", { from: operator });
    })

    it('should block filtered operators', async () => {
      await registry.setBlockedOperators([operator], { from: owner });
      await creator.mintBaseNew([owner], [1], [tokenURI], { from: owner });
      await creator.setApprovalForAll(operator, true, { from: owner });

      await truffleAssert.reverts(creator.safeTransferFrom(owner, anyone1, 1, 1, "0x0", { from: operator }));
      await creator.safeTransferFrom(owner, anyone1, 1, 1, "0x0", { from: owner });
    })
  });

});
