// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IHedgePrice {
	// returns the price of the hedge we are prepared to pay
	function getPrice(uint strike_price, bytes memory data) external view returns (uint);
}
