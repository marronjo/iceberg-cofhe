import { task } from 'hardhat/config';
import { BigNumber } from 'bignumber.js';

const sepoliaStateView = "0xE1Dd9c3fA50EDB962E442f60DfBc432e24537E4C";
const poolKey = "0x9b977b2a33d582e2295f5d8aac6a448b0533c5b65f30bb973f9fc1fbe8f25248";
const decimalPrecision = 18;

task('get-exchange-rate', 'Fetch current exchange rate from Uniswap v4 pool').setAction(async (taskArgs, hre) => {

  const stateViewInterface = new hre.ethers.Interface([
    "function getSlot0(bytes32 poolId) view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)"    
  ]);

  const [signer] = await hre.ethers.getSigners();
  const contract = new hre.ethers.Contract(sepoliaStateView, stateViewInterface, signer);

  const [sqrtPricex96, tick, protocolFee, lpFee] = await contract.getSlot0(poolKey);

  logPoolState(sqrtPricex96, tick, protocolFee, lpFee);
  logExchangeRate(sqrtPricex96.toString());
});

const logPoolState = (sqrtPriceX96: string, tick: string, protocolFee: string, lpFee: string) => {
  console.log("");
  console.log("---- Current Pool State ----")
  console.log("sqrtPriceX96 : " + sqrtPriceX96);
  console.log("tick         : " + tick);
  console.log("protocolFee  : " + protocolFee);
  console.log("lpFee        : " + lpFee);
  console.log("");
}

const logExchangeRate = (sqrtPriceResult: string) => {
  const sqrtPriceX96 = new BigNumber(sqrtPriceResult);

  const priceRatio = sqrtPriceX96.dividedBy(new BigNumber(2).pow(96)).pow(2);
  const decimalFactor = new BigNumber(10).pow(decimalPrecision).dividedBy(new BigNumber(10).pow(decimalPrecision));

  const buyOneOfToken0 = priceRatio.dividedBy(decimalFactor);
  const buyOneOfToken1 = new BigNumber(1).dividedBy(buyOneOfToken0);

  console.log("price of token0 in value of token1 : " + buyOneOfToken0.toFixed(decimalPrecision));
  console.log("price of token1 in value of token0 : " + buyOneOfToken1.toFixed(decimalPrecision));
  console.log("");

  // Convert to smallest unit (wei-like)
  const buyOneOfToken0Wei = buyOneOfToken0.multipliedBy(new BigNumber(10).pow(decimalPrecision)).integerValue(BigNumber.ROUND_DOWN).toFixed(0);
  const buyOneOfToken1Wei = buyOneOfToken1.multipliedBy(new BigNumber(10).pow(decimalPrecision)).integerValue(BigNumber.ROUND_DOWN).toFixed(0);

  console.log("price of token0 in value of token1 in lowest decimal : " + buyOneOfToken0Wei);
  console.log("price of token1 in value of token0 in lowest decimal : " + buyOneOfToken1Wei);
  console.log("");
}

// Current output, verified against Uniswap Interface exchange rates
//
// price of token0 in value of token1 : 1.061186745504384975
// price of token1 in value of token0 : 0.942341208308908205

// price of token0 in value of token1 in lowest decimal : 1061186745504384975
// price of token1 in value of token0 in lowest decimal : 942341208308908205
