const truffleAssert = require('truffle-assertions');
const OperatorFilter = artifacts.require("OperatorFilterer");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-solidity/MockERC721');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-solidity/MockERC1155');
const MockRegistry = artifacts.require("MockRegistry");
const tokenURI = "https://example.com";

contract('OperatorFilterer', function ([...accounts]) {
  const [owner, operator, operator2, anyone1] = accounts;

  describe("ERC721", () => {
    let creator, mock, ext;

    beforeEach(async () => {
      creator = await ERC721Creator.new("gm", "GM", { from: owner, gas: 9000000 });
      mock = await MockRegistry.new({ from: owner });
      ext = await OperatorFilter.new(mock.address, '0x000000000000000000000000000000000000dEaD', false, { from: owner });
    })
  });

  describe("ERC1155", () => {
    let creator, registry, ext;

    beforeEach(async () => {
      creator = await ERC1155Creator.new("gm", "GM", { from: owner, gas: 9000000 });
      registry = await MockRegistry.new({ from: owner });
      ext = await OperatorFilter.new(mock.address, '0x000000000000000000000000000000000000dEaD', false, { from: owner });

      await creator.setApproveTransfer(ext.address);
    });

    it('should allow', () => { })
    it('should allow if operator owns token', async () => { })
    it('should block filtered operators', async () => {
      await registry.setBlockedOperators([operator], true);
      await creator.mintBase(owner, tokenURI, { from: owner });
      await creator.approve(operator, 1, { from: owner });

      // operator is blocked
      await truffleAssert.reverts(creator.transferFrom(owner, anyone1, 1, { from: operator }));
      await truffleAssert.reverts(creator.safeTransferFrom(owner, anyone1, 1, { from: operator }));
      
      // but owner can still transfer
      await creator.transferFrom(owner, anyone1, 1, { from: owner });
    })
  });

  // describe('operator filter', function() {
  //   it('should allow when empty', async function() {
  //     const { creator, mock, ext } = await setup({ failAddresses: [] });

  //     await ext.mint(creator.address, owner, tokenURI, { from: owner });
  //     await creator.approve(operator, 1, { from: owner });
  //     await creator.transferFrom(owner, anyone1, 1, { from: operator });

  //     assert.equal(await creator.balanceOf(anyone1), 1);
  //   })

  //   it('should allow when not in registry', async function() {
  //     const { creator, mock, ext } = await setup({ failAddresses: [operator2] });

  //     await ext.mint(creator.address, owner, tokenURI, { from: owner });
  //     await creator.approve(operator, 1, { from: owner });
  //     await creator.transferFrom(owner, anyone1, 1, { from: operator });

  //     assert.equal(await creator.balanceOf(anyone1), 1);
  //   })

  //   it('should block even when approved', async function () {
  //     const { creator, mock, ext } = await setup({ failAddresses: [operator] });

  //     await ext.mint(creator.address, owner, tokenURI, { from: owner });
  //     await creator.approve(operator, 1, { from: owner });

  //     truffleAssert.reverts(creator.transferFrom(owner, anyone1, 1, { from: operator }));
  //     truffleAssert.reverts(creator.safeTransferFrom(owner, anyone1, 1, { from: operator }));
  //   });

  //   it('should block even when approved for all', async function () {
  //     const { creator, mock, ext } = await setup({ failAddresses: [operator] });

  //     await ext.mint(creator.address, owner, tokenURI, { from: owner });
  //     await creator.setApprovalForAll(operator, true, { from: owner });

  //     truffleAssert.reverts(creator.transferFrom(owner, anyone1, 1, { from: operator }));
  //     truffleAssert.reverts(creator.safeTransferFrom(owner, anyone1, 1, { from: operator }));
  //   });
  // })
});
