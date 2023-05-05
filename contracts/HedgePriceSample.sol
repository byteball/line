// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IHedgePrice.sol";

contract HedgePriceSample is IHedgePrice {
	// returns the price of the loan
	function getPrice(uint strike_price, bytes memory data) external view returns (uint) {
		return 2e18/1000/10;
	}
}
