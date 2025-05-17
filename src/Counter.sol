// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//Uniswap Imports
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

//FHE Imports
import {FHE, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract Counter is BaseHook {
    using PoolIdLibrary for PoolKey;

    // NOTE: ---------------------------------------------------------
    // more natural syntax with euint operations by using FHE library
    // all euint types are wrapped forms of uint256
    // therefore using library for uint256 works for all euint types
    // ---------------------------------------------------------------
    using FHE for uint256;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => euint128 count) public beforeSwapCount;
    mapping(PoolId => euint128 count) public afterSwapCount;

    mapping(PoolId => euint128 count) public beforeAddLiquidityCount;
    mapping(PoolId => euint128 count) public beforeRemoveLiquidityCount;

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

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        euint128 current = beforeSwapCount[key.toId()];
        beforeSwapCount[key.toId()] = current.add(FHE.asEuint128(1)); //add encrypted 1 to beforeSwapCount

        FHE.allowThis(beforeSwapCount[key.toId()]); //allow this contract to access and use this new value

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        euint128 current = afterSwapCount[key.toId()];
        afterSwapCount[key.toId()] = current.add(FHE.asEuint128(1)); //add encrypted 1 to afterSwapCount

        FHE.allowThis(afterSwapCount[key.toId()]); //allow this contract to access and use this new value

        return (BaseHook.afterSwap.selector, 0);
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        euint128 current = beforeAddLiquidityCount[key.toId()];
        beforeAddLiquidityCount[key.toId()] = current.add(FHE.asEuint128(1)); //add encrypted 1 to beforeAddLiquidityCount

        FHE.allowThis(beforeAddLiquidityCount[key.toId()]); //allow this contract to access and use this new value

        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        euint128 current = beforeRemoveLiquidityCount[key.toId()];
        beforeRemoveLiquidityCount[key.toId()] = current.add(FHE.asEuint128(1)); //add encrypted 1 to beforeRemoveLiquidityCount

        FHE.allowThis(beforeRemoveLiquidityCount[key.toId()]); //allow this contract to access and use this new value

        return BaseHook.beforeRemoveLiquidity.selector;
    }
}
