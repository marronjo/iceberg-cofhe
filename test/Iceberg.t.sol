// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//Foundry Imports
import "forge-std/Test.sol";

//Uniswap Imports
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Iceberg} from "../src/Iceberg.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SortTokens} from "./utils/SortTokens.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {EpochLibrary, Epoch} from "../src/lib/EpochLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

import {Queue} from "../src/Queue.sol";

//FHE Imports
import {FHE, euint128, euint128, euint32, ebool, InEuint128, InEuint32, InEbool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {IFHERC20} from "../src/interface/IFHERC20.sol";
import {HybridFHERC20} from "../src/HybridFHERC20.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-foundry-mocks/CoFheTest.sol";

contract IcebergTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    //test instance with useful utilities for testing FHE contracts locally
    CoFheTest CFT;

    address private user = makeAddr("user");

    Iceberg hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    Currency fheCurrency0;
    Currency fheCurrency1;

    HybridFHERC20 fheToken0;
    HybridFHERC20 fheToken1;

    uint160 constant SQRT_RATIO_10_1 = 250541448375047931186413801569;

    function setUp() public {
        //initialise new CoFheTest instance with logging turned on
        CFT = new CoFheTest(true);

        fheToken0 = new HybridFHERC20("TOKEN0", "TOK0");
        fheToken1 = new HybridFHERC20("TOKEN1", "TOK1");

        vm.label(user, "user");
        vm.label(address(this), "test");
        vm.label(address(fheToken0), "token0");
        vm.label(address(fheToken1), "token1");

        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();

        vm.startPrank(user);
        (fheCurrency0, fheCurrency1) = mintAndApprove2Currencies(address(fheToken0), address(fheToken1));

        deployAndApprovePosm(manager, fheCurrency0, fheCurrency1);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("Iceberg.sol:Iceberg", constructorArgs, flags);
        hook = Iceberg(flags);

        vm.label(address(hook), "hook");

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

    // tick lower should be 0 since pool was initialized with 1-1 SQRT Price
    // e.g. tick price has not moved up or down
    function testTickLowerLast() public view {
        assertEq(hook.getTickLowerLast(key.toId()), 0);
    }

    // init with 10-1 price ratio, 61 tick spacing
    // log_1.0001(10) ≈ 23026.25 -> floor = 23026
    // (23026 / 61) * 61 -> 377 * 61 = 22997
    function testGetTickLowerLastWithDifferentPrice() public {
        PoolKey memory differentKey =
            PoolKey(Currency.wrap(address(fheToken0)), Currency.wrap(address(fheToken1)), 3000, 61, hook);
        manager.initialize(differentKey, SQRT_RATIO_10_1);
        assertEq(hook.getTickLowerLast(differentKey.toId()), 22997);
    }

    function testPlaceIcebergOrderToken0() public {
        euint128 userBalanceBefore0 = fheToken0.encBalances(user);
        euint128 userBalanceBefore1 = fheToken1.encBalances(user);

        int24 lower = 0;
        InEbool memory zeroForOne = CFT.createInEbool(true, user);
        InEuint128 memory liquidity = CFT.createInEuint128(100, user);

        vm.prank(user);
        hook.placeIcebergOrder(key, lower, zeroForOne, liquidity);

        // Check hook balances of token0 & token1
        // since zeroForOne = true
        // user sends hook token0 e.g. swap token0 for token1
        // fheToken0 : user -> hook encrypted 0
        // fheToken1 : user -> hook encrypted 100
        CFT.assertHashValue(fheToken0.encBalances(address(hook)), 100);
        CFT.assertHashValue(fheToken1.encBalances(address(hook)), 0);

        uint256 userBalanceAfter0 = CFT.mockStorage(euint128.unwrap(fheToken0.encBalances(user)));
        uint256 userBalanceAfter1 = CFT.mockStorage(euint128.unwrap(fheToken1.encBalances(user)));

        // token0 balance after should be 100 tokens less than balance before
        CFT.assertHashValue(userBalanceBefore0, uint128(userBalanceAfter0 + 100));
        CFT.assertHashValue(userBalanceBefore1, uint128(userBalanceAfter1));
    }

    function testPlaceIcebergOrderToken1() public {
        euint128 userBalanceBefore0 = fheToken0.encBalances(user);
        euint128 userBalanceBefore1 = fheToken1.encBalances(user);

        int24 lower = 0;
        InEbool memory zeroForOne = CFT.createInEbool(false, user);
        InEuint128 memory liquidity = CFT.createInEuint128(100, user);

        vm.prank(user);
        hook.placeIcebergOrder(key, lower, zeroForOne, liquidity);

        // Check hook balances of token0 & token1
        // since zeroForOne = false
        // user sends hook token1 e.g. swap token1 for token0
        // fheToken0 : user -> hook encrypted 0
        // fheToken1 : user -> hook encrypted 100
        CFT.assertHashValue(fheToken0.encBalances(address(hook)), 0);
        CFT.assertHashValue(fheToken1.encBalances(address(hook)), 100);

        uint256 userBalanceAfter0 = CFT.mockStorage(euint128.unwrap(fheToken0.encBalances(user)));
        uint256 userBalanceAfter1 = CFT.mockStorage(euint128.unwrap(fheToken1.encBalances(user)));

        CFT.assertHashValue(userBalanceBefore0, uint128(userBalanceAfter0));
        // token1 balance after should be 100 tokens less than balance before
        CFT.assertHashValue(userBalanceBefore1, uint128(userBalanceAfter1 + 100));
    }

    function testQueueZeroAfterPlaceIcebergOrder() public {
        int24 lower = 60;
        InEbool memory zeroForOne = CFT.createInEbool(false, user);
        InEuint128 memory liquidity = CFT.createInEuint128(100, user);

        vm.prank(user);
        hook.placeIcebergOrder(key, lower, zeroForOne, liquidity);

        Queue q = hook.poolQueue(keccak256(abi.encode(key)));

        // ensure queue is not initialised yet
        assertEq(address(q), address(0));
    }

    //
    // --------------- Helper Functions ------------------
    //
    function placeIcebergOrder(int24 _lower, bool _zeroForOne, uint128 _liquidity) private returns(ebool, euint128) {
        InEbool memory zeroForOne = CFT.createInEbool(_zeroForOne, user);
        InEuint128 memory liquidity = CFT.createInEuint128(_liquidity, user);

        hook.placeIcebergOrder(key, _lower, zeroForOne, liquidity);

        return(FHE.asEbool(zeroForOne), FHE.asEuint128(liquidity));
    }

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
