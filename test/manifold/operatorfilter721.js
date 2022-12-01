const truffleAssert = require('truffle-assertions');
const OperatorFilter = artifacts.require("OperatorFilterer");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-solidity/MockERC721');
const ERC1155Creator = artifacts.require('@manifoldxyz/creator-core-solidity/MockERC1155');
const MockRegistry = artifacts.require("MockRegistry");
const tokenURI = "https://example.com";

contract('OperatorFilter', function ([...accounts]) {
  const [owner, operator, operator2, anyone1] = accounts;

  const setup = async ({ failAddresses }) => {
    const creator = await ERC721Creator.new("gm", "GM", { from: owner, gas: 9000000 });
    const mock = await MockRegistry.new(failAddresses, { from: owner });
    const ext = await ERC721OperatorFilter.new(mock.address, '0x000000000000000000000000000000000000dEaD', false, { from: owner });

    await creator.setApproveExtension(ext.address, "", { from: owner });

    return { creator, mock, ext };
  }
  
  describe('minting', function () {
    it('should mint a token', async function() {
      const { creator, mock, ext } = await setup({ failAddresses: [] });

      assert.equal(await creator.balanceOf(owner), 0);
      await ext.mint(creator.address, owner, tokenURI, { from: owner });
      assert.equal(await creator.balanceOf(owner), 1);
    })

    it('should block minting', () => {

    });
  });

  describe('operator filter', function() {
    it('should allow when empty', async function() {
      const { creator, mock, ext } = await setup({ failAddresses: [] });

      await ext.mint(creator.address, owner, tokenURI, { from: owner });
      await creator.approve(operator, 1, { from: owner });
      await creator.transferFrom(owner, anyone1, 1, { from: operator });

      assert.equal(await creator.balanceOf(anyone1), 1);
    })

    it('should allow when not in registry', async function() {
      const { creator, mock, ext } = await setup({ failAddresses: [operator2] });

      await ext.mint(creator.address, owner, tokenURI, { from: owner });
      await creator.approve(operator, 1, { from: owner });
      await creator.transferFrom(owner, anyone1, 1, { from: operator });

      assert.equal(await creator.balanceOf(anyone1), 1);
    })

    it('should block even when approved', async function () {
      const { creator, mock, ext } = await setup({ failAddresses: [operator] });

      await ext.mint(creator.address, owner, tokenURI, { from: owner });
      await creator.approve(operator, 1, { from: owner });

      truffleAssert.reverts(creator.transferFrom(owner, anyone1, 1, { from: operator }));
      truffleAssert.reverts(creator.safeTransferFrom(owner, anyone1, 1, { from: operator }));
    });

    it('should block even when approved for all', async function () {
      const { creator, mock, ext } = await setup({ failAddresses: [operator] });

      await ext.mint(creator.address, owner, tokenURI, { from: owner });
      await creator.setApprovalForAll(operator, true, { from: owner });

      truffleAssert.reverts(creator.transferFrom(owner, anyone1, 1, { from: operator }));
      truffleAssert.reverts(creator.safeTransferFrom(owner, anyone1, 1, { from: operator }));
    });
  })
});
