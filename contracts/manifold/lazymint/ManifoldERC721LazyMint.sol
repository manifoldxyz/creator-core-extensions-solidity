// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IManifoldERC721LazyMint.sol";

/**
 * Manifold ERC721 Lazy Mint Controller Implementation
 */
contract ManifoldERC721LazyMint is CreatorExtension, ICreatorExtensionTokenURI, IManifoldERC721LazyMint, ReentrancyGuard {
    using Strings for uint256;

    mapping(address => mapping(uint256 => string)) _baseURI;
    mapping(address => mapping(uint256 => string)) _placeholderURI;
    mapping(address => mapping(uint256 => uint256)) _maxSupply;
    mapping(address => mapping(uint256 => uint256)) _totalSupply;
    // 0 - non-active, 1 - premint, 2 - open
    mapping(address => mapping(uint256 => uint8)) _salePhase;
    mapping(address => mapping(uint256 => uint256)) _mintPrice;
    mapping(address => mapping(uint256 => uint256)) _premintPrice;
    mapping(address => mapping(uint256 => uint256)) _maxTokensPerAddress;
    mapping(address => mapping(uint256 => mapping(address => bool))) _allowList;
    mapping(address => mapping(uint256 => address[])) _allowListKeys;
    mapping(address => mapping(uint256 => mapping(address => uint256))) _tokensMinted;
    mapping(address => mapping(uint256 => uint256)) _tokenIdToDrop;
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) _tokenIdToDropTokenId;
    mapping(address => mapping(uint256 => uint256)) _totalToWithdraw;
    mapping(address => uint256) _currentDrop;

    /**
     * @dev Only allows approved admins to call the specified function
     */
    modifier creatorAdminRequired(address creator) {
        require(IAdminControl(creator).isAdmin(msg.sender), "Must be owner or admin of creator contract");
        _;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorExtension, IERC165) returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId || interfaceId == type(IManifoldERC721LazyMint).interfaceId ||
               CreatorExtension.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IManifoldERC721LazyMint-createDrop}.
     */
    function createDrop(address creator, string calldata placeholderURI, uint256 maxSupply_, uint256 mintPrice_, uint256 premintPrice_, uint256 maxTokensPerAddress_) external override creatorAdminRequired(creator) returns(uint256) {
        _currentDrop[creator] += 1;
        uint256 drop = _currentDrop[creator];
        _placeholderURI[creator][drop] = placeholderURI;
        _maxSupply[creator][drop] = maxSupply_;
        _mintPrice[creator][drop] = mintPrice_;
        _premintPrice[creator][drop] = premintPrice_;
        _maxTokensPerAddress[creator][drop] = maxTokensPerAddress_;

        emit DropCreated(msg.sender, creator, drop, maxSupply_, mintPrice_, premintPrice_,maxTokensPerAddress_);
        return drop;
    }

    /**
     * @dev See {IManifoldERC721LazyMint-activatePremintPhase}.
     */
    function activatePremintPhase(address creator, uint256 drop) external override creatorAdminRequired(creator) {
        require(drop > 0, "Invalid drop");
        _salePhase[creator][drop] = 1;
    }

    /**
     * @dev See {IManifoldERC721LazyMint-activateSalePhase}.
     */
    function activateSalePhase(address creator, uint256 drop) external override creatorAdminRequired(creator) {
        require(drop > 0, "Invalid drop");
        _salePhase[creator][drop] = 2;
    }

    /**
     * @dev See {IManifoldERC721LazyMint-deactivateSales}.
     */
    function deactivateSales(address creator, uint256 drop) external override creatorAdminRequired(creator) {
        require(drop > 0, "Invalid drop");
        _salePhase[creator][drop] = 0;
    }

    /**
     * @dev See {IManifoldERC721LazyMint-salePhase}.
     */
    function salePhase(address creator, uint256 drop) external view override returns(uint8) {
        return _salePhase[creator][drop];
    }

    /**
     * @dev See {IManifoldERC721LazyMint-maxSupply}.
     */
    function maxSupply(address creator, uint256 drop) external view override returns(uint256) {
        return _maxSupply[creator][drop];
    }

    /**
     * @dev See {IManifoldERC721LazyMint-mintPrice}.
     */
    function mintPrice(address creator, uint256 drop) external view override returns(uint256) {
        return _mintPrice[creator][drop];
    }

    /**
     * @dev See {IManifoldERC721LazyMint-premintPrice}.
     */
    function premintPrice(address creator, uint256 drop) external view override returns(uint256) {
        return _premintPrice[creator][drop];
    }

    /**
     * @dev See {IManifoldERC721LazyMint-maxTokensPerAddress}.
     */
    function maxTokensPerAddress(address creator, uint256 drop) external view override returns(uint256) {
        return _maxTokensPerAddress[creator][drop];
    }

    /**
     * @dev See {IManifoldERC721LazyMint-isInAllowList}.
     */
    function isInAllowList(address creator, uint256 drop, address wallet) external view override returns(bool) {
        return _isInAllowList(creator, drop, wallet);
    }

    /**
     * @dev See {IManifoldERC721LazyMint-setAllowList}.
     */
    function setAllowList(address creator, uint256 drop, address[] calldata allowList_) external override creatorAdminRequired(creator) {
        // Remove previous allow list
        for (uint256 i = 0; i < _allowListKeys[creator][drop].length; i++) {
            _allowList[creator][drop][ _allowListKeys[creator][drop][i]] = false;
        }

        // Update with new allow list
        _allowListKeys[creator][drop] = allowList_;
        for (uint256 i = 0; i < allowList_.length; i++) {
            _allowList[creator][drop][allowList_[i]] = true;
        }
    }

    /**
     * @dev See {IManifoldERC721LazyMint-totalSupply}.
     */
    function totalSupply(address creator, uint256 drop) external view override returns(uint256) {
        return _totalSupply[creator][drop];
    }

    /**
     * @dev See {IManifoldERC721LazyMint-premint}.
     */
    function premint(address creator, uint256 drop, uint16 count) external payable override {
        require(_isInAllowList(creator, drop, msg.sender), "Account is not in the allow list");
        require(_salePhase[creator][drop] == 1, "Pre-mint is not active");
        require(_premintPrice[creator][drop] * count <= msg.value, "Ether value sent is not correct");
        _mint(creator, drop, count);
    }

    /**
     * @dev See {IManifoldERC721LazyMint-premint}.
     */
    function mint(address creator, uint256 drop, uint16 count) external payable override {
        require(_salePhase[creator][drop] == 2, "Sale is not active");
        require(_mintPrice[creator][drop] * count <= msg.value, "Ether value sent is not correct");
        _mint(creator, drop, count);
    }

    /**
     * @dev See {IManifoldERC721LazyMint-withdraw}.
     */
    function withdraw(address creator, uint256 drop, address payable to) external payable override creatorAdminRequired(creator) {
        payable(to).transfer(_totalToWithdraw[creator][drop]);
        _totalToWithdraw[creator][drop] = 0;
    }

    /**
     * @dev See {IManifoldERC721LazyMint-totalToWithdraw}.
     */
    function totalToWithdraw(address creator, uint256 drop) external view override returns(uint256) {
        return _totalToWithdraw[creator][drop];
    }

    /**
     * @dev See {IManifoldERC721LazyMint-reveal}.
     */
    function reveal(address creator, uint256 drop, string calldata baseURI) external override creatorAdminRequired(creator) {
        _baseURI[creator][drop] = baseURI;
    }

    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        uint256 drop = _tokenIdToDrop[creator][tokenId];

        bytes memory possibleBaseURI = bytes(_baseURI[creator][drop]);
        if (possibleBaseURI.length == 0) {
            return _placeholderURI[creator][drop];
        }

        uint256 dropTokenId = _tokenIdToDropTokenId[creator][drop][tokenId];
        return string(abi.encodePacked(_baseURI[creator][drop], dropTokenId.toString()));
    }

    function _mint(address creator, uint256 drop, uint16 count) internal {
        require(_checkMaxTokensForAddress(creator, drop, count, msg.sender), "Exceeded max available to purchase");
        require(_totalSupply[creator][drop] + count <= _maxSupply[creator][drop], "Purchase would exceed max tokens");

        _tokensMinted[creator][drop][msg.sender] += count;
        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = IERC721CreatorCore(creator).mintExtension(msg.sender);
            _tokenIdToDrop[creator][tokenId] = drop;
            _tokenIdToDropTokenId[creator][drop][tokenId] = _totalSupply[creator][drop] + i + 1;
        }
        _totalSupply[creator][drop] += count;
        _totalToWithdraw[creator][drop] += msg.value;
    }

    function _isInAllowList(address creator, uint256 drop, address wallet) internal view returns (bool) {
        return _allowList[creator][drop][wallet];
    }

    function _checkMaxTokensForAddress(address creator, uint256 drop, uint16 count, address recipient) internal view returns (bool) {
        // If _maxTokensPerAddress is -1 you can mint as many tokens as you want
        return (_tokensMinted[creator][drop][recipient] + count <= _maxTokensPerAddress[creator][drop]) || (_maxTokensPerAddress[creator][drop] < 0);
    }
}
