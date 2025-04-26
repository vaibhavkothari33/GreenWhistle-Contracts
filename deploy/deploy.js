// deploy.js - Deployment script for GreenWhistle Game Contracts
const { ethers } = require("hardhat");

async function main() {
  console.log("Starting deployment of GreenWhistle Game Contracts...");

  // Get the contract factories
  const GameToken = await ethers.getContractFactory("GameToken");
  const QuestCertificateNFT = await ethers.getContractFactory("QuestCertificateNFT");
  const MarketplaceV2 = await ethers.getContractFactory("MarketplaceV2");

  // Get the deployer account
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying contracts with account: ${deployer.address}`);
  
  // Display account balance
  const balance = await deployer.getBalance();
  console.log(`Account balance: ${ethers.utils.formatEther(balance)} ETH`);

  // Deploy GameToken first
  console.log("Deploying GameToken...");
  const gameToken = await GameToken.deploy();
  await gameToken.deployed();
  console.log(`GameToken deployed at: ${gameToken.address}`);

  // Deploy QuestCertificateNFT
  console.log("Deploying QuestCertificateNFT...");
  const questCertificate = await QuestCertificateNFT.deploy();
  await questCertificate.deployed();
  console.log(`QuestCertificateNFT deployed at: ${questCertificate.address}`);

  // Create a treasury address (in production, this should be a secure multisig)
  const treasuryAddress = deployer.address; 
  console.log(`Using treasury address: ${treasuryAddress}`);

  // Deploy MarketplaceV2 with GameToken address and treasury
  console.log("Deploying MarketplaceV2...");
  const marketplace = await MarketplaceV2.deploy(gameToken.address, treasuryAddress);
  await marketplace.deployed();
  console.log(`MarketplaceV2 deployed at: ${marketplace.address}`);

  // Transfer some tokens to the marketplace for liquidity (optional)
  const initialMarketplaceFunding = ethers.utils.parseEther("100000"); // 100,000 tokens
  console.log(`Transferring ${ethers.utils.formatEther(initialMarketplaceFunding)} tokens to marketplace for liquidity...`);
  await gameToken.transfer(marketplace.address, initialMarketplaceFunding);

  // Verify contracts on Etherscan (if on a supported network)
  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("Waiting for block confirmations...");
    // Wait for 5 block confirmations to ensure deployment is confirmed
    await gameToken.deployTransaction.wait(5);
    await questCertificate.deployTransaction.wait(5);
    await marketplace.deployTransaction.wait(5);

    console.log("Verifying contracts on Etherscan...");
    try {
      await hre.run("verify:verify", {
        address: gameToken.address,
        constructorArguments: [],
      });

      await hre.run("verify:verify", {
        address: questCertificate.address,
        constructorArguments: [],
      });

      await hre.run("verify:verify", {
        address: marketplace.address,
        constructorArguments: [gameToken.address, treasuryAddress],
      });
    } catch (error) {
      console.error("Error verifying contracts:", error);
    }
  }

  // Log all deployed contract addresses for easy reference
  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log(`GameToken (GWT): ${gameToken.address}`);
  console.log(`QuestCertificateNFT (GWQC): ${questCertificate.address}`);
  console.log(`MarketplaceV2: ${marketplace.address}`);
  console.log(`Treasury: ${treasuryAddress}`);
  console.log("\nDeployment complete!");
}

// Handle errors
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });