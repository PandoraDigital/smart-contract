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

describe("NFT marketplace", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.MockERC20 = await ethers.getContractFactory('MockERC20');
        this.DroidBot = await ethers.getContractFactory('DroidBot');
        this.PandoBox = await ethers.getContractFactory('PandoBox');
        this.NftMarket = await ethers.getContractFactory('NftMarket');
    })

    beforeEach( async () => {
        resetHardhat();
        this.droidBot = await this.DroidBot.deploy("this is uri");
        this.pandoBox = await this.PandoBox.deploy("this is uri");
        this.token = await this.MockERC20.deploy("mockerc20", 'ERC20',this.wallet[0].address, 0);
        this.market = await this.NftMarket.deploy([this.droidBot.address, this.pandoBox.address], [this.token.address],this.wallet[0].address);
        await this.droidBot.addMinter(this.wallet[0].address);
        await this.pandoBox.addMinter(this.wallet[0].address);
        for(let i = 0; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            await this.token.connect(user).mint(user.address, parseUnits('5000000','18'));
            await this.token.connect(user).approve(this.market.address, parseUnits('5000000','18'));
            await this.droidBot.connect(user).setApprovalForAll(this.market.address, true);
            await this.pandoBox.connect(user).setApprovalForAll(this.market.address, true);
            await this.pandoBox.create(user.address, 1);
            await this.droidBot.create(user.address, 9, 10000);
        }
    });

    it("Deploy marketplace", async () => {

    });

    it("Ask and Buy", async () => {
        //create ask
        let tx = await this.market.connect(this.wallet[10]).setSalePrice(this.droidBot.address, this.token.address, 11, parseUnits('1000','18'));

        //buy
        tx = await this.market.connect(this.wallet[11]).buy(this.droidBot.address, 11);
        expect(await this.droidBot.ownerOf(11)).to.equal(this.wallet[11].address);
        expect((await this.token.balanceOf(this.wallet[10].address)).toString()).to.equal(parseUnits('5000950','18'));
        expect((await this.token.balanceOf(this.wallet[11].address)).toString()).to.equal(parseUnits('4999000','18'));
    });

    it("Ask and bid", async () => {
        //create ask
        let tx = await this.market.connect(this.wallet[10]).setSalePrice(this.droidBot.address, this.token.address, 11, parseUnits('10000','18'));

        // bid: 1
        tx = await this.market.connect(this.wallet[11]).bid(this.droidBot.address, this.token.address, 11, parseUnits('5000','18'), 0);

        // update bid : 2
        tx = await this.market.connect(this.wallet[11]).bid(this.droidBot.address, this.token.address, 11, parseUnits('6000','18'), 1);

        // bid : 3
        tx = await this.market.connect(this.wallet[12]).bid(this.droidBot.address, this.token.address, 11, parseUnits('7000','18'), 0);
        let totalBids = await this.market.totalBids()
        tx = await this.market.connect(this.wallet[12]).cancelBid(this.droidBot.address, 11, totalBids);

        tx = await this.market.connect(this.wallet[10]).acceptBid(this.droidBot.address, 11, 2);

        expect(await this.droidBot.ownerOf(11)).to.equal(this.wallet[11].address);
        expect((await this.token.balanceOf(this.wallet[10].address)).toString()).to.equal(parseUnits('5005700','18'));
        expect((await this.token.balanceOf(this.wallet[11].address)).toString()).to.equal(parseUnits('4994000','18'));



    });


});