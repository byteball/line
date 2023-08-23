// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const loanJson = require('../artifacts/contracts/LoanNFT.sol/LoanNFT.json');

const loan_address = '0x37ec92963660A6d98bE0aE2A7Adf8e0A8c0a0B5F';
const base_uri = 'https://linetoken.org/meta/';

async function main() {
	const [owner] = await hre.ethers.getSigners();

	console.log("Working with the account:", owner.address);
	console.log("Account balance:", hre.ethers.utils.formatEther(await owner.getBalance()));

	const loan_contract = new ethers.Contract(loan_address, loanJson.abi, owner);
	console.log(`using LoanNFT contract at`, loan_contract.address);
	const res = await loan_contract.setBaseUri(base_uri);
	console.log(res);
//	const uri = await loan_contract.tokenURI(3);
//	console.log(uri);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
