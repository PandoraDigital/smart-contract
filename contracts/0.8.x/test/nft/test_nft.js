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

describe("PandoBox and PandoBot", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.DroidBot = await ethers.getContractFactory('DroidBot');
        this.PandoBox = await ethers.getContractFactory('PandoBox');
        // this.Minter = await ethers.getContractFactory('Minter');
    })

    beforeEach( async () => {
        let latestBlock = (await ethers.provider.getBlock('latest')).number;
        this.droidBot = await this.DroidBot.deploy("this is uri");
        this.pandoBox = await this.PandoBox.deploy("this is uri");
    });

    it("Deploy nft and set minter", async () => {
        await this.droidBot.addMinter(this.wallet[0].address);
        await this.pandoBox.addMinter(this.wallet[0].address);
        expect((await this.droidBot.isMinter(this.wallet[0].address))).to.equal(true);
        expect((await this.pandoBox.isMinter(this.wallet[0].address))).to.equal(true);
    });

    it("Create Box and Bot", async () => {
        await this.droidBot.addMinter(this.wallet[0].address);
        await this.pandoBox.addMinter(this.wallet[0].address);

        //pando box
        let tx = await this.pandoBox.create(this.wallet[1].address, 1);
        expect((await this.pandoBox.totalSupply()).toString()).to.equal('1');
        let info = await this.pandoBox.nftInfo(1);
        expect(info.level.toString()).to.equal('1');

        tx = await this.droidBot.create(this.wallet[1].address, 9, 10000);
        expect((await this.droidBot.totalSupply()).toString()).to.equal('1');
        info = await this.droidBot.nftInfo(1);
        expect(info.level.toString()).to.equal('9');
        expect(info.power.toString()).to.equal('10000');
    });

    it("Burn NFT", async () => {
        await this.droidBot.addMinter(this.wallet[0].address);
        await this.pandoBox.addMinter(this.wallet[0].address);
        let tx = await this.pandoBox.create(this.wallet[1].address, 1);
        tx = await this.droidBot.create(this.wallet[1].address, 9, 10000);

        await this.pandoBox.connect(this.wallet[1]).burn(1);
        await this.droidBot.connect(this.wallet[1]).burn(1);
        expect((await this.pandoBox.totalSupply()).toString()).to.equal('1');
        expect((await this.droidBot.totalSupply()).toString()).to.equal('1');
    });
});