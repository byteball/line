// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ILoanPrice.sol";

contract LoanPriceSample is ILoanPrice {
	// returns the price of the loan
	function getPrice(uint loan_num, bytes memory data) external view returns (uint) {
		return 2e18;
	}
}
