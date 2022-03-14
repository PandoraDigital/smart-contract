const { expect, use} = require("chai");
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

describe.only("PandoAssembly", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.MockERC20 = await ethers.getContractFactory('MockERC20');
        this.DroidBot = await ethers.getContractFactory('DroidBot');
        this.PandoBox = await ethers.getContractFactory('PandoBox');
        this.NFTLib = await ethers.getContractFactory('NFTLib');
        this.EnumerableSet = await ethers.getContractFactory('EnumerableSet');
        this.enumerableSet = await this.EnumerableSet.deploy();
        this.nftLib = await this.NFTLib.deploy();
        this.PandoAssembly = await ethers.getContractFactory('PandoAssembly',  {
            libraries: {
                NFTLib: this.nftLib.address
            }
        });
    })

    beforeEach( async () => {
        resetHardhat();
        this.droidBot = await this.DroidBot.deploy("this is uri");
        this.token = await this.MockERC20.deploy("mockerc20", 'ERC20',this.wallet[0].address, 0);
        this.pandoAssembly = await this.PandoAssembly.deploy(this.token.address, this.droidBot.address, this.wallet[0].address);
        await this.droidBot.addMinter(this.wallet[0].address);
        for(let i = 0; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            await this.token.connect(user).mint(user.address, parseUnits('5000000','18'));
            await this.token.connect(user).approve(this.pandoAssembly.address, parseUnits('5000000','18'));
            await this.droidBot.connect(user).setApprovalForAll(this.pandoAssembly.address, true);
            await this.droidBot.create(user.address, 9, 10000);
            await this.droidBot.create(user.address, 8, 8000);
        }
    });
    it("Deploy PandoAssembly", async () => {

    });

    it("Deposit and Withdraw", async () => {
        // let tx = await this.pandoAssembly.connect(this.wallet[1]).deposit([3,4], this.wallet[1].address);
        // let userInfo = await this.pandoAssembly.info(this.wallet[1].address);
        // console.log(userInfo);
    });
});