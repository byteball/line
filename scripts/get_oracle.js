// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const lineJson = require('../artifacts/contracts/Line.sol/Line.json');

const line_address = '0x31f8d38df6514b6cc3C360ACE3a2EFA7496214f6';

async function main() {
	const [owner] = await hre.ethers.getSigners();

	console.log("Working with the account:", owner.address);
	console.log("Account balance:", hre.ethers.utils.formatEther(await owner.getBalance()));

	const line_contract = new ethers.Contract(line_address, lineJson.abi, owner);
	console.log(`using LINE contract at`, line_contract.address);
	const oracle = await line_contract.oracle();
	console.log(oracle);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
