// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IFHERC20} from "../../src/interface/IFHERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @notice Shared configuration between scripts
contract Config {
    /// @dev populated with default anvil addresses
    IFHERC20 immutable token0;
    IFHERC20 immutable token1; 
    IHooks immutable hookContract;

    Currency immutable currency0; 
    Currency immutable currency1;

    constructor(){
        if(block.chainid == 11155111){      // Ethereum Sepolia
            token0 = IFHERC20(address(0x0eA00720cAA3b6A5d18683D09A75E8425934529c));
            token1 = IFHERC20(address(0xBA131d183F67dD1B4252487681b598B6bC165D17));
            hookContract = IHooks(address(0x5487bfA4195EB06d0084e3B5Cb52970396C350c0));
            currency0 = Currency.wrap(address(token0));
            currency1 = Currency.wrap(address(token1));
        }
        //
        // } else if(block.chainid == 421614){ // Arbitrum Sepolia
        //     token0 = IFHERC20(address(0x29844F233a9b5411800a7264F15CfF794A9F4303));
        //     token1 = IFHERC20(address(0x3585004F86af7b95B8aD63a898C90279B101b678));
        //     hookContract = IHooks(address(0xD5D3106da310E6cC784D52F46638EF3f0586d0c0));
        //     currency0 = Currency.wrap(address(token0));
        //     currency1 = Currency.wrap(address(token1));
        // }
    }
}
