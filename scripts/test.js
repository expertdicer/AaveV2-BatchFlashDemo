const hre = require("hardhat");

async function getMockPriceOracle(reserveAssets) {

    const PriceOracle = await hre.ethers.getContractFactory("HardhatOracle");
    var assets = [];
    var sources = [];
    var fallbackOracle = "0x96e7fe3b8b0De79cD55Bf23ef476B52AfEF082De";
    var weth = "0x96e7fe3b8b0De79cD55Bf23ef476B52AfEF082De";
    var priceOracle = await PriceOracle.deploy(assets, sources, fallbackOracle, weth);
    await priceOracle.deployed();
    return priceOracle;
}

module.exports = {
    getMockPriceOracle
};


async function main() {

    var networkName = hre.network.name;

    const BatchFlashDemo = await hre.ethers.getContractFactory("BatchFlashDemo");
    var batchFlashDemo = await BatchFlashDemo.deploy(assets, sources, fallbackOracle, weth);
    await batchFlashDemo.deployed();

}



// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });