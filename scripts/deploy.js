// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const { reset } = require("@nomicfoundation/hardhat-network-helpers");
require('dotenv').config();

const GBYTE_ADDRESS = process.env.testnet ? '0xe1C41Aae8b62caF493908ca63990f019c0786121' : '0x0b93109d05Ef330acD2c75148891cc61D20C3EF1';
const rpc = process.env.testnet ? 'https://evm.testnet.kava.io' : 'https://evm.kava.io';

async function main() {
//	await reset(rpc);
	const [deployer] = await hre.ethers.getSigners();

	console.log("Deploying contracts with the account:", deployer.address);

	console.log("Account balance:", hre.ethers.utils.formatEther(await deployer.getBalance()));

	const LineFactory = await hre.ethers.getContractFactory("Line");
	const line_contract = await LineFactory.deploy(GBYTE_ADDRESS, "LINE Token", "LINE");
	console.log(`deployed LINE at`, line_contract.address);

	await line_contract.deployed();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
