import { task } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import tokenAbi from '../artifacts/src/HybridFHERC20.sol/HybridFHERC20.json';
import { token0, token1 } from './util/constants';
import { Encryptable, FheTypes, cofhejs } from 'cofhejs/node';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';

task('get-token-balances', 'get user token balances').setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    await initialiseCofheJs(signer);

    const [token0Contract, token1Contract] = await getTokenContracts(signer, hre);

    const userEncBalance0 = await token0Contract.encBalances(signer.address);
    const userEncBalance1 = await token1Contract.encBalances(signer.address);

    const userBalance0 = await token0Contract.balanceOf(signer.address);
    const userBalance1 = await token1Contract.balanceOf(signer.address);

    const output0 = await cofhejs.unseal(userEncBalance0, FheTypes.Uint128);
    const output1 = await cofhejs.unseal(userEncBalance1, FheTypes.Uint128);

    console.log('user token0 public balance : ' + userBalance0);
    console.log('user token1 public balance : ' + userBalance1);

    console.log('');

    console.log('user token0 encrypted balance : ' + output0.data);
    console.log('user token1 encrypted balance : ' + output1.data);
});

task('mint-encrypted', 'mint encrypted tokens to user').setAction(async (taskArgs, hre) => {
    const [signer] = await hre.ethers.getSigners();
    await initialiseCofheJs(signer);

    const [token0Contract, token1Contract] = await getTokenContracts(signer, hre);

    const amount = await cofhejs.encrypt([Encryptable.uint128(1000n)]);

    if(!amount.success || amount.data === null){
        console.error(amount.error);
        return;
    }

    console.log(amount);

    await token0Contract.mintEncrypted(signer.address, amount.data[0].ctHash);
    await token1Contract.mintEncrypted(signer.address, amount.data[0].ctHash);

    console.log('Great Success');
});

const getTokenContracts = async (signer: HardhatEthersSigner, hre: HardhatRuntimeEnvironment) => {
    return [new hre.ethers.Contract(token0, tokenAbi.abi, signer),
        new hre.ethers.Contract(token1, tokenAbi.abi, signer)];
}

const initialiseCofheJs = async (signer: HardhatEthersSigner) => {
    await cofhejs.initializeWithEthers({
        ethersProvider: signer.provider,
        ethersSigner: signer,
        environment: 'TESTNET'
    });
}
