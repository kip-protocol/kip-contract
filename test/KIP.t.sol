// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KIP.sol";

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
}

contract KIPTest is Test {
    uint256 sepholiaFork;

    KIP kip;

    function setUp() public {
        sepholiaFork = vm.createFork("https://eth-sepolia.g.alchemy.com/v2/61_02oiFhc8CvMWwDnYsaCkNAuG7Ss8p");
        kip = new KIP(address(0xD0daae2231E9CB96b94C8512223533293C3693Bf));
    }

    function testCreateCollection() public {
        kip.createCollection(100, 1000000, 5, 1, "aaa");
        string memory uri = kip.uri(1);
        assertEq(uri, "aaa");
        uint256[] memory collections = kip.getCategoryCollections(1);
        console.log(collections.length);
    }

    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        public
        pure
        returns (bytes4)
    {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }
}
