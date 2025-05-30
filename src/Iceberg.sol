// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//Uniswap Imports
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {EpochLibrary, Epoch} from "./lib/EpochLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

//Fhenix Imports
import { 
    FHE,
    InEuint128,
    euint128,
    InEuint32,
    euint32,
    InEbool,
    ebool
    } from "@fhenixprotocol/cofhe-contracts/FHE.sol";

import {IFHERC20} from "./interface/IFHERC20.sol";
import {Queue} from "./Queue.sol";

contract Iceberg is BaseHook {

    error NotManager();
    error ZeroLiquidity();
    error InRange();
    error CrossedRange();
    error Filled();
    error NotFilled();
    error NotPoolManagerToken();

    modifier onlyByManager() {
        if (msg.sender != address(poolManager)) revert NotManager();
        _;
    }

    using PoolIdLibrary for PoolKey;
    using EpochLibrary for Epoch;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using StateLibrary for IPoolManager;
    using FHE for uint256;

    bytes internal constant ZERO_BYTES = bytes("");

    euint128 private ZERO = FHE.asEuint128(0);
    euint128 private ONE = FHE.asEuint128(1);

    Epoch private constant EPOCH_DEFAULT = Epoch.wrap(0);

    mapping(bytes32 tokenId => euint128 amount) claimableTokens;
    mapping(bytes32 tokenId => ebool zeroForOne) redeemOutput;

    mapping(PoolId => int24) public tickLowerLasts;
    Epoch public epochNext = Epoch.wrap(1);

    // bundle encrypted zeroForOne data into single struct
    // zeroForOne must be decrypted to be used as a key
    // hence why so many fields in single struct
    struct EncEpochInfo {
        bool zeroForOnefilled;
        bool oneForZerofilled;
        Currency currency0;
        Currency currency1;
        euint128 zeroForOneToken0;
        euint128 zeroForOneToken1;
        euint128 oneForZeroToken0;
        euint128 oneForZeroToken1;
        euint128 zeroForOneLiquidity;
        euint128 oneForZeroLiquidity;
        //mappings used to keep track / cancel user orders
        mapping(address => euint128) liquidityMapToken0;
        mapping(address => euint128) liquidityMapToken1;
    }

    struct DecryptedOrder {
        bool zeroForOne;
        int24 tickLower;
        address token;
    }

    //used to find order details based on encrypted handle from decryption queue
    mapping(euint128 liquidityHandle => DecryptedOrder) public orderInfo;

    // each pool has separate decrpytion queue for encrypted orders
    mapping(bytes32 key => Queue queue) public poolQueue;

    mapping(bytes32 key => mapping(int24 tickLower => Epoch)) public epochs;
    mapping(Epoch => EncEpochInfo) public encEpochInfos;

    mapping(bytes32 tokenId => euint128 totalSupply) public totalSupply;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        FHE.allowThis(ZERO);
        FHE.allowThis(ONE);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
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

    function getTickLowerLast(PoolId poolId) public view returns (int24) {
        return tickLowerLasts[poolId];
    }

    function setTickLowerLast(PoolId poolId, int24 tickLower) private {
        tickLowerLasts[poolId] = tickLower;
    }

    function getEncEpoch(PoolKey memory key, int24 tickLower) public view returns (Epoch) {
        return epochs[keccak256(abi.encode(key))][tickLower];
    }

    function setEncEpoch(PoolKey memory key, int24 tickLower, Epoch epoch) private {
        epochs[keccak256(abi.encode(key))][tickLower] = epoch;
    }

    function getTick(PoolId poolId) private view returns (int24 tick) {
        (, tick,,) = poolManager.getSlot0(poolId);
    }

    function getTickLower(int24 tick, int24 tickSpacing) private pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--;
        return compressed * tickSpacing;
    }

    function getUserLiquidity(PoolKey calldata key, address user, int24 tickLower, bool zeroForOne) public view returns(euint128) {
        Epoch e = getEncEpoch(key, tickLower);
        EncEpochInfo storage encEpochInfo = encEpochInfos[e];
        return zeroForOne ? encEpochInfo.liquidityMapToken0[user] : encEpochInfo.liquidityMapToken1[user];
    }

    //if queue does not exist for given pool, deploy new queue
    function getPoolQueue(PoolKey calldata key) private returns(Queue queue){
        bytes32 poolKey = keccak256(abi.encode(key));
        queue = poolQueue[poolKey];
        if(address(queue) == address(0)){
            queue = new Queue();
            poolQueue[poolKey] = queue;
        }
    }

    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick)
        internal
        override
        onlyByManager
        returns (bytes4)
    {
        setTickLowerLast(key.toId(), getTickLower(tick, key.tickSpacing));
        return BaseHook.afterInitialize.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override onlyByManager returns (bytes4, BeforeSwapDelta, uint24) {
        
        Queue queue = getPoolQueue(key);

        //if nothing in decryption queue, continue
        //otherwise try execute trades
        while(!queue.isEmpty()){

            euint128 liquidityHandle = queue.peek();

            DecryptedOrder memory order = orderInfo[liquidityHandle];

            (uint128 decryptedLiquidity, bool decrypted) = IFHERC20(order.token).getUnwrapResultSafe(address(this), liquidityHandle);
            if(!decrypted){
                return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
            }
            
            //value is decrypted
            //pop from queue since it is no longer needed
            queue.pop();

            BalanceDelta delta = _swapPoolManager(key, order.zeroForOne, -int256(uint256(decryptedLiquidity))); 

            (uint128 amount0, uint128 amount1) = _settlePoolManagerBalances(key, delta, order.zeroForOne);

            _storeSwapOutputs(key, order, amount0, amount1);
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);   //TODO edit beforeSwapDelta to reflect swap
    }

    function _settlePoolManagerBalances(PoolKey calldata key, BalanceDelta delta, bool zeroForOne) private returns(uint128 amount0, uint128 amount1) {
        if(zeroForOne){
            amount0 = uint128(-delta.amount0()); // hook sends in -amount0 and receives +amount1
            amount1 = uint128(delta.amount1());
        } else {
            amount0 = uint128(delta.amount0()); // hook sends in -amount1 and receives +amount0
            amount1 = uint128(-delta.amount1());
        }

        // settle with pool manager the unencrypted FHERC20 tokens
        // send in tokens owed to pool and take tokens owed to the hook
        if (delta.amount0() < 0) {
            key.currency0.settle(poolManager, address(this), uint256(amount0), false);
            key.currency1.take(poolManager, address(this), uint256(amount1), false);

            IFHERC20(Currency.unwrap(key.currency1)).wrap(address(this), amount1); //encrypted wrap newly received (taken) token1
        } else {
            key.currency1.settle(poolManager, address(this), uint256(amount1), false);
            key.currency0.take(poolManager, address(this), uint256(amount0), false);

            IFHERC20(Currency.unwrap(key.currency0)).wrap(address(this), amount0); //encrypted wrap newly received (taken) token0
        }
    }

    function _storeSwapOutputs(PoolKey calldata key, DecryptedOrder memory order, uint128 amount0, uint128 amount1) private {
        Epoch epoch = getEncEpoch(key, order.tickLower);
        EncEpochInfo storage epochInfo = encEpochInfos[epoch];

        if(order.zeroForOne){
            epochInfo.zeroForOnefilled = true;
            epochInfo.zeroForOneToken0 = FHE.add(epochInfo.zeroForOneToken0, FHE.asEuint128(amount0));
            epochInfo.zeroForOneToken1 = FHE.add(epochInfo.zeroForOneToken1, FHE.asEuint128(amount1));
        } else {
            epochInfo.oneForZerofilled = true;
            epochInfo.oneForZeroToken0 = FHE.add(epochInfo.oneForZeroToken0, FHE.asEuint128(amount0));
            epochInfo.oneForZeroToken1 = FHE.add(epochInfo.oneForZeroToken1, FHE.asEuint128(amount1));
        }

        //add hook allowances
        FHE.allowThis(epochInfo.zeroForOneToken0);
        FHE.allowThis(epochInfo.zeroForOneToken1);
    }

    function placeIcebergOrder(PoolKey calldata key, int24 tickLower, InEbool calldata zeroForOne, InEuint128 calldata liquidity)
        external
    {
        euint128 _liquidity = FHE.asEuint128(liquidity);
        ebool _zeroForOne = FHE.asEbool(zeroForOne);

        EncEpochInfo storage epochInfo;
        Epoch epoch = getEncEpoch(key, tickLower);

        if (epoch.equals(EPOCH_DEFAULT)) {
            unchecked {
                setEncEpoch(key, tickLower, epoch = epochNext);
                epochNext = epoch.unsafeIncrement();
            }
            epochInfo = encEpochInfos[epoch];
            epochInfo.currency0 = key.currency0;
            epochInfo.currency1 = key.currency1;
        } else {
            epochInfo = encEpochInfos[epoch];
        }

        epochInfo.liquidityMapToken0[msg.sender] = FHE.select(_zeroForOne, FHE.add(epochInfo.liquidityMapToken0[msg.sender], _liquidity), epochInfo.liquidityMapToken0[msg.sender]);
        epochInfo.liquidityMapToken1[msg.sender] = FHE.select(_zeroForOne, epochInfo.liquidityMapToken1[msg.sender], FHE.add(epochInfo.liquidityMapToken1[msg.sender], _liquidity));

        epochInfo.zeroForOneLiquidity = FHE.select(_zeroForOne, FHE.add(epochInfo.zeroForOneLiquidity, _liquidity), epochInfo.zeroForOneLiquidity);
        epochInfo.oneForZeroLiquidity = FHE.select(_zeroForOne, epochInfo.oneForZeroLiquidity, FHE.add(epochInfo.oneForZeroLiquidity, _liquidity));

        //add allowances for hook
        FHE.allowThis(epochInfo.liquidityMapToken0[msg.sender]);
        FHE.allowThis(epochInfo.liquidityMapToken1[msg.sender]);
        FHE.allowThis(epochInfo.zeroForOneLiquidity);
        FHE.allowThis(epochInfo.oneForZeroLiquidity);

        euint128 token0Amount = FHE.select(_zeroForOne, _liquidity, ZERO);
        euint128 token1Amount = FHE.select(_zeroForOne, ZERO, _liquidity);

        FHE.allow(token0Amount, Currency.unwrap(key.currency0));
        FHE.allow(token1Amount, Currency.unwrap(key.currency1));

        // send both tokens, one amount is encrypted zero to obscure trade direction
        IFHERC20(Currency.unwrap(key.currency0)).transferFromEncrypted(msg.sender, address(this), token0Amount);
        IFHERC20(Currency.unwrap(key.currency1)).transferFromEncrypted(msg.sender, address(this), token1Amount);
    }

    // after swap happens, price will change
    // check if any encrypted orders can be filled
    //
    // if yes ...
    //
    // 1. request decrpytion from FHE coprocessor FHE.decrypt(evalue)
    // 2. add value to decryption queue to be queried later queue.push(evalue)
    // 3. continue with swap lifecycle e.g. return back to pool manager
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) internal override onlyByManager returns (bytes4, int128) {
        (int24 tickLower, int24 lower, int24 upper) = _getCrossedTicks(key.toId(), key.tickSpacing);
        if (lower > upper) return (BaseHook.afterSwap.selector, 0);

        // note that a zeroForOne swap means that the pool is actually gaining token0, so limit
        // order fills are the opposite of swap fills, hence the inversion below
        bool zeroForOne = !params.zeroForOne;

        for (; lower <= upper; lower += key.tickSpacing) {
            _decryptEpoch(key, lower, zeroForOne);
        }

        setTickLowerLast(key.toId(), tickLower);
        return (BaseHook.afterSwap.selector, 0);
    }

    function _decryptEpoch(PoolKey calldata key, int24 lower, bool zeroForOne) internal {
        Epoch epoch = getEncEpoch(key, lower);
        EncEpochInfo storage encEpoch = encEpochInfos[epoch];

        ebool _zeroForOne = FHE.asEbool(zeroForOne);

        // if order exists at current price level e.g. epoch exists
        if (!epoch.equals(EPOCH_DEFAULT)) {
            euint128 liquidityTotal = FHE.select(_zeroForOne, encEpoch.zeroForOneLiquidity, encEpoch.oneForZeroLiquidity);

            //request unwrap of order amount from coprocessor
            address token = zeroForOne ? address(Currency.unwrap(key.currency0)) : address(Currency.unwrap(key.currency1));

            FHE.allow(liquidityTotal, token);
            euint128 liquidityHandle = IFHERC20(token).requestUnwrap(address(this), liquidityTotal);

            FHE.allowThis(liquidityHandle);

            //add order key to decryption queue
            //to be queried in beforeSwap hook before next swap takes place
            Queue queue = getPoolQueue(key);
            queue.push(liquidityHandle);

            //add order details to mapping
            //used to query in beforeSwap hook
            orderInfo[liquidityHandle] = DecryptedOrder(zeroForOne, lower, token);
        }
    }

    function withdraw(PoolKey calldata key, int24 tickLower) external returns(euint128, euint128) {
        Epoch epoch = getEncEpoch(key, tickLower);
        EncEpochInfo storage epochInfo = encEpochInfos[epoch];

        // if (!epochInfo.filled) revert NotFilled(); withdraw encrypted 0 instead of revert

        euint128 liquidityZero = epochInfo.liquidityMapToken0[msg.sender];
        euint128 liquidityOne = epochInfo.liquidityMapToken1[msg.sender];
        
        ebool zeroForOne = liquidityZero.gte(liquidityOne);

        // delete epochInfo.liquidityMapToken0[msg.sender];
        // delete epochInfo.liquidityMapToken1[msg.sender];

        euint128 liquidityTotal0 = epochInfo.zeroForOneLiquidity;
        euint128 liquidityTotal1 = epochInfo.oneForZeroLiquidity;

        euint128 amount0 = FHE.select(zeroForOne, ZERO, _safeMulDiv(epochInfo.oneForZeroToken0, liquidityOne, liquidityTotal1));
        euint128 amount1 = FHE.select(zeroForOne, _safeMulDiv(epochInfo.zeroForOneToken1, liquidityZero, liquidityTotal0), ZERO);

        epochInfo.oneForZeroToken0 = epochInfo.oneForZeroToken0.sub(amount0);
        epochInfo.zeroForOneToken1 = epochInfo.zeroForOneToken1.sub(amount1);
    
        epochInfo.zeroForOneLiquidity = epochInfo.zeroForOneLiquidity.sub(liquidityZero);
        epochInfo.oneForZeroLiquidity = epochInfo.oneForZeroLiquidity.sub(liquidityOne);

        FHE.allow(amount0, Currency.unwrap(key.currency0));
        FHE.allow(amount1, Currency.unwrap(key.currency1));

        IFHERC20(Currency.unwrap(key.currency0)).transferFromEncrypted(address(this), msg.sender, amount0);
        IFHERC20(Currency.unwrap(key.currency1)).transferFromEncrypted(address(this), msg.sender, amount1);

        return(amount0, amount1);
    }

    function _safeMulDiv(euint128 a, euint128 b, euint128 c) private returns(euint128) {
        euint128 divisor = FHE.select(c.eq(ZERO), ONE, c);  //avoid divide by 0 errors
        return FHE.div(FHE.mul(a, b), divisor);
    }

    function _swapPoolManager(PoolKey calldata key, bool zeroForOne, int256 amountSpecified) private returns(BalanceDelta delta) {
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? 
                        TickMath.MIN_SQRT_PRICE + 1 :   // increasing price of token 1, lower ratio
                        TickMath.MAX_SQRT_PRICE - 1
        });

        delta = poolManager.swap(key, params, ZERO_BYTES);
    }

    function _getCrossedTicks(PoolId poolId, int24 tickSpacing)
        internal
        view
        returns (int24 tickLower, int24 lower, int24 upper)
    {
        tickLower = getTickLower(getTick(poolId), tickSpacing);
        int24 tickLowerLast = getTickLowerLast(poolId);

        if (tickLower < tickLowerLast) {
            lower = tickLower + tickSpacing;
            upper = tickLowerLast;
        } else {
            lower = tickLowerLast;
            upper = tickLower - tickSpacing;
        }
    }
}
