// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract KIPToken is Context, ERC20, Ownable {
    constructor() ERC20("KIPToken", "KT") Ownable(_msgSender()) {
        _mint(_msgSender(), 10000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
