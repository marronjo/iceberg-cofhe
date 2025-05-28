import { task } from 'hardhat/config';
import { cofhejs, Encryptable } from 'cofhejs/node';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { PoolKeyStruct, Iceberg } from '../typechain-types/src/Iceberg';

const icebergSepolia = '0x4402948CD6fe4fb6070DEA39B7AB9b25e5CB90C0';
import icebergAbi from '../artifacts/src/Iceberg.sol/Iceberg.json';

task('get-iceberg-premissions', 'get iceberg hook permissions').setAction(async(taskArgs, hre) => {
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

task('place-iceberg-order', 'place encrypted iceberg order').setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    const provider = hre.ethers.provider;

    await cofhejs.initializeWithEthers({
        ethersProvider: provider,
        ethersSigner: signer,
        environment: 'TESTNET'
    });

    const iceberg = await getIcebergContract(hre);

    const encInputs = await cofhejs.encrypt([Encryptable.bool(true), Encryptable.uint128(1000n)]);

    if(!encInputs.success || encInputs.data === null){
        console.log("Error encrypting inputs");
        return;
    }
    
    const zeroForOne = encInputs.data[0];
    const liquidity = encInputs.data[1];
    const tickLower = 600;

    const poolKey: PoolKeyStruct = {
        currency0 : "0x0eC274fFB635b534086716855BAc795b841BD490",
        currency1 : "0xaAA70eC4269B182fa49Cec06C9617aa38b12A647",
        fee : 3000,
        tickSpacing : 60,
        hooks: icebergSepolia
    }

    console.log(zeroForOne);
    console.log(liquidity);
    console.log(poolKey);

    const tx = await iceberg.placeIcebergOrder(poolKey, tickLower, zeroForOne, liquidity);
    await tx.wait();
}); 

const getIcebergContract = async (hre: HardhatRuntimeEnvironment) => {
    const [signer] = await hre.ethers.getSigners();
    return new hre.ethers.Contract(icebergSepolia, icebergAbi.abi, signer);
}
