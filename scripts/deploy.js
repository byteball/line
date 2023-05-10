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
//const GBYTE_ADDRESS = process.env.testnet ? '0x01d040cfA47C3B60289c1f3a97Dce039445BFCAf' : '0xeb34De0C4B2955CE0ff1526CDf735c9E6d249D09'; // BSC
//const GBYTE_ADDRESS = process.env.testnet ? '0xeA9E7c046c6E4635F9A71836fF023c8f45948433' : '0xAB5F7a0e20b0d056Aed4Aa4528C78da45BE7308b'; // Polygon
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

//	const hpFactory = await hre.ethers.getContractFactory("HedgePriceSample");
//	const hp_contract = await hpFactory.deploy();
//	console.log(`deployed HedgePrice at`, hp_contract.address);
//	await hp_contract.deployed();

//	const nftFactory = await hre.ethers.getContractFactory("LoanNFT");
//	const nft_contract = await nftFactory.deploy("NFT", "NFT");
//	console.log(`deployed LoanNFT at`, nft_contract.address);
//	await nft_contract.deployed();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
	console.error(error);
	process.exitCode = 1;
});
