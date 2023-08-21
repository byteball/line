// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IOracle.sol";

interface IEquilibrePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint reserve0, uint reserve1, uint32 blockTimestampLast);
	function currentCumulativePrices() external view returns (uint reserve0Cumulative, uint reserve1Cumulative, uint blockTimestamp);
}


contract EquilibreOracle is IOracle {
	uint public constant PERIOD = 24 hours;

	IEquilibrePair immutable pair;
	bool immutable isToken0;

	uint    public reserve0CumulativeLast;
	uint    public reserve1CumulativeLast;
	uint32  public blockTimestampLast;

	constructor(address pairAddress, address token) {
		pair = IEquilibrePair(pairAddress);
		require(pair.token0() == token || pair.token1() == token, "token is not in the pair");
		isToken0 = pair.token0() == token;
		(reserve0CumulativeLast, reserve1CumulativeLast, ) = pair.currentCumulativePrices();
		uint reserve0;
		uint reserve1;
		(reserve0, reserve1, blockTimestampLast) = pair.getReserves();
		require(reserve0 != 0 && reserve1 != 0, 'NO_RESERVES'); // ensure that there's liquidity in the pair
	}

	function updateAndGetAveragePrice() public returns (uint priceAverage) {
		(uint reserve0Cumulative, uint reserve1Cumulative, uint blockTimestamp) = pair.currentCumulativePrices();
		uint d0 = reserve0Cumulative - reserve0CumulativeLast;
		uint d1 = reserve1Cumulative - reserve1CumulativeLast;
		priceAverage = isToken0 ? 1e18 * d1/d0 : 1e18 * d1/d0;
		uint32 timeElapsed = uint32(blockTimestamp) - blockTimestampLast;

		// update the state if a full period has passed since the last update
		if (timeElapsed >= PERIOD){
			reserve0CumulativeLast = reserve0Cumulative;
			reserve1CumulativeLast = reserve1Cumulative;
			blockTimestampLast = uint32(blockTimestamp);
		}
	}

	function getAveragePrice() external view returns (uint priceAverage) {
		(uint reserve0Cumulative, uint reserve1Cumulative, ) = pair.currentCumulativePrices();
		uint d0 = reserve0Cumulative - reserve0CumulativeLast;
		uint d1 = reserve1Cumulative - reserve1CumulativeLast;
		priceAverage = isToken0 ? 1e18 * d1/d0 : 1e18 * d0/d1;
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

