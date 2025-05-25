import { task } from 'hardhat/config';
import { BigNumber } from 'bignumber.js';

task('get-exchange-rate', 'Fetch current exchange rate from Uniswap v4 pool').setAction(async (taskArgs, hre) => {
    //TODO: read sqrtPriceX96 from stateview contract getSlot0() method
	const sqrtPriceX96 = new BigNumber("81616034954994713222607626487");
	const Decimal0: number = 18
	const Decimal1: number = 18

  const priceRatio = sqrtPriceX96.dividedBy(new BigNumber(2).pow(96)).pow(2);
  const decimalFactor = new BigNumber(10).pow(Decimal1).dividedBy(new BigNumber(10).pow(Decimal0));

  const buyOneOfToken0 = priceRatio.dividedBy(decimalFactor);
  const buyOneOfToken1 = new BigNumber(1).dividedBy(buyOneOfToken0);

  console.log("price of token0 in value of token1 : " + buyOneOfToken0.toFixed(Decimal1));
  console.log("price of token1 in value of token0 : " + buyOneOfToken1.toFixed(Decimal0));
  console.log("");

  // Convert to smallest unit (wei-like)
  const buyOneOfToken0Wei = buyOneOfToken0.multipliedBy(new BigNumber(10).pow(Decimal1)).integerValue(BigNumber.ROUND_DOWN).toFixed(0);
  const buyOneOfToken1Wei = buyOneOfToken1.multipliedBy(new BigNumber(10).pow(Decimal0)).integerValue(BigNumber.ROUND_DOWN).toFixed(0);

  console.log("price of token0 in value of token1 in lowest decimal : " + buyOneOfToken0Wei);
  console.log("price of token1 in value of token0 in lowest decimal : " + buyOneOfToken1Wei);
  console.log("");
});

// Current output, verified against Uniswap Interface exchange rates
//
// price of token0 in value of token1 : 1.061186745504384975
// price of token1 in value of token0 : 0.942341208308908205

// price of token0 in value of token1 in lowest decimal : 1061186745504384975
// price of token1 in value of token0 in lowest decimal : 942341208308908205
