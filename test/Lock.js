const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const ADDRESSES = require("../scripts/constants");
const { expect } = require("chai");
const hre = require("hardhat");
const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("Testing staking", function () {
  async function deployContract() {
    const [owner, otherAccount] = await hre.ethers.getSigners();

    const budsDeploy = await hre.ethers.deployContract("BudsToken", [
      "Buds Token",
      "BUDS",
      ADDRESSES.bscTestnet.connectorAddress,
      ADDRESSES.bscTestnet.zetaTokenAddress,
      ADDRESSES.bscTestnet.zetaConsumerAddress,
    ]);

    const farmerDeploy = await hre.ethers.deployContract("Farmer", [
      ADDRESSES.bscTestnet.connectorAddress,
      ADDRESSES.bscTestnet.zetaTokenAddress,
      ADDRESSES.bscTestnet.zetaConsumerAddress,
      true,
    ]);

    const stakingContract = await hre.ethers.deployContract("Stake", [
      budsDeploy.target,
      farmerDeploy.target,
    ]);

    return { budsDeploy, farmerDeploy, stakingContract, owner, otherAccount };
  }

  describe("Satking contract Deployment", function () {
    it("Should set the buds address", async function () {
      const { stakingContract, budsDeploy } = await loadFixture(deployContract);

      expect(await stakingContract.getbudsAddress()).to.equal(
        budsDeploy.target
      );
    });

    it("Should set the farmer address", async function () {
      const { stakingContract, farmerDeploy } = await loadFixture(
        deployContract
      );

      expect(await stakingContract.getFarmerAddress()).to.equal(
        farmerDeploy.target
      );
    });
  });
});
