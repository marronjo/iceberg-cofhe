// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {HybridFHERC20} from "../src/HybridFHERC20.sol";

contract HybridFHERC20Script is Script {
    function setUp() public {}

    function run() public returns(address, address) {
        vm.startBroadcast();
        HybridFHERC20 token0 = new HybridFHERC20("MELT Token", "MELT");
        HybridFHERC20 token1 = new HybridFHERC20("ICE Token", "ICE");
        vm.stopBroadcast();

        return(address(token0), address(token1));
    }
}