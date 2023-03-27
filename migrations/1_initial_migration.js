const Migrations = artifacts.require("Migrations");
const BurnRedeemLib = artifacts.require("BurnRedeemLib");
const ERC1155BurnRedeem = artifacts.require("ERC1155BurnRedeem");
const ERC721BurnRedeem = artifacts.require("ERC721BurnRedeem");


module.exports = function (deployer) {
  deployer.deploy(Migrations);
  deployer.deploy(BurnRedeemLib).then(() => {
      deployer.link(BurnRedeemLib, ERC1155BurnRedeem);
      deployer.link(BurnRedeemLib, ERC721BurnRedeem);
  });
};
