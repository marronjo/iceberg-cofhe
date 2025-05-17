// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

library SortTokens {
    function sort(address tokenA, address tokenB)
        internal
        pure
        returns (Currency _currency0, Currency _currency1)
    {
        if (tokenA < tokenB) {
            (_currency0, _currency1) = (Currency.wrap(tokenA), Currency.wrap(tokenB));
        } else {
            (_currency0, _currency1) = (Currency.wrap(tokenB), Currency.wrap(tokenA));
        }
    }
}
