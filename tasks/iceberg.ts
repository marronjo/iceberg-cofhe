import { task } from 'hardhat/config';

const icebergSepolia = '0x4402948CD6fe4fb6070DEA39B7AB9b25e5CB90C0';
import icebergAbi from '../out/Iceberg.sol/Iceberg.json';

task('get-iceberg-premissions', 'get iceberg hook permissions').setAction(async(taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();

    const iceberg = new hre.ethers.Contract(icebergSepolia, icebergAbi.abi, signer);

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

    console.log('under maintenance');

    // const [signer] = await hre.ethers.getSigners();
    // const provider = hre.ethers.provider;

    // TODO : fix cofhejs init error
    // cofhejs.initializeWithEthers({
    //     ethersProvider: provider,
    //     ethersSigner: signer,
    //     environment: 'TESTNET'
    // });

    // await cofhejs.createPermit();

    // const zeroForOne = await cofhejs.encrypt([Encryptable.bool(true)]);
});
