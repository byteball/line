// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ILine.sol";
import "./ILoanPrice.sol";
import "./IHedgePrice.sol";


contract LoanNFT is ERC721 {

	using SafeERC20 for IERC20;

	struct Loan {
		uint collateral_amount;
		uint loan_amount;
		uint interest_multiplier; // interest multiplier when the loan was opened, used to calculate the interest to pay
		address initial_owner;
		uint32 ts;
	}

	// adds current_loan_amount which constantly grows
	struct CurrentLoan {
		uint loan_num;
		uint collateral_amount;
		uint loan_amount;
		uint current_loan_amount;
		uint interest_multiplier;
		address initial_owner;
		uint32 ts;
	}

	uint public last_loan_num;
	mapping(uint => Loan) public loans;

	mapping(uint => SellOrder) public sell_orders;
	mapping(uint => BuyOrder) public buy_orders;
	uint public max_buy_order_id;
	uint[] public released_buy_order_ids;
	function getCountReleasedIds() external view returns (uint) { return released_buy_order_ids.length; }

	uint public max_price_contract_gas_consumption = 200000;
	uint public exchange_fee10000 = 100; // 1%, charged from taker only
	string private base_uri = "";

	address public immutable issuer;

	modifier onlyIssuer() {
		require(msg.sender == issuer, "not issuer");
		_;
	}

	modifier onlyOwner() {
		require(msg.sender == Ownable(issuer).owner(), "not admin");
		_;
	}

	constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_){
		issuer = msg.sender;
	}

    function _baseURI() internal view override returns (string memory) {
        return base_uri;
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

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize) internal override {
		for (uint n = firstTokenId; n < firstTokenId + batchSize; n++)
			delete sell_orders[n];
	}

	function setExchangeFee(uint new_exchange_fee10000) onlyOwner external {
		require(new_exchange_fee10000 < 5000, "exchange fee too large");
		exchange_fee10000 = new_exchange_fee10000;
	}

	function setMaxPriceContractGasConsumption(uint new_gas) onlyOwner external {
		max_price_contract_gas_consumption = new_gas;
	}

	function setBaseUri(string memory new_uri) onlyOwner external {
		base_uri = new_uri;
	}
	

	function getLoan(uint loan_num) external view returns (Loan memory){
		return loans[loan_num];
	}

	function getAllActiveLoans() external view returns (CurrentLoan[] memory) {
		uint interest_multiplier = ILine(issuer).getCurrentInterestMultiplier();
		uint count_active_loans = 0;
		for (uint i=1; i<=last_loan_num; i++){
			Loan memory loan = loans[i];
			if (loan.collateral_amount > 0)
				count_active_loans++;
		}
		CurrentLoan[] memory active_loans = new CurrentLoan[](count_active_loans);
		uint current = 0;
		for (uint i=1; i<=last_loan_num; i++){
			Loan memory loan = loans[i];
			if (loan.collateral_amount > 0){
				active_loans[current] = CurrentLoan({
					loan_num: i,
					collateral_amount: loan.collateral_amount,
					loan_amount: loan.loan_amount,
					current_loan_amount: loan.loan_amount * interest_multiplier / loan.interest_multiplier,
					interest_multiplier: loan.interest_multiplier,
					initial_owner: loan.initial_owner,
					ts: loan.ts
				});
				current++;
			}
		}
		return active_loans;
	}

	function getAllActiveLoansByOwner(address owner) external view returns (CurrentLoan[] memory) {
		uint interest_multiplier = ILine(issuer).getCurrentInterestMultiplier();
		uint count_active_loans = 0;
		for (uint i=1; i<=last_loan_num; i++) {
			Loan memory loan = loans[i];
			if (loan.collateral_amount > 0 && ownerOf(i) == owner)
				count_active_loans++;
		}
		CurrentLoan[] memory active_loans = new CurrentLoan[](count_active_loans);
		if (count_active_loans == 0)
			return active_loans;
		uint current = 0;
		for (uint i=1; i<=last_loan_num; i++) {
			Loan memory loan = loans[i];
			if (loan.collateral_amount > 0 && ownerOf(i) == owner){
				active_loans[current] = CurrentLoan({
					loan_num: i,
					collateral_amount: loan.collateral_amount,
					loan_amount: loan.loan_amount,
					current_loan_amount: loan.loan_amount * interest_multiplier / loan.interest_multiplier,
					interest_multiplier: loan.interest_multiplier,
					initial_owner: loan.initial_owner,
					ts: loan.ts
				});
				current++;
			}
		}
		return active_loans;
	}



	/////////////////////////////////
	// Marketplace functions

	struct SellOrder {
		uint price;
		ILoanPrice price_contract;
		bytes data;
	}

	struct DetailedSellOrder {
		address user;
		uint price;
		ILoanPrice price_contract;
		bytes data;
		uint current_price;
		uint loan_num;
		uint collateral_amount;
		uint current_loan_amount;
		uint strike_price; // scaled by 1e18 factor
	}

	struct BuyOrder {
		address user;
		uint amount; // in collateral tokens
		uint strike_price; // scaled by 1e18 factor
		uint hedge_price; // scaled by 1e18 factor, how many collateral tokens I'm ready to pay per hedging 1 LINE token
		IHedgePrice price_contract;
		bytes data;
	}

	struct EvaluatedBuyOrder {
		address user;
		uint buy_order_id;
		uint amount; // in collateral tokens
		uint strike_price; // scaled by 1e18 factor
		uint hedge_price;
		IHedgePrice price_contract;
		bytes data;
		uint current_hedge_price; // scaled by 1e18 factor, how many collateral tokens I'm ready to pay per hedging 1 LINE token
	}

	event NewSellOrder(uint indexed loan_num, address indexed user, uint price, ILoanPrice price_contract, bytes data, uint current_price);
	event CanceledSellOrder(uint indexed loan_num, address indexed user, uint price, ILoanPrice price_contract, bytes data);
	event Bought(uint indexed loan_num, address indexed buyer, address indexed seller, uint price);
	
	event NewBuyOrder(uint indexed buy_order_id, address indexed user, uint amount, uint strike_price, uint hedge_price, IHedgePrice price_contract, bytes data, uint current_hedge_price);
	event CanceledBuyOrder(uint indexed buy_order_id, address indexed user, uint amount, uint strike_price, uint hedge_price, IHedgePrice price_contract, bytes data);
	event FilledBuyOrder(uint indexed buy_order_id, address indexed user, uint amount, uint strike_price, uint hedge_price, IHedgePrice price_contract, bytes data);
	event Sold(uint indexed loan_num, uint buy_order_id, address indexed buyer, address indexed seller, uint price);

	// put up a loan for sale, the price is in GBYTEs. This can also replace an existing order
	function createSellOrder(uint loan_num, uint price, ILoanPrice price_contract, bytes memory data) external {
		require(ownerOf(loan_num) == msg.sender, "not your loan");
		require(price == 0 && address(price_contract) != address(0) || price > 0 && address(price_contract) == address(0), "need either static price or price_contract");
		uint current_price = price;
		if (address(price_contract) != address(0)){ // validate the price contract
			uint initial_gas = gasleft();
			current_price = price_contract.getPrice(loan_num, data);
			require(current_price > 0, "price_contract returned invalid price");
			uint remaining_gas = gasleft();
			require(initial_gas - remaining_gas < max_price_contract_gas_consumption, "getPrice is too gas-expensive"); // buyer would have to pay a lot for gas
		}
		sell_orders[loan_num] = SellOrder({
			price: price,
			price_contract: price_contract,
			data: data
		});
		emit NewSellOrder(loan_num, msg.sender, price, price_contract, data, current_price);
	}

	function cancelSellOrder(uint loan_num) external {
		require(ownerOf(loan_num) == msg.sender, "not your loan");
		SellOrder storage so = sell_orders[loan_num];
		emit CanceledSellOrder(loan_num, msg.sender, so.price, so.price_contract, so.data);
		delete sell_orders[loan_num];
	}

	function getSellOrderPrice(uint loan_num) public view returns (uint) {
		SellOrder storage so = sell_orders[loan_num];
		if (so.price > 0)
			return so.price;
		if (address(so.price_contract) == address(0)) // no sell order at all
			return 0;
		try so.price_contract.getPrice(loan_num, so.data) returns (uint price) {
			return price; // getPrice() can return 0 which effectively removes the order
		}
		catch { // they won't DoS us by reverting
			return 0;
		}
	}

	function buy(uint loan_num, uint max_price) external {
		uint price = getSellOrderPrice(loan_num);
		require(price > 0, "this loan is not for sale");
		if (max_price > 0)
			require(price <= max_price, "price too large"); // if the price is determined by price_contract, it could suddenly change
		address old_owner = ownerOf(loan_num);
		require(old_owner != msg.sender, "buying from oneself?");
		IERC20(ILine(issuer).collateral_token_address()).safeTransferFrom(msg.sender, old_owner, price);
		if (exchange_fee10000 > 0)
			IERC20(ILine(issuer).collateral_token_address()).safeTransferFrom(msg.sender, address(this), price * exchange_fee10000/10000);
		_safeTransfer(old_owner, msg.sender, loan_num, ""); // may call onERC721Received() which might re-enter but it is safe since there are no state changes after the external call
		emit Bought(loan_num, msg.sender, old_owner, price);
	}

	function getSellOrders() external view returns (DetailedSellOrder[] memory) {
		uint interest_multiplier = ILine(issuer).getCurrentInterestMultiplier();
		uint count_loans_for_sale = 0;
		for (uint i=1; i<=last_loan_num; i++){
			if (getSellOrderPrice(i) > 0)
				count_loans_for_sale++;
		}
		DetailedSellOrder[] memory active_sell_orders = new DetailedSellOrder[](count_loans_for_sale);
		uint current = 0;
		for (uint i=1; i<=last_loan_num; i++){
			uint current_price = getSellOrderPrice(i);
			if (current_price > 0){
				Loan memory loan = loans[i];
				SellOrder storage so = sell_orders[i];
				uint current_loan_amount = loan.loan_amount * interest_multiplier / loan.interest_multiplier;
				active_sell_orders[current] = DetailedSellOrder({
					user: ownerOf(i),
					price: so.price,
					price_contract: so.price_contract,
					data: so.data,
					current_price: current_price,
					loan_num: i,
					collateral_amount: loan.collateral_amount,
					current_loan_amount: current_loan_amount,
					strike_price: 1e18 * loan.collateral_amount / current_loan_amount
				});
				current++;
			}
		}
		return active_sell_orders;
	}




	function findUnusedBuyOrderId() internal returns (uint){
		if (released_buy_order_ids.length > 0){
			uint id = released_buy_order_ids[released_buy_order_ids.length - 1];
			released_buy_order_ids.pop();
			return id;
		}
		max_buy_order_id++;
		return max_buy_order_id;
	}

	function createBuyOrder(uint amount, uint strike_price, uint hedge_price, IHedgePrice price_contract, bytes memory data) external {
		require(amount > 0, "bad amount");
		require(strike_price > 0, "bad strike price");
		require(hedge_price == 0 && address(price_contract) != address(0) || hedge_price > 0 && address(price_contract) == address(0), "need either a static hedge price or a price_contract");
		IERC20(ILine(issuer).collateral_token_address()).safeTransferFrom(msg.sender, address(this), amount);
		uint current_hedge_price = hedge_price;
		if (address(price_contract) != address(0)){ // validate the price contract
			uint initial_gas = gasleft();
			current_hedge_price = price_contract.getPrice(strike_price, data);
			require(current_hedge_price > 0, "price_contract returned invalid price");
			uint remaining_gas = gasleft();
			require(initial_gas - remaining_gas < max_price_contract_gas_consumption, "getPrice is too gas-expensive"); // seller would have to pay a lot for gas
		}
		uint id = findUnusedBuyOrderId();
		buy_orders[id] = BuyOrder({
			user: msg.sender,
			amount: amount,
			strike_price: strike_price,
			hedge_price: hedge_price,
			price_contract: price_contract,
			data: data
		});
		emit NewBuyOrder(id, msg.sender, amount, strike_price, hedge_price, price_contract, data, current_hedge_price);
	}

	function cancelBuyOrder(uint id) external {
		BuyOrder memory bo = buy_orders[id];
		require(bo.user != address(0), "no such order");
		require(bo.user == msg.sender, "not your order");
		delete buy_orders[id];
		released_buy_order_ids.push(id);
		IERC20(ILine(issuer).collateral_token_address()).safeTransfer(msg.sender, bo.amount);
		emit CanceledBuyOrder(id, msg.sender, bo.amount, bo.strike_price, bo.hedge_price, bo.price_contract, bo.data);
	}

	function getHedgePrice(uint buy_order_id) public view returns (uint) {
		BuyOrder storage bo = buy_orders[buy_order_id];
		if (bo.hedge_price > 0)
			return bo.hedge_price;
		if (address(bo.price_contract) == address(0)) // no buy order at all
			return 0;
		try bo.price_contract.getPrice(bo.strike_price, bo.data) returns (uint price) {
			return price; // getPrice() can return 0 which effectively removes the order
		}
		catch { // they won't DoS us by reverting
			return 0;
		}
	}

	function sell(uint loan_num, uint buy_order_id, uint min_price) external {
		address old_owner = ownerOf(loan_num);
		require(old_owner == msg.sender, "not your loan");
		Loan storage loan = loans[loan_num];

		BuyOrder storage bo = buy_orders[buy_order_id];
		address buyer = bo.user;
		require(buyer != address(0), "no such order");
		require(buyer != old_owner, "selling to oneself?");

		uint current_loan_amount = loan.loan_amount * ILine(issuer).getCurrentInterestMultiplier() / loan.interest_multiplier;
		uint strike_price = 1e18 * loan.collateral_amount / current_loan_amount;
		require(strike_price >= bo.strike_price, "strike price is smaller than the buyer wants");

		uint hedge_price = getHedgePrice(buy_order_id);
		require(hedge_price > 0, "order not available");
		uint price = hedge_price * current_loan_amount / 1e18;
		if (min_price > 0)
			require(price >= min_price, "price too small");
		require(price <= bo.amount, "buy order amount too small for this loan");

		bo.amount -= price;
		if (bo.amount == 0) { // fully filled the order, remove it
			BuyOrder memory mbo = buy_orders[buy_order_id];
			delete buy_orders[buy_order_id];
			released_buy_order_ids.push(buy_order_id);
			emit FilledBuyOrder(buy_order_id, buyer, mbo.amount, mbo.strike_price, mbo.hedge_price, mbo.price_contract, mbo.data);
		}
		_safeTransfer(msg.sender, buyer, loan_num, ""); // may call onERC721Received() which might re-enter but it is safe since we have already subtracted everything before the external call
		IERC20(ILine(issuer).collateral_token_address()).safeTransfer(msg.sender, price * (10000 - exchange_fee10000)/10000);
		emit Sold(loan_num, buy_order_id, buyer, msg.sender, price);
	}

	function getBuyOrders() external view returns (EvaluatedBuyOrder[] memory) {
		uint count_buy_orders = 0;
		for (uint id=1; id<=max_buy_order_id; id++){
			if (getHedgePrice(id) > 0)
				count_buy_orders++;
		}
		EvaluatedBuyOrder[] memory active_buy_orders = new EvaluatedBuyOrder[](count_buy_orders);
		uint current = 0;
		for (uint id=1; id<=max_buy_order_id; id++){
			uint current_hedge_price = getHedgePrice(id);
			if (current_hedge_price > 0){
				BuyOrder storage bo = buy_orders[id];
				active_buy_orders[current] = EvaluatedBuyOrder({
					user: bo.user,
					buy_order_id: id,
					amount: bo.amount,
					strike_price: bo.strike_price,
					hedge_price: bo.hedge_price,
					price_contract: bo.price_contract,
					data: bo.data,
					current_hedge_price: current_hedge_price
				});
				current++;
			}
		}
		return active_buy_orders;
	}


}
