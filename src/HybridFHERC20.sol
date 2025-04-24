// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FHE} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/**
 * @dev Minimal implementation of an FHERC20 token
 * Implementation of the bare minimum methods to make
 * the hook work with a hybrid FHE / ERC20 token
 */
contract HybridFHERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address user, uint256 amount) public {
        _mint(user, amount);
    }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}