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

        fheToken0.approve(address(swapRouter), type(uint256).max);
        fheToken1.approve(address(swapRouter), type(uint256).max);

        fheToken0.approve(address(manager), type(uint256).max);
        fheToken1.approve(address(manager), type(uint256).max);

        fheToken0.mintEncrypted(address(hook), FHE.asEuint128(0));  //init value in mock storage
        fheToken1.mintEncrypted(address(hook), FHE.asEuint128(0));  //init value in mock storage

        vm.stopPrank();
    }

    function testBeforeSwapHookIcebergOrderFilled() public {

        //-----------------------------------------------
        //                                              
        //          STAGE 1 - Place Iceberg Order
        //          
        //    zeroForOne - true (sell token0 buy token1)  
        //          ticklower - 0 set at middle tick
        //          liquidity - 1000000 quantity
        //                                              
        //-----------------------------------------------

        int24 lower = 0;
        InEbool memory zeroForOne = CFT.createInEbool(true, user);
        InEuint128 memory liquidity = CFT.createInEuint128(1000000, user);

        euint128 userBalanceBeforeToken0 = fheToken0.encBalances(user);
        euint128 userBalanceBeforeToken1 = fheToken1.encBalances(user);

        euint128 hookBalanceBeforeToken0 = fheToken0.encBalances(address(hook));
        euint128 hookBalanceBeforeToken1 = fheToken1.encBalances(address(hook));

        // user places limit order at given tick lower
        vm.prank(user);
        hook.placeIcebergOrder(key, lower, zeroForOne, liquidity);

        euint128 userBalanceAfterToken0 = fheToken0.encBalances(user);
        euint128 userBalanceAfterToken1 = fheToken1.encBalances(user);

        euint128 hookBalanceAfterToken0 = fheToken0.encBalances(address(hook));
        euint128 hookBalanceAfterToken1 = fheToken1.encBalances(address(hook));

        // user balance assertions
        // user should send 1000000 token0
        // token1 balance should be the same as before
        CFT.assertHashValue(userBalanceBeforeToken0, _mockStorageHelper(userBalanceAfterToken0) + 1000000);
        CFT.assertHashValue(userBalanceBeforeToken1, _mockStorageHelper(userBalanceAfterToken1));

        // hook balance assertions
        // hook should receive 1000000 token0
        // token1 balance should be the same as before
        CFT.assertHashValue(hookBalanceBeforeToken0, _mockStorageHelper(hookBalanceAfterToken0) - 1000000);
        CFT.assertHashValue(hookBalanceBeforeToken1, _mockStorageHelper(hookBalanceAfterToken1));

        //-----------------------------------------------
        //                                              
        //            STAGE 2 - Execute swap
        //     zeroForOne - false (opposite to iceberg)
        //    amount - 1e18 large enough to cross 0 tick
        //    price limit - tickPrice @ 60
        //
        //    validate correct order data is stored
        //                                              
        //-----------------------------------------------

        doSwap(false, -1e18, 60);

        Epoch epoch = hook.getEncEpoch(key, lower);

        assertTrue(EpochLibrary.equals(epoch, Epoch.wrap(1)));

        (
            bool fill0,
            ,
            Currency curr0,
            Currency curr1,
            ,,,,
            euint128 zeroForOneTotal,
            euint128 oneForZeroTotal
        ) = hook.encEpochInfos(epoch);

        assertFalse(fill0);
        assertEq(Currency.unwrap(curr0), Currency.unwrap(key.currency0));
        assertEq(Currency.unwrap(curr1), Currency.unwrap(key.currency1));
        CFT.assertHashValue(zeroForOneTotal, 1000000);                              //zeroForOne liquidity should be 1000000 from iceberg order above
        CFT.assertHashValue(oneForZeroTotal, 0);                                    //oneForZero liquidity should be 0
        CFT.assertHashValue(hook.getUserLiquidity(key, user, 0, true), 1000000);    //user total should be 1000000 since no other orders

        //-----------------------------------------------
        //                                              
        //      STAGE 3 - Decryption Queue Validation
        //          
        //      ensure decryption request was sent to
        //      coprocessor and the encrypted value exists
        //              in the decryption queue.  
        //                                              
        //-----------------------------------------------

        Queue queue = hook.poolQueue(keccak256(abi.encode(key)));
        assertFalse(queue.isEmpty());       //ensure order is in the decryption queue

        //look at value at top of queue
        euint128 top = queue.peek();

        CFT.assertHashValue(top, 1000000);

        (
            bool orderZeroForOne,
            int24 orderTickLower,
            address orderToken
        ) = hook.orderInfo(top);

        assertEq(orderZeroForOne, true);
        assertEq(orderTickLower, 0);
        assertEq(orderToken, Currency.unwrap(key.currency0));

        //-----------------------------------------------
        //                                              
        //      STAGE 4 - Simulate Async Decryption
        //          
        //        decryption happens randomly between
        //      1-10 block timestamps in mock environment
        //      warp timestamp by 11 to ensure decrypted
        //                  value is ready
        //                                              
        //-----------------------------------------------
        
        vm.warp(block.timestamp + 11);

        //-----------------------------------------------
        //                                              
        //     STAGE 5 - Test BeforeSwap Order Fill
        //          
        //   the order is now decrypted and waiting to fill.
        //      
        //  execute another swap, so the beforeSwap is called
        //  then the decrypted iceberg order should be filled
        //         before the new swap completes.
        //                                              
        //-----------------------------------------------

        euint128 hookBalanceBeforeFillToken0 = fheToken0.encBalances(address(hook));
        euint128 hookBalanceBeforeFillToken1 = fheToken1.encBalances(address(hook));

        doSwap(true, -1);

        //-----------------------------------------------
        //                                              
        //     STAGE 6 - Validate order filled correctly
        //          
        //       check hook balances before / after
        //          for correct tokens in / out
        //                                              
        //-----------------------------------------------

        euint128 hookBalanceAfterFillToken0 = fheToken0.encBalances(address(hook));
        euint128 hookBalanceAfterFillToken1 = fheToken1.encBalances(address(hook));

        assertEqEuint(hookBalanceBeforeFillToken0, hookBalanceAfterFillToken0, 1000000);
        assertEqEuintNormalise(hookBalanceBeforeFillToken1, int128(1000000), hookBalanceAfterFillToken1, 1000000);

        //-----------------------------------------------
        //                                              
        //     STAGE 7 - Ensure Withdrawal works
        //          
        //      make sure user can withdraw funds
        //  validate balance change of correct tokens
        //                                              
        //-----------------------------------------------

        euint128 userBalanceBeforeWithdrawToken0 = fheToken0.encBalances(user);
        euint128 userBalanceBeforeWithdrawToken1 = fheToken1.encBalances(user);

        euint128 hookBalanceBeforeWithdrawToken0 = fheToken0.encBalances(address(hook));
        euint128 hookBalanceBeforeWithdrawToken1 = fheToken1.encBalances(address(hook));

        vm.prank(user);
        (euint128 amount0, euint128 amount1) = hook.withdraw(key, 0);

        euint128 userBalanceAfterWithdrawToken0 = fheToken0.encBalances(user);
        euint128 userBalanceAfterWithdrawToken1 = fheToken1.encBalances(user);

        euint128 hookBalanceAfterWithdrawToken0 = fheToken0.encBalances(address(hook));
        euint128 hookBalanceAfterWithdrawToken1 = fheToken1.encBalances(address(hook));

        assertEqEuint(userBalanceBeforeWithdrawToken0, userBalanceAfterWithdrawToken0);             //no change
        assertLtEuint(userBalanceBeforeWithdrawToken1, userBalanceAfterWithdrawToken1);             //gain token1

        assertEqEuint(hookBalanceBeforeWithdrawToken0, hookBalanceAfterWithdrawToken0);             //no change
        assertGtEuint(hookBalanceBeforeWithdrawToken1, hookBalanceAfterWithdrawToken1);             //lose token1
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

    function testQueueEmptyAfterSwap() public {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 100,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(user);
        swapRouter.swap(key, params, _defaultTestSettings(), ZERO_BYTES);

        Queue queue = hook.poolQueue(keccak256(abi.encode(key)));

        assertTrue(queue.isEmpty());
    }

    function testExistsAfterPlaceIcebergOrderZeroForOne() public {
        int24 lower = 0;
        InEbool memory zeroForOne = CFT.createInEbool(true, user);
        InEuint128 memory liquidity = CFT.createInEuint128(1000000, user);

        //user places limit order at given tick lower
        vm.prank(user);
        hook.placeIcebergOrder(key, lower, zeroForOne, liquidity);

        //another user swaps large amount in opposite direction
        doSwap(false, -1e18, 60);

        Epoch epoch = hook.getEncEpoch(key, lower);

        assertTrue(EpochLibrary.equals(epoch, Epoch.wrap(1)));

        (
            bool fill0,
            bool fill1,
            Currency curr0,
            Currency curr1,
            ,,,,
            euint128 zeroForOneTotal,
            euint128 oneForZeroTotal
        ) = hook.encEpochInfos(epoch);

        assertFalse(fill0);
        assertFalse(fill1);
        assertEq(Currency.unwrap(curr0), Currency.unwrap(key.currency0));
        assertEq(Currency.unwrap(curr1), Currency.unwrap(key.currency1));
        CFT.assertHashValue(zeroForOneTotal, 1000000);                                     //zeroForOne liquidity should be 1000000 from iceberg order above
        CFT.assertHashValue(oneForZeroTotal, 0);                                           //oneForZero liquidity should be 0
        CFT.assertHashValue(hook.getUserLiquidity(key, user, 0, true), 1000000);           //total should be 1000000 since no other orders

        Queue queue = hook.poolQueue(keccak256(abi.encode(key)));
        assertFalse(queue.isEmpty());

        euint128 top = queue.peek();

        CFT.assertHashValue(top, 1000000);

        (
            bool orderZeroForOne,
            int24 orderTickLower,
            address token
        ) = hook.orderInfo(top);

        assertEq(orderZeroForOne, true);
        assertEq(orderTickLower, 0);
        assertEq(token, Currency.unwrap(key.currency0));
    }

    function testExistsAfterPlaceIcebergOrderOneForZero() public {
        int24 lower = 0;
        InEbool memory zeroForOne = CFT.createInEbool(false, user);
        InEuint128 memory liquidity = CFT.createInEuint128(987654321, user);

        //user places limit order at given tick lower
        vm.prank(user);
        hook.placeIcebergOrder(key, lower, zeroForOne, liquidity);

        //another user swaps large amount in opposite direction
        doSwap(true, 12345678910);

        Epoch epoch = hook.getEncEpoch(key, lower);

        assertTrue(EpochLibrary.equals(epoch, Epoch.wrap(1)));

        (
            ,
            bool fill1,
            Currency curr0,
            Currency curr1,
            ,,,,
            euint128 zeroForOneTotal,
            euint128 oneForZeroTotal
        ) = hook.encEpochInfos(epoch);

        assertFalse(fill1);
        assertEq(Currency.unwrap(curr0), Currency.unwrap(key.currency0));
        assertEq(Currency.unwrap(curr1), Currency.unwrap(key.currency1));
        CFT.assertHashValue(zeroForOneTotal, 0);                  //zeroForOne liquidity should be 0
        CFT.assertHashValue(oneForZeroTotal, 987654321);           //oneForZero liquidity should be 987654321 from iceberg order above
        CFT.assertHashValue(hook.getUserLiquidity(key, user, 0, false), 987654321);         //total should be 987654321 since no other orders

        Queue queue = hook.poolQueue(keccak256(abi.encode(key)));
        assertFalse(queue.isEmpty());

        euint128 top = queue.peek();

        CFT.assertHashValue(top, 987654321);

        (
            bool orderZeroForOne,
            int24 orderTickLower,
            address token
        ) = hook.orderInfo(top);

        assertEq(orderZeroForOne, false);
        assertEq(orderTickLower, 0);
        assertEq(token, Currency.unwrap(key.currency1));
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

    function doSwap(bool zeroForOne, int256 amount, int24 tick) private {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amount,
            sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(tick)
        });

        vm.prank(user);
        swapRouter.swap(key, params, _defaultTestSettings(), ZERO_BYTES);
    }  

    function doSwap(bool zeroForOne, int256 amount) private {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amount,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        vm.prank(user);
        swapRouter.swap(key, params, _defaultTestSettings(), ZERO_BYTES);
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

    function _defaultTestSettings() internal pure returns (PoolSwapTest.TestSettings memory testSetting) {
        return PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false});
    }

    // help with easier to read test assertions
    function _mockStorageHelper(euint128 value) private view returns(uint128){
        return uint128(CFT.mockStorage(euint128.unwrap(value)));
    }

    function _mockStorageHelper(ebool value) private view returns(bool){
        return CFT.mockStorage(ebool.unwrap(value)) == 1 ? true : false;
    }

    // fetch evalues from mock storage and compare plaintext
    function assertEqEuint(euint128 a, euint128 b) private view {
        assertEq(_mockStorageHelper(a), _mockStorageHelper(b));
    }

    // fetch evalues from mock storage and compare plaintext
    // int value can be +/- to allow for add/sub operations
    function assertEqEuint(euint128 a, int128 aOffset, euint128 b) private view {
        int128 aAfterOffset = int128(_mockStorageHelper(a)) + aOffset;  //assume no underflow
        assertEq(uint128(aAfterOffset), _mockStorageHelper(b));
    }

    // fetch evalues from mock storage and compare plaintext
    function assertEqEuint(euint128 a, euint128 b, int128 bOffset) private view {
        int128 bAfterOffset = int128(_mockStorageHelper(b)) + bOffset;  //assume no underflow
        assertEq(_mockStorageHelper(a), uint128(bAfterOffset));
    }

    function assertLtEuint(euint128 a, euint128 b) private view {
        assertTrue(_mockStorageHelper(a) < _mockStorageHelper(b));
    }

    function assertLteEuint(euint128 a, euint128 b) private view {
        assertTrue(_mockStorageHelper(a) <= _mockStorageHelper(b));
    }

    function assertGtEuint(euint128 a, euint128 b) private view {
        assertTrue(_mockStorageHelper(a) > _mockStorageHelper(b));
    }

    function assertGteEuint(euint128 a, euint128 b) private view {
        assertTrue(_mockStorageHelper(a) >= _mockStorageHelper(b));
    }

    // fetch evalues from mock storage and compare plaintext with normalise
    function assertEqEuintNormalise(euint128 a, uint128 aAmount, euint128 b) private view {
        assertEq((_mockStorageHelper(a) / aAmount) * aAmount, _mockStorageHelper(b));
    }

    // fetch evalues from mock storage and compare plaintext with normalise
    function assertEqEuintNormalise(euint128 a, euint128 b, uint128 bAmount) private view {
        assertEq(_mockStorageHelper(a), (_mockStorageHelper(b) / bAmount) * bAmount);
    }

    // fetch evalues from mock storage and compare plaintext with normalise
    function assertEqEuintNormalise(euint128 a, uint128 aAmount, euint128 b, int128 bOffset) private view {
        int128 bAfterOffset = int128(_mockStorageHelper(b)) + bOffset;  //assume no underflow
        assertEq((_mockStorageHelper(a) / aAmount) * aAmount, uint128(bAfterOffset));
    }

    // fetch evalues from mock storage and compare plaintext with normalise
    function assertEqEuintNormalise(euint128 a, int128 aOffset, euint128 b, uint128 bAmount) private view {
        int128 aAfterOffset = int128(_mockStorageHelper(a)) + aOffset;  //assume no underflow
        assertEq(uint128(aAfterOffset), (_mockStorageHelper(b) / bAmount) * bAmount);
    }
}
