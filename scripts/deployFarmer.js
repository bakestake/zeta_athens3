const hre = require("hardhat");
const ADDRESSES = require("./constants");
//goerli - 0x234A43F634237051a6401aA4Fe0f18334eD3D581
//mumbai -
//bscTestnet -
async function main() {
  const lock = await hre.ethers.deployContract("Farmer", [
    ADDRESSES.bscTestnet.connectorAddress,
    ADDRESSES.bscTestnet.zetaTokenAddress,
    ADDRESSES.bscTestnet.zetaConsumerAddress,
    true,
  ]);

  await lock.waitForDeployment();

  console.log(`Farmer token deployed to ${lock.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
