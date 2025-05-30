import { PoolKeyStruct } from "../../typechain-types/src/Iceberg";

// constants for iceberg pool on sepolia
export const token0 = '0x0eC274fFB635b534086716855BAc795b841BD490';
export const token1 = '0xaAA70eC4269B182fa49Cec06C9617aa38b12A647';

export const icebergAddress = '0x4402948CD6fe4fb6070DEA39B7AB9b25e5CB90C0';
export const stateView = '0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C';

export const stateViewIface = 'function getSlot0(bytes32 poolId) view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)';

export const poolId = '0x9b977b2a33d582e2295f5d8aac6a448b0533c5b65f30bb973f9fc1fbe8f25248';
export const poolKey: PoolKeyStruct = {
    currency0 : token0,
    currency1 : token1,
    fee : 3000,
    tickSpacing : 60,
    hooks: icebergAddress
}
