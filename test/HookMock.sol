// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Iceberg} from "../src/Iceberg.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract HookMock is Iceberg {
    constructor(IPoolManager _poolManager) Iceberg(_poolManager) {}

    function afterInitializeCall(PoolKey calldata key) public {
        _afterInitialize(address(0), key, uint160(0), 0);
    }
}