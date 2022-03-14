const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const {BigNumber} = require("ethers");
const {parseUnits} = require("ethers/lib/utils");
const utils = require("../utils/utilities");



const timeTravel = async (seconds) => {
    await ethers.provider.send('evm_setNextBlockTimestamp', [seconds]);
    await ethers.provider.send('evm_mine');
}

const resetHardhat = async () =>{
    await ethers.provider.send('hardhat_reset');
}


describe.only("Swap router, factory and trading pool", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.ERC20 = await ethers.getContractFactory('MockERC20');
        this.WETH = await ethers.getContractFactory('WETH');
        this.Oracle = await ethers.getContractFactory('MockOracle');
        this.SwapFactory = await ethers.getContractFactory('SwapFactory');
        this.Router = await ethers.getContractFactory('SwapRouter');
        this.Pair = await ethers.getContractFactory('SwapPair');
        this.TradingPool = await ethers.getContractFactory('TradingPool');
        this.Minter = await ethers.getContractFactory('MockMinter');


        // console.log("factory length", await this.factory.pairCodeHash());
    });

    beforeEach(async () => {
        resetHardhat();
        this.WBNB = await this.WETH.deploy();
        this.token0 = await this.ERC20.deploy('token 0', 'TK0', this.wallet[0].address, 0);
        this.token1 = await this.ERC20.deploy('token 1', 'TK1', this.wallet[0].address, 0);
        this.tokenReward = await this.ERC20.deploy('tokenReward', 'TKR', this.wallet[0].address, 0);
        this.factory = await this.SwapFactory.deploy();
        this.router = await this.Router.deploy(this.factory.address, this.WBNB.address);
        this.minter = await this.Minter.deploy(this.tokenReward.address);
        this.tradingPool = await this.TradingPool.deploy(this.minter.address, this.router.address, this.factory.address);
        this.oracle = await this.Oracle.deploy();
        for(let i = 0; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            // await this.WBNB.connect(user).mint(user.address, parseUnits('5000000','18'));
            await this.token0.connect(user).mint(user.address, parseUnits('5000000','18'));
            await this.token1.connect(user).mint(user.address, parseUnits('5000000','18'));
            await this.WBNB.connect(user).approve(this.router.address, parseUnits('5000000','18'));
            await this.token0.connect(user).approve(this.router.address, parseUnits('5000000','18'));
            await this.token1.connect(user).approve(this.router.address, parseUnits('5000000','18'));
        }
        await this.router.setTradingPool(this.tradingPool.address);
    });
    it("Deploy swap", async () => {

    });

    it("Add liquidity, swap, remove liquidity and earn hash rate trading pool", async () => {
        let create2Address = utils.getCreate2Address(this.factory.address,[this.token0.address, this.token1.address], this.Pair.bytecode);
        //setting trading pool
        await this.tradingPool.add(create2Address, 100);
        await this.tradingPool.setOracle(this.token0.address, this.oracle.address);
        await this.tradingPool.setOracle(this.token1.address, this.oracle.address);
        await this.tradingPool.setRewardPerBlock(parseUnits('25','18'), [create2Address]);
        let tx = await this.router.connect(this.wallet[1]).addLiquidity(
            this.token0.address,
            this.token1.address,
            parseUnits('1000000','18'),
            parseUnits('1000000','18'),
            0,
            0,
            this.wallet[1].address,
            99999999999
        );
        let pairAddress = await this.factory.getPair(this.token0.address, this.token1.address);

        //compare address pair
        expect(pairAddress).to.eq(create2Address);
        expect(await this.factory.allPairs(0)).to.eq(create2Address)
        expect((await this.factory.allPairsLength()).toNumber()).to.equal(1);

        //check balance LP-token
        const balance = await this.Pair.connect(this.wallet[1]).attach(pairAddress).balanceOf(this.wallet[1].address);
        expect(balance.toString()).to.equal("999999999999999999999000");

        //swap token0 for token1
        tx = await this.router.connect(this.wallet[3]).swapExactTokensForTokens('100000000000000000000000','0',[this.token0.address, this.token1.address], this.wallet[3].address, 99999999999);
        let token0Balance = await this.token0.balanceOf(this.wallet[3].address);
        let token1Balance = await this.token1.balanceOf(this.wallet[3].address);
        expect(token0Balance.toString()).to.equal("4900000000000000000000000");
        expect(token1Balance.toString()).to.equal("5090661089388014913158134");

        //swap token1 for token0
        tx = await this.router.connect(this.wallet[4]).swapExactTokensForTokens('100000000000000000000000','0',[this.token1.address, this.token0.address], this.wallet[3].address, 99999999999);
        let token0Balance1 = await this.token0.balanceOf(this.wallet[3].address);
        let token1Balance1 = await this.token1.balanceOf(this.wallet[3].address);
        expect(token0Balance1.toString()).to.equal("5008687582655742007302566");
        expect(token1Balance1.toString()).to.equal("5090661089388014913158134");

        //approve pair token
        tx = await this.Pair.connect(this.wallet[1]).attach(pairAddress).approve(this.router.address, balance);

        // remove liquidity
        tx = await this.router.connect(this.wallet[1]).removeLiquidity(
            this.token0.address,
            this.token1.address,
            balance,
            0,
            0,
            this.wallet[1].address,
            99999999999
        );
        const balanceAfter = await this.Pair.connect(this.wallet[1]).attach(pairAddress).balanceOf(this.wallet[1].address);
        token0Balance = await this.token0.balanceOf(this.wallet[1].address);
        token1Balance = await this.token1.balanceOf(this.wallet[1].address);

        expect(token0Balance.toString()).to.equal("4991312417344257992696442");
        expect(token1Balance.toString()).to.equal("5009338910611985086840856");
        expect(balanceAfter.toString()).to.equal("0");

        let totalHashRate = await this.tradingPool.totalHashRate(create2Address);
        let userHashRate = await this.tradingPool.userHashRate(create2Address, this.wallet[3].address);
        expect(totalHashRate.toString()).to.equal('199348672043756920460700');
        expect(userHashRate.toString()).to.equal('90661089388014913158134');

        tx = await this.tradingPool.connect(this.wallet[3]).harvest(create2Address, this.wallet[3].address);
        let balanceReward = await this.tokenReward.balanceOf(this.wallet[3].address);
        expect(balanceReward.toString()).to.equal('59108989137219241611');
    });
})