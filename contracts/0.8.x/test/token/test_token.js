const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const {BigNumber} = require("ethers");
const {parseUnits} = require("ethers/lib/utils");
const utils = require("../utils/utilities");


const mineBlocks = async (count) => {
    for(let i = 0; i < count; i++) {
        await ethers.provider.send('evm_mine');
    }
}

const timeTravel = async (seconds) => {
    await ethers.provider.send('evm_setNextBlockTimestamp', [seconds]);
    await ethers.provider.send('evm_mine');
}

const resetHardhat = async () =>{
    await ethers.provider.send('hardhat_reset');
}

describe("Pandora tokens", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.PandoraSpirit = await ethers.getContractFactory('PandoraSpirit');
        this.Pandorium = await ethers.getContractFactory('Pandorium');
        this.Minter = await ethers.getContractFactory('Minter');
    })

    beforeEach( async () => {
        this.psr = await this.PandoraSpirit.deploy(parseUnits('10000000', '18'), this.wallet[0].address);
        this.pan = await this.Pandorium.deploy();
        let latestBlock = (await ethers.provider.getBlock('latest')).number;
        this.minter = await this.Minter.deploy(this.wallet[0].address, this.pan.address, parseUnits(utils.PAN_PER_BLOCK, '18'), latestBlock);
    })

    it("Pandora Spirit", async () => {
        let balance = await this.psr.balanceOf(this.wallet[0].address);
        expect(balance.toString()).to.equal(parseUnits('10000000', '18'));
    });

    it("Pandorium", async () => {
        let balance = await this.pan.balanceOf(this.wallet[0].address);
        expect(balance.toString()).to.equal(parseUnits('0', '18'));

        //add minter
        await this.pan.addMinter(this.minter.address);

        //time skip
        await mineBlocks(20);
        await this.minter.update();

        //check balance
        balance = await this.pan.balanceOf(this.minter.address);
        expect(balance.toString()).to.equal(parseUnits('517.5', '18'));

        balance = await this.pan.balanceOf(this.wallet[0].address);
        expect(balance.toString()).to.equal(parseUnits('57.5', '18'));


    });
});