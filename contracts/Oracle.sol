// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
//import '@uniswap/v2-core/contracts/libraries/UQ112x112.sol';
//import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol';

import "./IOracle.sol";


contract Oracle is IOracle {
	uint public constant PERIOD = 24 hours;

	IUniswapV2Pair immutable pair;
	bool immutable isToken0;

	uint    public priceCumulativeLast;
	uint32  public blockTimestampLast;

	constructor(address pairAddress, address token) {
		pair = IUniswapV2Pair(pairAddress);
		require(pair.token0() == token || pair.token1() == token, "token is not in the pair");
		isToken0 = pair.token0() == token;
		priceCumulativeLast = isToken0 ? pair.price0CumulativeLast() : pair.price1CumulativeLast(); // fetch the current accumulated price value
		uint112 reserve0;
		uint112 reserve1;
		(reserve0, reserve1, blockTimestampLast) = pair.getReserves();
		require(reserve0 != 0 && reserve1 != 0, 'NO_RESERVES'); // ensure that there's liquidity in the pair
	}

	function updateAndGetAveragePrice() public returns (uint price0Average) {
		(uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
		uint priceCumulative = isToken0 ? price0Cumulative : price1Cumulative;
		uint32 timeElapsed = blockTimestamp - blockTimestampLast;

		price0Average = (priceCumulative - priceCumulativeLast) / timeElapsed * 1e18 / UQ112x112.Q112;

		// update the state if a full period has passed since the last update
		if (timeElapsed >= PERIOD){
			priceCumulativeLast = priceCumulative;
			blockTimestampLast = blockTimestamp;
		}
	}

	function getAveragePrice() external view returns (uint price0Average) {
		(uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
		uint priceCumulative = isToken0 ? price0Cumulative : price1Cumulative;
		uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

		price0Average = (priceCumulative - priceCumulativeLast) / timeElapsed * 1e18 / UQ112x112.Q112;
	}

	function getCurrentPrice() public view returns (uint){
		(uint reserve0, uint reserve1, ) = pair.getReserves();
		return isToken0 ? 1e18 * reserve1 / reserve0 : 1e18 * reserve0 / reserve1;
	}

	// returm max(avg price, current price)
	function getPrice() external returns (uint){
		uint current_price = getCurrentPrice();
		uint avg_price = updateAndGetAveragePrice();
		return current_price > avg_price ? current_price : avg_price;
	}

}


library UQ112x112 {
    uint224 constant Q112 = 2**112;

    // encode a uint112 as a UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    // divide a UQ112x112 by a uint112, returning a UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}
