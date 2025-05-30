import { task } from 'hardhat/config';
import { cofhejs, Encryptable } from 'cofhejs/node';
import { icebergAddress, poolKey } from './util/constants';
import { initialiseCofheJs } from './util/common';

import icebergAbi from '../artifacts/src/Iceberg.sol/Iceberg.json';

task('get-iceberg-permissions', 'get iceberg hook permissions').setAction(async(taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    const iceberg = new hre.ethers.Contract(icebergAddress, icebergAbi.abi, signer);

    const [ beforeInitialize,
            afterInitialize,
            beforeAddLiquidity,
            beforeRemoveLiquidity,
            afterAddLiquidity,
            afterRemoveLiquidity,
            beforeSwap,
            afterSwap,
            beforeDonate,
            afterDonate,
            beforeSwapReturnDelta,
            afterSwapReturnDelta,
            afterAddLiquidityReturnDelta,
            afterRemoveLiquidityReturnDelta
        ] = await iceberg.getHookPermissions();

    console.log("-- Iceberg Hook Permissions --");
    console.log("beforeInitialize                : " + beforeInitialize);
    console.log("afterInitialize                 : " + afterInitialize);
    console.log("beforeAddLiquidity              : " + beforeAddLiquidity);
    console.log("beforeRemoveLiquidity           : " + beforeRemoveLiquidity);
    console.log("afterAddLiquidity               : " + afterAddLiquidity);
    console.log("afterRemoveLiquidity            : " + afterRemoveLiquidity);
    console.log("beforeSwap                      : " + beforeSwap);
    console.log("afterSwap                       : " + afterSwap);
    console.log("beforeDonate                    : " + beforeDonate);
    console.log("afterDonate                     : " + afterDonate);
    console.log("beforeSwapReturnDelta           : " + beforeSwapReturnDelta);
    console.log("afterSwapReturnDelta            : " + afterSwapReturnDelta);
    console.log("afterAddLiquidityReturnDelta    : " + afterAddLiquidityReturnDelta);
    console.log("afterRemoveLiquidityReturnDelta : " + afterRemoveLiquidityReturnDelta);
});

task('place-iceberg-order', 'place encrypted iceberg order')
.addParam('zeroForOne', 'direction of trade, true for 0->1, false for 1->0 token swap')
.addParam('liquidity', 'size of the iceberg order')
.addParam('tickLower', 'tick price to place order at')
.setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();

    await initialiseCofheJs(signer);
    const iceberg = new hre.ethers.Contract(icebergAddress, icebergAbi.abi, signer);

    const zeroForOneInput: boolean = taskArgs.zeroForOne === 'true';
    const liquidityInput: bigint = BigInt(taskArgs.liquidity);
    const tickLower: number = parseInt(taskArgs.tickLower);

    const encInputs = await cofhejs.encrypt([Encryptable.bool(zeroForOneInput), Encryptable.uint128(liquidityInput)]);

    if(!encInputs.success){
        console.error("Error encrypting inputs", encInputs.error);
        return;
    }
    
    const zeroForOne = encInputs.data[0];
    const liquidity = encInputs.data[1];

    const tx = await iceberg.placeIcebergOrder(poolKey, tickLower, zeroForOne, liquidity);
    await tx.wait();

    console.log("Order placed successfully!");
    console.log("Transaction hash : " + tx.hash);
}); 
