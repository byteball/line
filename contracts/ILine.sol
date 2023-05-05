// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ILine {
	// returns the price of LINE multiplied by 1e18
	function collateral_token_address() external view returns (address);
	function getCurrentInterestMultiplier() external view returns (uint);
}
