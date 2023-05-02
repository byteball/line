// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";


contract LoanNFT is ERC721 {

	struct Loan {
		uint collateral_amount;
		uint loan_amount;
		uint interest_multiplier; // interest multiplier when the loan was opened, used to calculate the interest to pay
		address initial_owner;
		uint32 ts;
	}

	uint public last_loan_num;
	mapping(uint => Loan) public loans;


	address public immutable issuer;

	modifier onlyIssuer() {
		require(msg.sender == issuer, "not issuer");
		_;
	}

	constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_){
		issuer = msg.sender;
	}

	function mint(Loan memory loan) external onlyIssuer returns (uint) {
		last_loan_num++;
		loans[last_loan_num] = loan;
		_safeMint(loan.initial_owner, last_loan_num); // may re-enter, no harm
		return last_loan_num;
	}

	function burn(uint loan_num) external onlyIssuer {
		delete loans[loan_num];
		_burn(loan_num);
	}

	function getLoan(uint loan_num) external view returns (Loan memory){
		return loans[loan_num];
	}

	function getAllActiveLoans() external view returns (Loan[] memory) {
		uint count_active_loans = 0;
		for (uint i=1; i<=last_loan_num; i++){
			Loan memory loan = loans[i];
			if (loan.collateral_amount > 0)
				count_active_loans++;
		}
		Loan[] memory active_loans = new Loan[](count_active_loans);
		uint current = 0;
		for (uint i=1; i<=last_loan_num; i++){
			Loan memory loan = loans[i];
			if (loan.collateral_amount > 0){
				active_loans[current] = loan;
				current++;
			}
		}
		return active_loans;
	}

	function getAllActiveLoansByOwner(address owner) external view returns (Loan[] memory) {
		uint count_active_loans = 0;
		for (uint i=1; i<=last_loan_num; i++) {
			Loan memory loan = loans[i];
			if (loan.collateral_amount > 0 && ownerOf(i) == owner)
				count_active_loans++;
		}
		Loan[] memory active_loans = new Loan[](count_active_loans);
		if (count_active_loans == 0)
			return active_loans;
		uint current = 0;
		for (uint i=1; i<=last_loan_num; i++) {
			Loan memory loan = loans[i];
			if (loan.collateral_amount > 0 && ownerOf(i) == owner){
				active_loans[current] = loan;
				current++;
			}
		}
		return active_loans;
	}

}
