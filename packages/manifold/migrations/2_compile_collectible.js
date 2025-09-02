// This migration ensures Collectible contracts are compiled for tests
const ERC721Collectible = artifacts.require("ERC721Collectible");
const MockManifoldMembership = artifacts.require("MockManifoldMembership");

module.exports = function (deployer) {
  // We don't need to deploy, just ensure compilation
  // The artifacts.require() calls above will trigger compilation
};