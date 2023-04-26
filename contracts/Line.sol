// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./IOracle.sol";
import "./Staking.sol";


contract Line is ERC20, Ownable, Staking {

	using SafeERC20 for IERC20;

	struct Loan {
		uint collateral_amount;
		uint loan_amount;
		uint interest_multiplier; // interest multiplier when the loan was opened, used to calculate the interest to pay
		address owner;
		uint32 ts;
	}

	event NewLoan(uint indexed loan_num, address indexed owner, uint collateral_amount, uint loan_amount, uint net_loan_amount, uint interest_multiplier);
	event Repaid(uint indexed loan_num, address indexed owner, uint collateral_amount, uint repaid_loan_amount, uint interest_multiplier);

	address public immutable collateral_token_address;
	uint public origination_fee10000 = 100; // 1%
	uint public interest_rate10000 = 100; // 1% p.a.
	address public oracle;

	uint public interest_multiplier = 1e18;
	uint public last_ts;

	uint public last_loan_num;
	mapping(uint => Loan) public loans;

	uint public total_debt;
	uint public total_interest;

	// incentivized liquidity pools
	uint public total_reward_share10000; // allowed to be more than 100%




	constructor(address _collateral_token_address, string memory name, string memory symbol) ERC20(name, symbol) {
		require(_collateral_token_address != address(0), "only ERC20 tokens");
		collateral_token_address = _collateral_token_address;
		last_ts = block.timestamp;
	}

	function setOriginationFee(uint new_origination_fee10000) onlyOwner external {
		require(new_origination_fee10000 < 10000, "origination fee too large");
		origination_fee10000 = new_origination_fee10000;
	}

	function setInterestRate(uint new_interest_rate10000) onlyOwner external {
		require(new_interest_rate10000 < 10000, "interest rate too large");
		interest_rate10000 = new_interest_rate10000;
	}

	function setOracle(address new_oracle) onlyOwner external {
		require(IOracle(new_oracle).getPrice() > 0, "bad oracle");
		oracle = new_oracle;
	}

	function setRewardShare(address pool_address, uint16 reward_share10000) onlyOwner external {
		total_reward_share10000 += uint(reward_share10000) - uint(pools[pool_address].reward_share10000);
		setPoolShare(pool_address, reward_share10000); // can be 0 to stop rewards
	}

	function applyInterest() public {
		interest_multiplier += interest_multiplier * interest_rate10000 / 10000 * (block.timestamp - last_ts) / 3600 / 24 / 365;
		uint interest = total_debt * interest_rate10000 / 10000 * (block.timestamp - last_ts) / 3600 / 24 / 365;
		total_debt += interest;
		total_interest += interest;
		last_ts = block.timestamp; 
	}

	function getLoanAmount(uint collateral_amount) internal returns (uint) {
		if (oracle == address(0)) // 1:1000 rate
			return collateral_amount * 1000;
		return collateral_amount * 1e18 / IOracle(oracle).getPrice();
	}

	function borrow(uint collateral_amount) external returns (uint) {
		IERC20(collateral_token_address).safeTransferFrom(msg.sender, address(this), collateral_amount);
		applyInterest();
		uint loan_amount = getLoanAmount(collateral_amount);
		uint net_loan_amount = loan_amount - loan_amount * origination_fee10000 / 10000;
		last_loan_num++;
		total_debt += loan_amount;
		loans[last_loan_num] = Loan({
			collateral_amount: collateral_amount,
			loan_amount: loan_amount,
			interest_multiplier: interest_multiplier,
			owner: msg.sender,
			ts: uint32(block.timestamp)
		});
		_mint(msg.sender, net_loan_amount);
		emit NewLoan(last_loan_num, msg.sender, collateral_amount, loan_amount, net_loan_amount, interest_multiplier);
		return last_loan_num;
	}

	function repay(uint loan_num) external {
		Loan memory loan = loans[loan_num];
		require(loan.collateral_amount > 0, "no such loan");
		require(loan.owner == msg.sender, "not your loan");
		applyInterest();
		uint current_loan_amount = loan.loan_amount * interest_multiplier / loan.interest_multiplier;
		_burn(msg.sender, current_loan_amount);
		delete loans[loan_num];
		total_debt -= current_loan_amount;
		IERC20(collateral_token_address).safeTransfer(msg.sender, loan.collateral_amount);
		emit Repaid(loan_num, msg.sender, loan.collateral_amount, current_loan_amount, interest_multiplier);
	}

	function getLoanDue(uint loan_num) external view returns (uint) {
		Loan memory loan = loans[loan_num];
		require(loan.collateral_amount > 0, "no such loan");
		uint new_interest_multiplier = interest_multiplier + interest_multiplier * interest_rate10000 / 10000 * (block.timestamp - last_ts) / 3600 / 24 / 365;
		uint current_loan_amount = loan.loan_amount * new_interest_multiplier / loan.interest_multiplier;
		return current_loan_amount;
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
			if (loan.collateral_amount > 0 && loan.owner == owner)
				count_active_loans++;
		}
		Loan[] memory active_loans = new Loan[](count_active_loans);
		if (count_active_loans == 0)
			return active_loans;
		uint current = 0;
		for (uint i=1; i<=last_loan_num; i++) {
			Loan memory loan = loans[i];
			if (loan.collateral_amount > 0 && loan.owner == owner){
				active_loans[current] = loan;
				current++;
			}
		}
		return active_loans;
	}

	function updateAndGetTotalReward() public override returns (uint) {
		applyInterest();
		return total_interest;
	}

	function getTotalReward() public view override returns (uint) {
		return total_interest + total_debt * interest_rate10000 / 10000 * (block.timestamp - last_ts) / 3600 / 24 / 365;
	}

}
