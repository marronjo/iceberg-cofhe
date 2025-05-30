import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { cofhejs } from 'cofhejs/node';

export const initialiseCofheJs = async (signer: HardhatEthersSigner) => {
    await cofhejs.initializeWithEthers({
        ethersProvider: signer.provider,
        ethersSigner: signer,
        environment: 'TESTNET'
    });
}
