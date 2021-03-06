// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract ERC721License is ERC721Upgradeable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice rootContent stores cids for each license pointing to root content
    mapping(uint256 => string) public rootContent;

    event RootContentCIDUpdated(uint256 indexed tokenId, string rootContent);
    event RootContentCIDRemoved(uint256 indexed tokenId);

    function initialize(address admin) public {
        __ERC721_init("GeoWebLicense", "GEO");

        _setupRole(ADMIN_ROLE, admin);
    }

    function mintLicense(
        address to,
        uint256 tokenId,
        string calldata ceramicDocId
    ) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not admin");

        _safeMint(to, tokenId);
        _setContent(tokenId, ceramicDocId);
    }

    function setContent(uint256 tokenId, string calldata ceramicDocId)
        external
    {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721License: caller is not owner nor approved"
        );
        _setContent(tokenId, ceramicDocId);
    }

    function removeContent(uint256 tokenId) external {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721License: caller is not owner nor approved"
        );

        _removeContent(tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        override
        returns (bool)
    {
        require(
            _exists(tokenId),
            "ERC721: operator query for nonexistent token"
        );
        address owner = ownerOf(tokenId);
        return (spender == owner || hasRole(ADMIN_ROLE, spender));
    }

    function _setContent(uint256 tokenId, string memory ceramicDocId) internal {
        rootContent[tokenId] = ceramicDocId;

        emit RootContentCIDUpdated(tokenId, ceramicDocId);
    }

    function _removeContent(uint256 tokenId) internal {
        delete rootContent[tokenId];

        emit RootContentCIDRemoved(tokenId);
    }
}
