const { expect } = require("chai");
const {
	time,
	loadFixture,
	reset,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const uniswapV2RouterJson = require('@uniswap/v2-periphery/build/UniswapV2Router02.json');
const uniswapV2FactoryJson = require('@uniswap/v2-core/build/UniswapV2Factory.json');
const uniswapV2PairJson = require('@uniswap/v2-core/build/UniswapV2Pair.json');
const nftJson = require('../artifacts/contracts/LoanNFT.sol/LoanNFT.json');
require('dotenv').config();

const { utils: { parseEther, formatEther }, BigNumber, constants: { AddressZero } } = ethers;

const UNISWAP_V2_ROUTER = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D';

describe("Line", function () {
	// We define a fixture to reuse the same setup in every test.
	// We use loadFixture to run this setup once, snapshot that state,
	// and reset Hardhat Network to that snapshot in every test.
	async function deployContracts() {

		await reset(`https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`, 17082600);

		// Contracts are deployed using the first signer/account by default
		const signers = await ethers.getSigners();
		const [owner, alice, bob, charlie] = signers;
	//	console.log({ owner, alice });

		const GbyteFactory = await ethers.getContractFactory("MintableToken");
		const gbyte_contract = await GbyteFactory.deploy("Imported GBYTE", "GBYTE");
		console.log(`deployed GBYTE at`, gbyte_contract.address);

		const LineFactory = await ethers.getContractFactory("Line");
		const line_contract = await LineFactory.deploy(gbyte_contract.address, "LINE Token", "LINE");
		console.log(`deployed LINE at`, line_contract.address);

		const uniswap_contract = new ethers.Contract(UNISWAP_V2_ROUTER, uniswapV2RouterJson.abi, signers[0]);
		console.log(`uniswap router contract`, uniswap_contract.address);

		return { gbyte_contract, line_contract, uniswap_contract, owner, alice, bob, charlie };
	}

	async function printOraclePrices() {
		const current_price = formatEther(await oracle_contract.getCurrentPrice());
		const average_price = formatEther(await oracle_contract.getAveragePrice());
		console.log({ current_price, average_price });	
	}

	let gbyte_contract;
	let line_contract;
	let nft_contract;
	let uniswap_contract;
	let oracle_contract;
	let pair_address;
	let owner;
	let alice;
	let bob;
	let charlie;
	let lp_amount;

	describe("Deployment", function () {
		it("Contract deployment", async function () {
		//	const { gbyte_contract, line_contract } = await loadFixture(deployContracts);
			const res = await deployContracts();
			gbyte_contract = res.gbyte_contract;
			line_contract = res.line_contract;
			uniswap_contract = res.uniswap_contract;
			owner = res.owner;
			alice = res.alice;
			bob = res.bob;
			charlie = res.charlie;

			const nft_contract_address = await line_contract.loanNFT();
			nft_contract = new ethers.Contract(nft_contract_address, nftJson.abi, alice);
			console.log('NFT contract', nft_contract.address);

			expect(await gbyte_contract.symbol()).to.equal("GBYTE");
			expect(await line_contract.symbol()).to.equal("LINE");
			expect(await line_contract.collateral_token_address()).to.equal(gbyte_contract.address);
		});

		it("Initial distribution", async function () {
			const amount = parseEther("100");
			await expect(gbyte_contract.mint(alice.address, amount)).to.changeTokenBalance(gbyte_contract, alice.address, amount);
			await expect(gbyte_contract.mint(bob.address, amount)).to.changeTokenBalance(gbyte_contract, bob.address, amount);
			await expect(gbyte_contract.mint(charlie.address, amount)).to.changeTokenBalance(gbyte_contract, charlie.address, amount);
		});

		it("Admin", async function () {
			expect(await line_contract.origination_fee10000()).to.equal(100);
			await expect(line_contract.setOriginationFee(200)).not.to.be.reverted;
			expect(await line_contract.origination_fee10000()).to.equal(200);
			await expect(line_contract.connect(alice).setOriginationFee(300)).to.be.revertedWith("Ownable: caller is not the owner");

			expect(await nft_contract.exchange_fee10000()).to.equal(100);
			await expect(nft_contract.connect(owner).setExchangeFee(20)).not.to.be.reverted; // 0.2%
			expect(await nft_contract.exchange_fee10000()).to.equal(20);
			await expect(nft_contract.connect(alice).setExchangeFee(300)).to.be.revertedWith("not admin");
		});

		it("Take a loan", async function () {
			const amount = parseEther("10");
			const lineBalanceInGbyte = await gbyte_contract.balanceOf(line_contract.address)
			const aliceBalanceInGbyte = await gbyte_contract.balanceOf(alice.address)
			const aliceBalanceInLine = await line_contract.balanceOf(alice.address)
			const loan_amount = amount.mul(1000);
			const net_loan_amount = loan_amount.mul(98).div(100);
			await expect(gbyte_contract.connect(alice).approve(line_contract.address, BigNumber.from(2).pow(256).sub(1))).not.to.be.reverted;
		//	const res = await line_contract.connect(alice).borrow(amount);
		//	expect(res).to.emit(line_contract, "NewL8oan").withArgs(10, alice.address, amount, amount, net_loan_amount, parseEther("1"));
			await expect(line_contract.connect(alice).borrow(amount))
				.to.emit(line_contract, "NewLoan").withArgs(1, alice.address, amount, loan_amount, net_loan_amount, anyValue)
			//	.to.changeTokenBalances(gbyte_contract, [alice.address, line_contract.address], [amount.mul(-2), amount])
			//	.to.changeTokenBalance(line_contract, alice.address, net_loan_amount);
			expect(await gbyte_contract.balanceOf(line_contract.address)).to.eq(lineBalanceInGbyte.add(amount))
			expect(await gbyte_contract.balanceOf(alice.address)).to.eq(aliceBalanceInGbyte.sub(amount))
			expect(await line_contract.balanceOf(alice.address)).to.eq(aliceBalanceInLine.add(net_loan_amount))
			expect(await nft_contract.balanceOf(alice.address)).to.eq(1)
			expect(await nft_contract.ownerOf(1)).to.eq(alice.address)
			const loans = await nft_contract.getAllActiveLoans()
			const alice_loans = await nft_contract.getAllActiveLoansByOwner(alice.address)
			expect(loans.length).to.eq(1)
			expect(alice_loans.length).to.eq(1)
			expect(loans[0].collateral_amount).to.eq(amount)
			expect(loans[0].loan_amount).to.eq(loan_amount)
			expect(loans[0].initial_owner).to.eq(alice.address)
		})

		it("Create a uniswap pair and add liquidity", async function () {
			const gbyte_amount = parseEther("1");
			const line_amount = parseEther("1000");
			await expect(gbyte_contract.connect(alice).approve(uniswap_contract.address, BigNumber.from(2).pow(256).sub(1))).not.to.be.reverted;
			await expect(line_contract.connect(alice).approve(uniswap_contract.address, BigNumber.from(2).pow(256).sub(1))).not.to.be.reverted;
			await expect(uniswap_contract.connect(alice).addLiquidity(line_contract.address, gbyte_contract.address, line_amount, gbyte_amount, line_amount, gbyte_amount, alice.address, Math.round(Date.now() / 1000) + 100)).not.to.be.reverted;
		});

		it("Deploy the oracle", async function () {
			const factory_address = await uniswap_contract.factory();
			const factory_contract = new ethers.Contract(factory_address, uniswapV2FactoryJson.abi, owner);
			console.log(`uniswap factory contract`, factory_contract.address);
			
			pair_address = await factory_contract.getPair(line_contract.address, gbyte_contract.address);
			console.log({ pair_address });

			const OracleFactory = await ethers.getContractFactory("UniswapV2Oracle");
			oracle_contract = await OracleFactory.deploy(pair_address, line_contract.address);
			console.log(`deployed oracle at`, oracle_contract.address);

			await printOraclePrices();
		});

		it("Set the oracle", async function () {
			await expect(line_contract.setOracle(alice.address)).to.be.reverted;
			await expect(line_contract.setOracle(oracle_contract.address)).not.to.be.reverted;
		});

		it("Add the new pair as a reward pool", async function () {
			await expect(line_contract.setRewardShare(alice.address, 5000)).to.be.reverted;
			await expect(line_contract.setRewardShare(pair_address, 5000)).not.to.be.reverted;
			expect(await line_contract.total_reward_share10000()).to.eq(5000);
			const pool = await line_contract.pools(pair_address);
			console.log('pool info', pool);
			expect(pool.exists).to.be.true;
			expect(pool.reward_share10000).to.be.eq(5000);
			expect(pool.last_total_reward).to.be.gt(0);
		});

		it("Stake the LP tokens for rewards", async function () {
			const pair_contract = new ethers.Contract(pair_address, uniswapV2PairJson.abi, alice);
			await expect(pair_contract.approve(line_contract.address, BigNumber.from(2).pow(256).sub(1))).not.to.be.reverted;
			lp_amount = await pair_contract.balanceOf(alice.address);
			await expect(line_contract.connect(alice).stake(gbyte_contract.address, lp_amount)).to.be.revertedWith("this pool is not receiving rewards");
			await expect(line_contract.connect(alice).stake(pair_address, lp_amount)).to.emit(line_contract, "Staked").withArgs(pair_address, alice.address, lp_amount, lp_amount);
			const stake = await line_contract.stakes(pair_address, alice.address);
			console.log('stake info', stake);
			expect(stake.amount).to.be.eq(lp_amount);
			expect(stake.last_total_pool_reward_per_token).to.be.eq(0);
			expect(stake.reward).to.be.eq(0);
		});

		it("Trade to change the oracle price", async function () {
			await time.increase(3600);
			const amount = parseEther('0.5');
			const amountOutMin = parseEther('0.33').mul(1000); // 1 - 1/1.5
			await expect(uniswap_contract.connect(alice).swapExactTokensForTokens(amount, amountOutMin, [gbyte_contract.address, line_contract.address], alice.address, Math.round(Date.now() / 1000) + 100)).not.to.be.reverted;
			await printOraclePrices();
			await time.increase(3600);
			await printOraclePrices();
		});

		it("Claim rewards", async function () {
			const balance_before = await line_contract.balanceOf(alice.address);
			const loan_amount = parseEther('10').mul(1000);
			const interest = loan_amount.mul(2 * 3600).div(24 * 3600 * 365).div(100); // total charged interest in 2 hours (1% p.a.)
		//	const la1 = interest1.add(loan_amount);
		//	const interest2 = la1.mul(3600).div(24 * 3600 * 365).div(100); // 2nd hour
			const reward = interest.div(2); // 0.5% yearly accrued during 2 hours
			await expect(line_contract.connect(alice).claim(pair_address)).to.emit(line_contract, "Claimed").withArgs(pair_address, alice.address, anyValue);
			const balance_after = await line_contract.balanceOf(alice.address);
			expect(balance_after).to.be.closeTo(balance_before.add(reward), reward.div(100));
		});

		it("Withdraw the LP tokens", async function () {
			const pair_contract = new ethers.Contract(pair_address, uniswapV2PairJson.abi, alice);
			const balance_before = await pair_contract.balanceOf(alice.address);
			expect(balance_before).to.be.eq(0);
			await expect(line_contract.connect(alice).unstake(pair_address, 0)).to.emit(line_contract, "Unstaked").withArgs(pair_address, alice.address, lp_amount, 0);
			const balance_after = await pair_contract.balanceOf(alice.address);
			expect(balance_after).to.be.eq(lp_amount);
		});

		it("Alice puts the loan for sale", async function () {
			const price = parseEther('1');
			
			const LoanPriceSampleFactory = await ethers.getContractFactory("LoanPriceSample");
			const loan_price_contract = await LoanPriceSampleFactory.deploy();
			console.log(`deployed loan price contract at`, loan_price_contract.address);
			const contract_price = parseEther('2');

			await expect(nft_contract.connect(alice).createSellOrder(1, price, AddressZero, [])).to.emit(nft_contract, "NewSellOrder").withArgs(1, alice.address, price, AddressZero, "0x", price);

			const amount = parseEther("10");
			const loan_amount = amount.mul(1000);
			const interest = loan_amount.mul(2 * 3600).div(24 * 3600 * 365).div(100); // total charged interest in 2 hours (1% p.a.)
			const current_loan_amount = loan_amount.add(interest)
			let sell_orders = await nft_contract.getSellOrders();
			expect(sell_orders.length).to.eq(1);
			expect(sell_orders[0].user).to.eq(alice.address);
			expect(sell_orders[0].price).to.eq(price);
			expect(sell_orders[0].price_contract).to.eq(AddressZero);
			expect(sell_orders[0].current_price).to.eq(price);
			expect(sell_orders[0].loan_num).to.eq(1);
			expect(sell_orders[0].collateral_amount).to.eq(amount);
			expect(sell_orders[0].current_loan_amount).to.be.closeTo(current_loan_amount, 4e14);
			expect(sell_orders[0].strike_price).to.be.closeTo(parseEther('1').mul(amount).div(current_loan_amount), 4e14);

			// cancel the order
			await expect(nft_contract.connect(alice).cancelSellOrder(1)).to.emit(nft_contract, "CanceledSellOrder").withArgs(1, alice.address, price, AddressZero, "0x");
			sell_orders = await nft_contract.getSellOrders();
			expect(sell_orders.length).to.eq(0);

			// create the order again, now with price_contract
			await expect(nft_contract.connect(alice).createSellOrder(1, 0, loan_price_contract.address, [])).to.emit(nft_contract, "NewSellOrder").withArgs(1, alice.address, 0, loan_price_contract.address, "0x", contract_price);
			sell_orders = await nft_contract.getSellOrders();
			expect(sell_orders.length).to.eq(1);
			expect(sell_orders[0].price).to.eq(0);
			expect(sell_orders[0].price_contract).to.eq(loan_price_contract.address);
			expect(sell_orders[0].current_price).to.eq(contract_price);
		});

		it("Bob buys the loan from Alice", async function () {
			const price = parseEther('2');
			const fee = price.div(500) // 0.2%

			await expect(gbyte_contract.connect(bob).approve(nft_contract.address, BigNumber.from(2).pow(256).sub(1))).not.to.be.reverted;

			const alice_balance_before = await gbyte_contract.balanceOf(alice.address);
			const bob_balance_before = await gbyte_contract.balanceOf(bob.address);
			const nft_balance_before = await gbyte_contract.balanceOf(nft_contract.address);
			expect(nft_balance_before).to.eq(0)
			await expect(nft_contract.connect(bob).buy(1, price)).to.emit(nft_contract, "Bought").withArgs(1, bob.address, alice.address, price);
			const alice_balance_after = await gbyte_contract.balanceOf(alice.address);
			const bob_balance_after = await gbyte_contract.balanceOf(bob.address);
			const nft_balance_after = await gbyte_contract.balanceOf(nft_contract.address);
			expect(alice_balance_after).to.eq(alice_balance_before.add(price))
			expect(bob_balance_after).to.eq(bob_balance_before.sub(price).sub(fee))
			expect(nft_balance_after).to.eq(fee)

			const sell_orders = await nft_contract.getSellOrders();
			expect(sell_orders.length).to.eq(0);

			expect(await nft_contract.ownerOf(1)).eq(bob.address)
		});

		it("Charlie creates an order to buy a loan", async function () {
			await expect(gbyte_contract.connect(charlie).approve(nft_contract.address, BigNumber.from(2).pow(256).sub(1))).not.to.be.reverted;
			const charlie_balance_before = await gbyte_contract.balanceOf(charlie.address);
			const nft_balance_before = await gbyte_contract.balanceOf(nft_contract.address);
			const amount = parseEther('2.1')
			const strike_price = parseEther('1').div(1000).mul(99).div(100)
			const hedge_price = parseEther('1').div(1000).div(10) // 0.00001

			const HedgePriceSampleFactory = await ethers.getContractFactory("HedgePriceSample");
			const hedge_price_contract = await HedgePriceSampleFactory.deploy();
			console.log(`deployed hedge price contract at`, hedge_price_contract.address);
			const contract_hedge_price = parseEther('2').div(1000).div(10) // 0.00002

			await expect(nft_contract.connect(charlie).createBuyOrder(amount, strike_price, hedge_price, AddressZero, [])).to.emit(nft_contract, "NewBuyOrder").withArgs(1, charlie.address, amount, strike_price, hedge_price, AddressZero, "0x", hedge_price);
			const charlie_balance_after = await gbyte_contract.balanceOf(charlie.address);
			const nft_balance_after = await gbyte_contract.balanceOf(nft_contract.address);
			expect(charlie_balance_after).to.eq(charlie_balance_before.sub(amount))
			expect(nft_balance_after).to.eq(nft_balance_before.add(amount))

			let buy_orders = await nft_contract.getBuyOrders();
			expect(buy_orders.length).to.eq(1);
			expect(buy_orders[0].user).to.eq(charlie.address);
			expect(buy_orders[0].buy_order_id).to.eq(1);
			expect(buy_orders[0].amount).to.eq(amount);
			expect(buy_orders[0].strike_price).to.eq(strike_price);
			expect(buy_orders[0].hedge_price).to.eq(hedge_price);
			expect(buy_orders[0].price_contract).to.eq(AddressZero);
			expect(buy_orders[0].current_hedge_price).to.eq(hedge_price);

			// cancel
			await expect(nft_contract.connect(charlie).cancelBuyOrder(1)).to.emit(nft_contract, "CanceledBuyOrder").withArgs(1, charlie.address, amount, strike_price, hedge_price, AddressZero, "0x");
			buy_orders = await nft_contract.getBuyOrders();
			expect(buy_orders.length).to.eq(0);
			expect(await gbyte_contract.balanceOf(charlie.address)).to.eq(charlie_balance_before)
			expect(await gbyte_contract.balanceOf(nft_contract.address)).to.eq(nft_balance_before)
			expect(await nft_contract.getCountReleasedIds()).to.eq(1)
			expect(await nft_contract.released_buy_order_ids(0)).to.eq(1)

			// place the order again, now with price_contract
			await expect(nft_contract.connect(charlie).createBuyOrder(amount, strike_price, 0, hedge_price_contract.address, [])).to.emit(nft_contract, "NewBuyOrder").withArgs(1, charlie.address, amount, strike_price, 0, hedge_price_contract.address, "0x", contract_hedge_price);
			buy_orders = await nft_contract.getBuyOrders();
			expect(buy_orders.length).to.eq(1);
			expect(buy_orders[0].hedge_price).to.eq(0);
			expect(buy_orders[0].price_contract).to.eq(hedge_price_contract.address);
			expect(buy_orders[0].current_hedge_price).to.eq(contract_hedge_price);

			expect(await gbyte_contract.balanceOf(charlie.address)).to.eq(charlie_balance_after)
			expect(await gbyte_contract.balanceOf(nft_contract.address)).to.eq(nft_balance_after)
			expect(await nft_contract.getCountReleasedIds()).to.eq(0)
		});

		it("Bob sells the loan to Charlie", async function () {
			const hedge_price = parseEther('2').div(1000).div(10) // 0.00002
			const amount = parseEther("10");
			const loan_amount = amount.mul(1000);
			const interest = loan_amount.mul(2 * 3600).div(24 * 3600 * 365).div(100); // total charged interest in 2 hours (1% p.a.)
			const current_loan_amount = loan_amount.add(interest)
			const price = hedge_price.mul(current_loan_amount).div(parseEther('1'))
			const fee = price.div(500) // 0.2%

			const bob_balance_before = await gbyte_contract.balanceOf(bob.address);
			const nft_balance_before = await gbyte_contract.balanceOf(nft_contract.address);

			await expect(nft_contract.connect(bob).sell(1, 1, price)).to.emit(nft_contract, "Sold").withArgs(1, 1, charlie.address, bob.address, anyValue);

			const bob_balance_after = await gbyte_contract.balanceOf(bob.address);
			const nft_balance_after = await gbyte_contract.balanceOf(nft_contract.address);
			expect(bob_balance_after).to.be.closeTo(bob_balance_before.add(price).sub(fee), fee.div(1000))
			expect(nft_balance_after).to.be.closeTo(nft_balance_before.sub(price).add(fee), fee.div(1000))

			expect(await nft_contract.ownerOf(1)).to.eq(charlie.address)

			const buy_orders = await nft_contract.getBuyOrders();
			expect(buy_orders.length).to.eq(1);
			expect(buy_orders[0].amount).to.be.closeTo(parseEther('2.1').sub(price), 1e14);
		});

		it("Charlie repays the loan", async function () {
			await time.increase(365 * 24 * 3600 - 2 * 3600);
			await printOraclePrices();
			const current_price = await oracle_contract.getCurrentPrice();

			const amount = parseEther("10");
			const loan_amount = amount.mul(1000).mul(101).div(100);
			expect(await line_contract.getLoanDue(1)).to.be.closeTo(loan_amount, 4e14);

			// alice sends her LINE tokens to Charlie, so that he can repay the loan
			await expect(line_contract.connect(alice).transfer(charlie.address, parseEther('9').mul(1000))).not.to.be.reverted
			
			// take another loan to pay interest for the 1st one
			const amount2 = parseEther("3");
			const loan_amount2 = amount2.mul(parseEther('1')).div(current_price);
			const net_loan_amount2 = loan_amount2.sub(loan_amount2.mul(200).div(10000));
			await expect(gbyte_contract.connect(charlie).approve(line_contract.address, BigNumber.from(2).pow(256).sub(1))).not.to.be.reverted;
			await expect(line_contract.connect(charlie).borrow(amount2))
				.to.emit(line_contract, "NewLoan").withArgs(2, charlie.address, amount2, loan_amount2, net_loan_amount2, anyValue)
			expect(await line_contract.getLoanDue(2)).to.be.closeTo(loan_amount2, 1);
			expect(await nft_contract.balanceOf(charlie.address)).to.eq(2)
			expect(await nft_contract.ownerOf(2)).to.eq(charlie.address)
			const loans = await nft_contract.getAllActiveLoans()
			const charlie_loans = await nft_contract.getAllActiveLoansByOwner(charlie.address)
			expect(loans.length).to.eq(2)
			expect(charlie_loans.length).to.eq(2)
			expect(loans[1].collateral_amount).to.eq(amount2)
			expect(loans[1].loan_amount).to.eq(loan_amount2)
			expect(loans[1].initial_owner).to.eq(charlie.address)

			await expect(line_contract.connect(charlie).repay(1))
				.to.emit(line_contract, "Repaid").withArgs(1, charlie.address, amount, anyValue, anyValue)
			
			const loans_after = await nft_contract.getAllActiveLoans()
			const charlie_loans_after = await nft_contract.getAllActiveLoansByOwner(charlie.address)
			expect(loans_after.length).to.eq(1)
			expect(charlie_loans_after.length).to.eq(1)
			expect(loans_after[0].collateral_amount).to.eq(amount2)

			const sell_orders = await nft_contract.getSellOrders();
			expect(sell_orders.length).to.eq(0);
		})

	});

});
