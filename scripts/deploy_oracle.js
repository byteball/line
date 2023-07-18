// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

const pair_address = '0xFb1Efb5FD9dfb72f40B81bC5aa0e15d616BA8831';
const token_address = '0x31f8d38df6514b6cc3C360ACE3a2EFA7496214f6';

async function main() {
	const [deployer] = await hre.ethers.getSigners();

	console.log("Deploying the oracle contract with the account:", deployer.address);

	console.log("Account balance:", hre.ethers.utils.formatEther(await deployer.getBalance()));

	const factory = await hre.ethers.getContractFactory("EquilibreOracle");
	const contract = await factory.deploy(pair_address, token_address);
	console.log(`deployed oracle at`, contract.address);
	await contract.deployed();

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
