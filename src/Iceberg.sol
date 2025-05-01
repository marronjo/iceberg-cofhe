// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//Uniswap Imports
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {EpochLibrary, Epoch} from "./lib/EpochLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

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

import {console2} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

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

    bytes internal constant ZERO_BYTES = bytes("");

    euint128 private ZERO = FHE.asEuint128(0);

    Epoch private constant EPOCH_DEFAULT = Epoch.wrap(0);

    mapping(bytes32 tokenId => euint128 amount) claimableTokens;
    mapping(bytes32 tokenId => ebool zeroForOne) redeemOutput;

    mapping(PoolId => int24) public tickLowerLasts;
    Epoch public epochNext = Epoch.wrap(1);

    // bundle encrypted zeroForOne data into single struct
    // zeroForOne must be decrypted to be used as a key
    struct EncEpochInfo {
        ebool filled;
        Currency currency0;
        Currency currency1;
        euint128 liquidityZeroForOne;
        euint128 liquidityOneForZero;
        mapping(address => euint128) liquidityMapZeroForOne;
        mapping(address => euint128) liquidityMapOneForZero;
    }

    //TODO Decrypted Epoch

    struct DecryptedOrder {
        bool zeroForOne;
        int24 tickLower;
        address token;
    }

    //used to find order details based on encrypted handle from decryption queue
    mapping(euint128 liquidityHandle => DecryptedOrder) orderInfo;

    // each pool has separate decrpytion queue for encrypted orders
    mapping(bytes32 key => Queue queue) public poolQueue;

    mapping(bytes32 key => mapping(int24 tickLower => Epoch)) public epochs;
    mapping(Epoch => EncEpochInfo) public encEpochInfos;

    mapping(bytes32 tokenId => euint128 totalSupply) public totalSupply;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

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

    function _getTokenFromPoolKey(PoolKey calldata poolKey, bool zeroForOne) private pure returns(address token){
        token = zeroForOne ? Currency.unwrap(poolKey.currency0) : Currency.unwrap(poolKey.currency1);
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
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) internal override onlyByManager returns (bytes4, BeforeSwapDelta, uint24) {
        
        Queue queue = getPoolQueue(key);

        //if nothing in decryption queue, continue
        //otherwise try execute trade
        if(!queue.isEmpty()){

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

            //TODO add values to decrypted Epoch  

            uint128 amount0;
            uint128 amount1;

            if(order.zeroForOne){
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

                //IFHERC20(Currency.unwrap(key.currency1)).wrap(amount1); //encrypted wrap newly received (taken) token1
            } else {
                key.currency1.settle(poolManager, address(this), uint256(amount1), false);
                key.currency0.take(poolManager, address(this), uint256(amount0), false);

                //IFHERC20(Currency.unwrap(key.currency0)).wrap(amount0); //encrypted wrap newly received (taken) token0
            }
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);   //TODO edit beforeSwapDelta to reflect swap
    }


    function placeIcebergOrder(PoolKey calldata key, int24 tickLower, InEbool calldata zeroForOne, InEuint128 calldata liquidity)
        external
        //onlyValidPools(key.hooks)
    {
        euint128 _liquidity = FHE.asEuint128(liquidity);

        //FHE Require, liquidity must be > 0
        //FHE.req(FHE.gt(_liquidity, FHE.asEuint128(0)));

        ebool _zeroForOne = FHE.asEbool(zeroForOne);

        //generate unique tokenId based on inputs
        //bytes32 tokenId = getTokenId(key, _tickLower, _zeroForOne);

        //mint FHERC6909 tokens to user as receipt of order
        //with calculated tokenId and encrypted amount
        //TODO _mintEnc(msg.sender, tokenId, _liquidity);
        //totalSupply[tokenId] = FHE.add(totalSupply[tokenId], _liquidity);

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

        unchecked {
            epochInfo.liquidityZeroForOne = FHE.select(_zeroForOne, FHE.add(epochInfo.liquidityZeroForOne, _liquidity), epochInfo.liquidityZeroForOne);
            epochInfo.liquidityOneForZero = FHE.select(_zeroForOne, epochInfo.liquidityOneForZero, FHE.add(epochInfo.liquidityOneForZero, _liquidity));

            epochInfo.liquidityMapZeroForOne[msg.sender] = FHE.select(_zeroForOne, FHE.add(epochInfo.liquidityMapZeroForOne[msg.sender], _liquidity), epochInfo.liquidityMapZeroForOne[msg.sender]);
            epochInfo.liquidityMapOneForZero[msg.sender] = FHE.select(_zeroForOne, epochInfo.liquidityMapOneForZero[msg.sender], FHE.add(epochInfo.liquidityMapOneForZero[msg.sender], _liquidity));
        }

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
        IPoolManager.SwapParams calldata params,
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
            euint128 liquidityTotal = FHE.select(_zeroForOne, encEpoch.liquidityZeroForOne, encEpoch.liquidityOneForZero);

            //request unwrap of order amount from coprocessor
            address token = zeroForOne ? address(Currency.unwrap(key.currency0)) : address(Currency.unwrap(key.currency1));
            IFHERC20(token).requestUnwrap(address(this), liquidityTotal);

            //add order key to decryption queue
            //to be queried in beforeSwap hook before next swap takes place
            Queue queue = getPoolQueue(key);
            queue.push(liquidityTotal);

            //add order details to mapping
            //used to query in beforeSwap hook
            orderInfo[liquidityTotal] = DecryptedOrder(zeroForOne, lower, token);

            //continue
        }
    }

    function _swapPoolManager(PoolKey calldata key, bool zeroForOne, int256 amountSpecified) private returns(BalanceDelta delta) {
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
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

    function getTokenId(PoolKey calldata key, uint32 tickLower, bool zeroForOne) private pure returns(bytes32) {
        return keccak256(abi.encodePacked(key.toId(), tickLower, zeroForOne));
    }
}
