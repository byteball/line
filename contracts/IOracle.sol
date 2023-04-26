// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IOracle {
	// returns the price of LINE multiplied by 1e18
	function getPrice() external returns (uint);
}
