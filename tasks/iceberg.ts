import { task } from 'hardhat/config';
import { cofhejs, Encryptable } from 'cofhejs/node';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { PoolKeyStruct } from '../typechain-types/src/Iceberg';

const icebergSepolia = '0x4402948CD6fe4fb6070DEA39B7AB9b25e5CB90C0';
import icebergAbi from '../artifacts/src/Iceberg.sol/Iceberg.json';

const poolKey: PoolKeyStruct = {
    currency0 : "0x0eC274fFB635b534086716855BAc795b841BD490",
    currency1 : "0xaAA70eC4269B182fa49Cec06C9617aa38b12A647",
    fee : 3000,
    tickSpacing : 60,
    hooks: icebergSepolia
}

task('get-iceberg-permissions', 'get iceberg hook permissions').setAction(async(taskArgs, hre) => {
    const iceberg = await getIcebergContract(hre);    

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
.addParam("zeroForOne", "direction of trade, true for 0->1, false for 1->0 token swap")
.addParam("liquidity", "size of the iceberg order")
.addParam("tickLower", "tick price to place order at")
.setAction(async (taskArgs, hre) => {
    await initialiseCofheJs(hre);
    const iceberg = await getIcebergContract(hre);

    const zeroForOneInput: boolean = taskArgs.zeroForOne === 'true';
    const liquidityInput: bigint = BigInt(taskArgs.liquidity);
    const tickLower: number = parseInt(taskArgs.tickLower);

    const encInputs = await cofhejs.encrypt([Encryptable.bool(zeroForOneInput), Encryptable.uint128(liquidityInput)]);

    if(!encInputs.success){
        console.log("Error encrypting inputs");
        return;
    }
    
    const zeroForOne = encInputs.data[0];
    const liquidity = encInputs.data[1];

    console.log(zeroForOne);
    console.log(liquidity);

    const tx = await iceberg.placeIcebergOrder(poolKey, tickLower, zeroForOne, liquidity);
    await tx.wait();

    console.log("Order placed successfully!");
    console.log("Transaction hash : " + tx.hash);
}); 

const getIcebergContract = async (hre: HardhatRuntimeEnvironment) => {
    const [signer] = await hre.ethers.getSigners();
    return new hre.ethers.Contract(icebergSepolia, icebergAbi.abi, signer);
}

const initialiseCofheJs = async (hre: HardhatRuntimeEnvironment) => {
    const [signer] = await hre.ethers.getSigners();
    const provider = hre.ethers.provider;

    await cofhejs.initializeWithEthers({
        ethersProvider: provider,
        ethersSigner: signer,
        environment: 'TESTNET'
    });
}
