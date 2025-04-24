// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//Uniswap Imports
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

//FHE Imports
import { FHE, euint256 } from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract Counter is BaseHook {
    using PoolIdLibrary for PoolKey;

    //allow for more natural syntax with euint256 operations
    //by utilising the FHE library
    using FHE for euint256;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => euint256 count) public beforeSwapCount;
    mapping(PoolId => euint256 count) public afterSwapCount;

    mapping(PoolId => euint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => euint256 count) public beforeRemoveLiquidityCount;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        euint256 current = beforeSwapCount[key.toId()];
        beforeSwapCount[key.toId()] = current.add(FHE.asEuint256(1)); //add encrypted 1 to beforeSwapCount

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        euint256 current = afterSwapCount[key.toId()];
        afterSwapCount[key.toId()] = current.add(FHE.asEuint256(1)); //add encrypted 1 to afterSwapCount

        return (BaseHook.afterSwap.selector, 0);
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        euint256 current = beforeAddLiquidityCount[key.toId()];
        beforeAddLiquidityCount[key.toId()] = current.add(FHE.asEuint256(1)); //add encrypted 1 to beforeAddLiquidityCount

        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        euint256 current = beforeRemoveLiquidityCount[key.toId()];
        beforeRemoveLiquidityCount[key.toId()] = current.add(FHE.asEuint256(1));

        return BaseHook.beforeRemoveLiquidity.selector;
    }
}
