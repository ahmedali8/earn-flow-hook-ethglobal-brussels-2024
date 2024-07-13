// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/console2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Dividend Token
 */
contract DividendToken is Ownable, ERC20 {
    constructor(address _owner, string memory _name, string memory _symbol) Ownable(_owner) ERC20(_name, _symbol) {
        console2.log("caller: ", msg.sender);
    }

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }
}
