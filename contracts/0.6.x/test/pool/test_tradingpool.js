const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const {BigNumber} = require("ethers");
const {parseUnits} = require("ethers/lib/utils");
const utils = require("../utils/utilities");



const timeTravel = async (seconds) => {
    await ethers.provider.send('evm_setNextBlockTimestamp', [seconds]);
    await ethers.provider.send('evm_mine');
}

const mineBlocks = async (count) => {
    for(let i = 0; i < count; i++) {
        await ethers.provider.send('evm_mine');
    }
}

const resetHardhat = async () =>{
    await ethers.provider.send('hardhat_reset');
}

describe("Trading pool", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.ERC20 = await ethers.getContractFactory('MockERC20');
        this.Minter = await ethers.getContractFactory('MockMinter');
        this.TradingPool = await ethers.getContractFactory('TradingPool');
        this.MockOracle = await ethers.getContractFactory('MockOracle');
    });

    beforeEach(async () => {
        resetHardhat();
        this.tokenReward = await this.ERC20.deploy('tokenReward', 'TKR', this.wallet[0].address, 0);
        this.tokenDeposit = await this.ERC20.deploy('tokenDeposit', 'TKD', this.wallet[0].address, 0);
        this.tokenDeposit1 = await this.ERC20.deploy('tokenDeposit1', 'TKD1', this.wallet[0].address, 0);
        this.minter = await this.Minter.deploy(this.tokenReward.address);
        this.tradingPool = await this.TradingPool.deploy(this.minter.address);
        for(let i = 0; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            // await this.tokenReward.connect(user).mint(user.address, parseUnits('5000000','18'));
            await this.tokenDeposit.connect(user).mint(user.address, parseUnits('5000000','18'));
            await this.tokenDeposit1.connect(user).mint(user.address, parseUnits('5000000','18'));
            await this.tokenReward.connect(user).approve(this.farming.address, parseUnits('5000000','18'));
            await this.tokenDeposit.connect(user).approve(this.farming.address, parseUnits('5000000','18'));
            await this.tokenDeposit1.connect(user).approve(this.farming.address, parseUnits('5000000','18'));
        }
    });

});