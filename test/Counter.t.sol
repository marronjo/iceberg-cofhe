// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//Foundry Imports
import "forge-std/Test.sol";

//Uniswap Imports
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {Counter} from "../src/Counter.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {SortTokens} from "./utils/SortTokens.sol";

import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

//FHE Imports
import {FHE, InEuint128, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-foundry-mocks/CoFheTest.sol";
import {HybridFHERC20} from "../src/HybridFHERC20.sol";
import {IFHERC20} from "../src/interface/IFHERC20.sol";

contract CounterTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    //test instance with useful utilities for testing FHE contracts locally
    CoFheTest CFT;

    Counter hook;
    PoolId poolId;

    HybridFHERC20 fheToken0;
    HybridFHERC20 fheToken1;

    Currency fheCurrency0;
    Currency fheCurrency1;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    address private user = makeAddr("user");

    function setUp() public {
        //initialise new CoFheTest instance with logging turned off
        CFT = new CoFheTest(false);

        bytes memory token0Args = abi.encode("TOKEN0", "TOK0");
        deployCodeTo("HybridFHERC20.sol:HybridFHERC20", token0Args, address(123));

        bytes memory token1Args = abi.encode("TOKEN1", "TOK1");
        deployCodeTo("HybridFHERC20.sol:HybridFHERC20", token1Args, address(456));

        fheToken0 = HybridFHERC20(address(123));
        fheToken1 = HybridFHERC20(address(456));    //ensure address token1 always > address token0

        vm.label(user, "user");
        vm.label(address(this), "test");
        vm.label(address(fheToken0), "token0");
        vm.label(address(fheToken1), "token1");

        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();

        vm.startPrank(user);
        (fheCurrency0, fheCurrency1) = mintAndApprove2Currencies(address(fheToken0), address(fheToken1));

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
        hook = Counter(flags);

        vm.label(address(hook), "hook");
        vm.label(address(this), "test");

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );

        vm.stopPrank();
    }

    function testCounterHooks() public {
        // positions were created in setup()
        CFT.assertHashValue(hook.beforeAddLiquidityCount(poolId), 1);

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        
        vm.prank(user);
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        CFT.assertHashValue(hook.beforeSwapCount(poolId), 1);
        CFT.assertHashValue(hook.afterSwapCount(poolId), 1);
    }

    function testLiquidityHooks() public {
        // positions were created in setup()
        CFT.assertHashValue(hook.beforeAddLiquidityCount(poolId), 1);
        //CFT.assertHashValue(hook.beforeRemoveLiquidityCount(poolId), 0);

        // remove liquidity
        uint256 liquidityToRemove = 1e18;
        posm.decreaseLiquidity(
            tokenId,
            liquidityToRemove,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );

        CFT.assertHashValue(hook.beforeAddLiquidityCount(poolId), 1);
        CFT.assertHashValue(hook.beforeRemoveLiquidityCount(poolId), 1);
    }

    //
    //      ... Helper Functions ...
    //
    function mintAndApprove2Currencies(address tokenA, address tokenB) internal returns (Currency, Currency) {
        Currency _currencyA = mintAndApproveCurrency(tokenA);
        Currency _currencyB = mintAndApproveCurrency(tokenB);

        (currency0, currency1) =
            SortTokens.sort(Currency.unwrap(_currencyA),Currency.unwrap(_currencyB));
        return (currency0, currency1);
    }

    function mintAndApproveCurrency(address token) internal returns (Currency currency) {
        IFHERC20(token).mint(user, 2 ** 250);
        IFHERC20(token).mint(address(this), 2 ** 250);

        //InEuint128 memory amount = CFT.createInEuint128(2 ** 120, address(this));
        InEuint128 memory amountUser = CFT.createInEuint128(2 ** 120, user);

        //IFHERC20(token).mintEncrypted(address(this), amount);
        IFHERC20(token).mintEncrypted(user, amountUser);

        address[9] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor()),
            address(actionsRouter)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            IFHERC20(token).approve(toApprove[i], Constants.MAX_UINT256);
        }

        return Currency.wrap(token);
    }
}
