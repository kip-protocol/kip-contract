// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {KIPQuery} from "./KIPQuery.sol";

contract KIPQANFT is Context, ERC721URIStorage, Ownable {
    uint256 private _tokenId;

    address public queryAddress;
    KIPQuery private query;

    mapping(uint256 => string) private _tokenURI;

    // Token ID => Question ID
    mapping(uint256 => uint256) private _tokenQuestionId;

    constructor() ERC721("KIP QA NFT", "KIPQA") Ownable(_msgSender()) {}

    function _baseURI() internal pure override returns (string memory) {
        return "https://ipfs.io/ipfs/";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        string memory baseURI = _baseURI();
        return string.concat(baseURI, _tokenURI[tokenId]);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        require(_ownerOf(tokenId) == _msgSender() || _getApproved(tokenId) == _msgSender(), "KIP Error: illegal call");
        super.transferFrom(from, to, tokenId);
        query.update(_tokenQuestionId[tokenId], to);
    }

    function mint(uint256 questionId, address to, string calldata uri) public {
        require(_msgSender() == queryAddress, "KIP Error: illegal call");
        _tokenQuestionId[_tokenId] = questionId;
        _safeMint(to, _tokenId);
        _tokenURI[_tokenId] = uri;
        unchecked {
            _tokenId++;
        }
    }

    function setQueryAddress(address queryAddress_) external onlyOwner {
        queryAddress = queryAddress_;
        query = KIPQuery(queryAddress_);
    }
}
