// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "../libraries/ABDKMath64x64.sol";
import "../libraries/single-creator/ERC721/ERC721SingleCreatorExtensionBase.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * Lazy mint with whitelist ERC721 tokens
 */
abstract contract ERC721LazyMintWhitelistBase is ERC721SingleCreatorExtensionBase, ICreatorExtensionTokenURI, ReentrancyGuard {
    using Strings for uint256;
    using ABDKMath64x64 for uint;

    string private _tokenPrefix;
    uint256 public _tokensMinted;
    mapping(uint256 => uint256) private _tokenEdition;
    uint private MINT_PRICE = 0.1 ether; // to be changed
    uint private MAX_MINTS = 50; // to be changed
    bytes32 merkleRoot;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId;
    }

    function _initialize(address creator, string memory prefix) internal {
      require(_creator == address(0), "Already initialized");
      _setCreator(creator);
      _tokenPrefix = prefix;
    }

    function onAllowList(address claimer, bytes32[] memory proof) public view returns(bool) {
        bytes32 leaf = keccak256(abi.encodePacked(claimer));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    function _setAllowList(bytes32 _merkleRoot) internal {
        merkleRoot = _merkleRoot;
    }

    /**
     * @dev Mint token if you are on the whitelist
     */
    function _premint(address[] memory to) internal {
        for (uint i = 0; i < to.length; i++) {
            _tokenEdition[IERC721CreatorCore(_creator).mintExtension(to[i])] = _tokensMinted + i + 1;
        }
        _tokensMinted += to.length;
        MAX_MINTS += to.length; // Extend max mints when preminting
    }
    
    /**
     * @dev Mint token if you are on the whitelist
     */
    function _mint(bytes32[] memory merkleProof) internal {
        require(_tokensMinted < MAX_MINTS, "Not enough mints left");
        require(MINT_PRICE == msg.value, "Not enough ETH");
        require(onAllowList(msg.sender, merkleProof), "Not on allowlist");

        _tokenEdition[IERC721CreatorCore(_creator).mintExtension(msg.sender)] = _tokensMinted + 1;
        _tokensMinted += 1;
    }

    /**
     * Set the token URI prefix
     */
    function _setTokenURIPrefix(string calldata prefix) internal {
        _tokenPrefix = prefix;
    }

    function _withdraw(address _to, uint amount) internal {
        payable(_to).transfer(amount);
    }

    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        require(creator == _creator && _tokenEdition[tokenId] != 0, "Invalid token");
        return  string(abi.encodePacked(_tokenPrefix, _tokenEdition[tokenId].toString()));
    }
    
}
