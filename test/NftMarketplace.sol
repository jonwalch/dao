pragma solidity ^0.8.0;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "../src/Dao.sol";
import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";


contract NftMarketplaceImpl is ERC721, NftMarketplace, IERC721Receiver {
    uint256 private _tokenIds;
    constructor(uint8 numNfts) ERC721 ("Bing", "BONG") {
        for (uint8 i = 0; i < numNfts; i++) {
            _safeMint(address(this), i);
        }
        _tokenIds = numNfts;
    }

    function _getPrice(address nftContract, uint nftId) private pure returns (uint price) {
       return 0.9 ether;
    }

    function getPrice(address nftContract, uint nftId) external returns (uint price) {
        return _getPrice(nftContract, nftId);
    }

    function buy(address nftContract, uint nftId) external payable returns (bool success){
        require(msg.value >= _getPrice(nftContract, nftId), "NftMarketplace: wrong price");
        _approve(msg.sender, nftId);
        safeTransferFrom(address(this), msg.sender, nftId);
        return true;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data)
    public returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
