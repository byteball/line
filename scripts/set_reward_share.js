// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
require('dotenv').config();
const lineJson = require('../artifacts/contracts/Line.sol/Line.json');

const line_address = process.env.testnet ? '0xC7eF6c6C211071ffBD03dfD418E5bE589F1975Ee' : ''; // Polygon
const token_address = '0x326C977E6efc84E512bB9C30f76E30c160eD06FB'; // LINK
const share = 5000;

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
