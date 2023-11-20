// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface ICross {
    struct Message {
        // messageType: 1: Create Collection; 2: Transfer; 3: Mint QA
        uint8 messageType;
        // data: The data would be transferred.
        bytes data;
    }

    struct Collection {
        // Collection ID
        uint256 id;
        // Creator
        address creator;
        // Supply
        uint256 supply;
        // Query Price
        uint256 price;
        // Query Royalties
        uint256 royalties;
        // Category
        uint8 category;
        // Query Count
        uint32 queryCount;
        // Mint Count
        uint32 mintCount;
    }

    struct TransferInfo {
        // From Address
        address from;
        // To Address
        address to;
        // Collection ID
        uint256 id;
        // Transfer Value
        uint256 value;
        // Transfer Data
        bytes data;
    }

    struct MintInfo {
        // To Address
        address to;
        // URI
        string uri;
    }

    // Emit when cross blockchain
    event MessageSent(bytes32 messageId);

    // Emit when cross blockchain
    event MessageReceived(bytes32 messageId);
}
