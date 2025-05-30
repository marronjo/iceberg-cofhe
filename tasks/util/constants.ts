import { PoolKeyStruct } from "../../typechain-types/src/Iceberg";

// constants for iceberg pool on sepolia
export const token0 = '0x0eA00720cAA3b6A5d18683D09A75E8425934529c';
export const token1 = '0xBA131d183F67dD1B4252487681b598B6bC165D17';

export const icebergAddress = '0x9c5c79E16f1366af6867c61919aCF8E1471290C0';
export const stateView = '0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C';

export const stateViewIface = 'function getSlot0(bytes32 poolId) view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)';

export const poolId = '0x3feaace03479a4b14999b3300f3555b4c275b4263363791788f76677cf834e59';
export const poolKey: PoolKeyStruct = {
    currency0 : token0,
    currency1 : token1,
    fee : 3000,
    tickSpacing : 60,
    hooks: icebergAddress
}
