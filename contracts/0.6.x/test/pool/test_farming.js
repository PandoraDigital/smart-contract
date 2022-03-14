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

describe("Farming", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.ERC20 = await ethers.getContractFactory('MockERC20');
        this.Minter = await ethers.getContractFactory('MockMinter');
        this.Farming = await ethers.getContractFactory('Farming');
    });

    beforeEach(async () => {
        resetHardhat();
        this.tokenReward = await this.ERC20.deploy('tokenReward', 'TKR', this.wallet[0].address, 0);
        this.tokenDeposit = await this.ERC20.deploy('tokenDeposit', 'TKD', this.wallet[0].address, 0);
        this.tokenDeposit1 = await this.ERC20.deploy('tokenDeposit1', 'TKD1', this.wallet[0].address, 0);
        this.minter = await this.Minter.deploy(this.tokenReward.address);
        this.farming = await this.Farming.deploy(this.minter.address);
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

    it("Deploy farming", async () => {

    });

    it("Add and set pool", async () => {
        let tx = await this.farming.add(100, this.tokenDeposit.address, utils.AddressZero, false);
        tx = await this.farming.add(200, this.tokenDeposit1.address, utils.AddressZero, false);
        expect((await this.farming.poolLength()).toString()).to.equal('2');
        expect((await this.farming.totalAllocPoint()).toString()).to.equal('300');
        expect((await this.farming.poolInfo(0)).allocPoint.toString()).to.equal('100');
        expect((await this.farming.poolInfo(1)).allocPoint.toString()).to.equal('200');

        //update pool
        tx = await this.farming.set(0, 300, utils.AddressZero, false);
        expect((await this.farming.poolInfo(0)).allocPoint.toString()).to.equal('300');
        expect((await this.farming.totalAllocPoint()).toString()).to.equal('500');
    });

    it("Deposit, Withdraw and Harvest", async () => {
        let tx = await this.farming.add(100, this.tokenDeposit.address, utils.AddressZero, false);
        tx = await this.farming.add(200, this.tokenDeposit1.address, utils.AddressZero, false);
        tx = await this.farming.setRewardPerBlock(parseUnits(utils.RewardPerBlock, '18'));

        //deposit
        tx = await this.farming.connect(this.wallet[1]).deposit(0, parseUnits('1000','18'), this.wallet[1].address);
        tx = await this.farming.connect(this.wallet[2]).deposit(0, parseUnits('2000','18'), this.wallet[2].address);
        tx = await this.farming.connect(this.wallet[3]).deposit(1, parseUnits('2000','18'), this.wallet[3].address);
        tx = await this.farming.connect(this.wallet[4]).deposit(1, parseUnits('3000','18'), this.wallet[4].address);

        //pending reward
        let reward1 = await this.farming.pendingReward(0, this.wallet[2].address);
        let userInfo = await this.farming.userInfo(0, this.wallet[2].address);
        expect(reward1.toString()).to.equal('3483333332000000000');
        expect(userInfo.amount.toString()).to.equal('2000000000000000000000');
        expect(userInfo.rewardDebt.toString()).to.equal('5225000000000000000');
        //mine blocks
        await mineBlocks(10);
        await this.farming.massUpdatePools();
        reward1 = await this.farming.pendingReward(0, this.wallet[2].address);
        userInfo = await this.farming.userInfo(0, this.wallet[2].address);
        expect(reward1.toString()).to.equal('22641666666000000000');
        expect(userInfo.amount.toString()).to.equal('2000000000000000000000');
        expect(userInfo.rewardDebt.toString()).to.equal('5225000000000000000');

        //harvest
        tx = await this.farming.connect(this.wallet[2]).harvest(0, this.wallet[2].address);
        let balanceReward = await this.tokenReward.balanceOf(this.wallet[2].address);
        expect(balanceReward.toString()).to.equal("24383333332000000000");
        let userInfoAfter = await this.farming.userInfo(0, this.wallet[2].address);
        expect(userInfoAfter.rewardDebt.sub(userInfo.rewardDebt).toString()).to.equal(balanceReward.toString());

        //withdraw
        tx = await this.farming.connect(this.wallet[2]).withdraw(0, parseUnits('1000','18'), this.wallet[2].address);
        userInfo = await this.farming.userInfo(0, this.wallet[2].address);
        expect(userInfo.amount.toString()).to.equal('1000000000000000000000');
        expect(userInfo.rewardDebt.toString()).to.equal('13933333333000000000');

        //withdraw and harvest
        await this.farming.massUpdatePools();
        userInfo = await this.farming.userInfo(1, this.wallet[3].address);
        tx = await this.farming.connect(this.wallet[3]).withdrawAndHarvest(1, parseUnits('1000','18'), this.wallet[3].address);
        userInfoAfter = await this.farming.userInfo(1, this.wallet[3].address);
        balanceReward = await this.tokenReward.balanceOf(this.wallet[3].address);
        expect(balanceReward.toString()).to.equal("36575000000000000000");
        expect(userInfoAfter.amount.toString()).to.equal('1000000000000000000000');
        expect(userInfoAfter.rewardDebt.toString()).to.equal('18287500000000000000');

    });
})