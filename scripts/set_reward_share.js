// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
require('dotenv').config();
const lineJson = require('../artifacts/contracts/Line.sol/Line.json');

const line_address = process.env.testnet ? '0xC7eF6c6C211071ffBD03dfD418E5bE589F1975Ee' : '0x31f8d38df6514b6cc3C360ACE3a2EFA7496214f6'; // Polygon testnet, Kava mainnet
//const token_address = '0x0bA1f827D2524a2ef6ce65129F63DEad622E75E3'; // LINK
//const token_address = '0xFb1Efb5FD9dfb72f40B81bC5aa0e15d616BA8831'; // Equilibre LINE-GBYTE
const token_address = '0xb253c4f9b615C20D9DE12bF317c71f896eb361A7'; // Equilibre LINE-USDT
const share = 5000; // out of 10000

async function main() {
	const [owner] = await hre.ethers.getSigners();

	console.log("Working with the account:", owner.address);
	console.log("Account balance:", hre.ethers.utils.formatEther(await owner.getBalance()));

	const line_contract = new ethers.Contract(line_address, lineJson.abi, owner);
	console.log(`using LINE contract at`, line_contract.address);
	const res = await line_contract.setRewardShare(token_address, share);
	console.log(res);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
