const hre = require("hardhat");
const ADDRESSES = require("./constants");

//goerli - 0x8465744Db9B8BAC5Fa51AF8B17B1a121748e3aA3
//mumbai- 0xC2dcaa45AEF927b1CCB04793B230780152838B42
//bscTestnet-

async function main() {
  const lock = await hre.ethers.deployContract("BudsToken", [
    "Buds Token",
    "BUDS",
    ADDRESSES.bscTestnet.connectorAddress,
    ADDRESSES.bscTestnet.zetaTokenAddress,
    ADDRESSES.bscTestnet.zetaConsumerAddress,
  ]);

  await lock.waitForDeployment();

  console.log(`Buds token deployed to ${lock.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
