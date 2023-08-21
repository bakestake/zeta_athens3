const hre = require("hardhat");

async function main() {
  const lock = await hre.ethers.deployContract("Stake", [
    "0x7aabae15a0ea088eb3affc3fbc5fdd5b074efe2e",
    "0x234A43F634237051a6401aA4Fe0f18334eD3D581",
    13700,
    30
  ]);

  await lock.waitForDeployment();

  console.log(`Staking contract deployed to ${lock.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
