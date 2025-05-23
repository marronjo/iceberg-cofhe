// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {Constants} from "./base/Constants.sol";
import {Iceberg} from "../src/Iceberg.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/// @notice Mines the address and deploys the Iceberg.sol Hook contract
contract IcebergScript is Script, Constants {
    function setUp() public {}

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(Iceberg).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();
        Iceberg iceberg = new Iceberg{salt: salt}(IPoolManager(POOLMANAGER));
        require(address(iceberg) == hookAddress, "IcebergScript: hook address mismatch");
    }
}
