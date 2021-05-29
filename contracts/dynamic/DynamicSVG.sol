// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Test Token
/// @author: manifold.xyz

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "manifoldxyz-creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "manifoldxyz-creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "manifoldxyz-creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "../libraries/ABDKMath64x64.sol";


contract DynamicSVG is CreatorExtension, Ownable, ICreatorExtensionTokenURI {

    using Strings for uint256;
    using ABDKMath64x64 for int128;

    uint256 private immutable _completionTimestamp;
    address private immutable _creator;

    constructor(address creator) {
        _completionTimestamp = block.timestamp+31536000;
        _creator = creator;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorExtension, IERC165) returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId || super.supportsInterface(interfaceId);
    }

    function mint(address to) external onlyOwner {
        IERC721CreatorCore(_creator).mintExtension(to);
    }

    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        //require(creator == _creator, "Invalid token");
        int128 completion = 1;
        if (_completionTimestamp > block.timestamp) {
            completion = ABDKMath64x64.divu(_completionTimestamp-block.timestamp, 31536000);
        }
        uint256 centiDistance = uint256(completion.pow(3).mul(ABDKMath64x64.div(48, 100)).add(ABDKMath64x64.div(2, 100)).muli(100));

        //x^y = 2^(y*log_2(x))
        int128 c1curve = ABDKMath64x64.exp_2(ABDKMath64x64.div(75,100).mul(ABDKMath64x64.log_2(completion)));
        int128 c2curve = ABDKMath64x64.exp_2(ABDKMath64x64.div(125,100).mul(ABDKMath64x64.log_2(completion)));
        int128 w1value = ABDKMath64x64.fromUInt(uint256(keccak256(abi.encodePacked(IERC721(creator).ownerOf(tokenId))))%100).div(ABDKMath64x64.fromUInt(100));
        int128 w2value = ABDKMath64x64.fromUInt(uint256(keccak256(abi.encodePacked(IERC721(creator).ownerOf(tokenId)))>>128)%100).div(ABDKMath64x64.fromUInt(100));
        int128 randHue = ABDKMath64x64.mul(w1value, ABDKMath64x64.fromUInt(360));
        int128 randOffset = ABDKMath64x64.mul(w2value, ABDKMath64x64.fromUInt(180)).add(ABDKMath64x64.fromUInt(360)).sub(ABDKMath64x64.fromUInt(90));

        return string(abi.encodePacked('data:application/json;utf8,{"name":"Test Token", "description":"Test Description", "image":"data:image/svg+xml;utf8,',
            "<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' width='1000' height='1000' viewBox='-0.5 -0.5 1 1'>",
            _generateDefs(completion, c1curve, c2curve, randHue, randOffset),
            _generateG(centiDistance),
            "</svg>",
            '"}'));
    }

    function _generateDefs(int128 completion, int128 c1curve, int128 c2curve, int128 randHue, int128 randOffset) private pure returns (string memory) {
        uint256 g1color = uint256(int256(randHue.add(completion.mul(ABDKMath64x64.fromUInt(60))).toInt()));
        uint256 g1saturation = uint256(c1curve.muli(100));
        uint256 g1lightness = uint256(c1curve.muli(70)+15);
        uint256 g2color = uint256(int256(randHue.add(completion.mul(ABDKMath64x64.fromUInt(60)).add(randOffset)).toInt()));
        uint256 g2saturation = uint256(c2curve.muli(50));
        uint256 g2lightness = uint256(c2curve.muli(35)+15);
        return string(abi.encodePacked(
                "<defs>",
                    "<linearGradient id='g' x1='0%' x2='0%' y1='1%' y2='100%'>",
                        "<stop id='g1' offset='0%' stop-color='hsl(",g1color.toString(),",",g1saturation.toString(),"%,",g1lightness.toString(),"%)' />",
                        "<stop id='g2' offset='50%' stop-color='hsl(",g2color.toString(),",",g2saturation.toString(),"%,",g2lightness.toString(),"%)' />",
                        "<stop id='g3' offset='100%' stop-color='hsl(0,0%,15%)' />",
                    "</linearGradient>",
                "</defs>"));
    }

    function _generateG(uint256 centiDistance) private pure returns (string memory) {
        return string(abi.encodePacked(
                "<g>",
                    "<rect id='rect' x='-0.5' y='-0.5' width='1' height='1' fill='hsl(0,0%,15%)' />",
                    "<circle id='circ' cx='0' cy='0' r='0.",centiDistance.toString(),"' fill='url(#g)'>",
                        "<animateTransform attributeName='transform' type='rotate' from='0' to='360' dur='60s' repeatCount='indefinite' />",
                    "</circle>",
                "</g>"));
    }
}
