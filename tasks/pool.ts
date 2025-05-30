import { task } from 'hardhat/config';
import { BigNumber } from 'bignumber.js';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { poolId, stateView, stateViewIface } from './util/constants';

const decimalPrecision = 18;

task('get-exchange-rate', 'Fetch current exchange rate from Uniswap v4 pool').setAction(async (taskArgs, hre) => {
  const contract = await getStateViewContract(hre);
  const [sqrtPricex96, , , ] = await contract.getSlot0(poolId);
  logExchangeRate(sqrtPricex96.toString());
});

task('get-pool-state', 'Fetch current state of Uniswap v4 pool').setAction(async (taskArgs, hre) => {
  const contract = await getStateViewContract(hre);
  const [sqrtPricex96, tick, protocolFee, lpFee] = await contract.getSlot0(poolId);
  logPoolState(sqrtPricex96, tick, protocolFee, lpFee);
});

const getStateViewContract = async (hre: HardhatRuntimeEnvironment) => {
  const stateViewInterface = new hre.ethers.Interface([
    stateViewIface
  ]);
  const [signer] = await hre.ethers.getSigners();
  return new hre.ethers.Contract(stateView, stateViewInterface, signer);
}

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
