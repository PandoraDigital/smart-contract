const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");
const {BigNumber} = require("ethers");
const {parseUnits} = require("ethers/lib/utils");



const timeTravel = async (seconds) => {
    await ethers.provider.send('evm_setNextBlockTimestamp', [seconds]);
    await ethers.provider.send('evm_mine');
}

const resetHardhat = async () =>{
    await ethers.provider.send('hardhat_reset');
}

const setting = async (contractPsr, contractPresale, _whitelistSlot, _waitingListSlot, _start, _duration, _numerator, _denominator, _maxBuy) => {
    const whitelistSlot = BigNumber.from(_whitelistSlot);
    const waitingListSlot = _waitingListSlot;
    const start = Math.floor(Date.now() / 1000) + 3600;
    const duration = _duration;
    const numerator = _numerator;
    const denominator = _denominator;
    const maxBuy = BigNumber.from(_maxBuy);
    const tokenApprove = whitelistSlot.mul(maxBuy).mul(BigNumber.from('1000000000000000000'));
    await contractPsr.transfer(this.presale.address, tokenApprove.toString());
    await contractPresale.settingPresale(whitelistSlot, waitingListSlot, start ,duration, numerator,denominator,maxBuy, start - 600);
}

// const registerMultiUser =


describe("Presale setting and deploy", async function () {
     before(async () => {
         this.wallet = await ethers.getSigners();
         this.USDT = await ethers.getContractFactory('MockERC20');
         this.Presale = await ethers.getContractFactory('Presale');
         this.Verifier = await ethers.getContractFactory('Verifier');
         this.PSR = await ethers.getContractFactory('PandoraSpirit');
     })

    beforeEach( async () => {
        this.usdt = await this.USDT.deploy('USDT','USDT', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.busd = await this.USDT.deploy('BUSD','BUSD', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.psr = await this.PSR.deploy('10000000000000000000000000', this.wallet[0].address);
        this.verifier = await this.Verifier.deploy(this.wallet[0].address);
        this.presale = await this.Presale.deploy(this.psr.address, this.usdt.address, this.busd.address, this.verifier.address);
        await this.presale.setOperator(this.wallet[0].address);
    })

    it("Test deployed", async  () => {
        expect(await this.presale.PandoraSpirit()).to.equal(this.psr.address);
        expect(await this.presale.USDT()).to.equal(this.usdt.address);
        expect(await this.presale.BUSD()).to.equal(this.busd.address);
        expect(await this.presale.verifier()).to.equal(this.verifier.address);
    })

    it("Test setting presale without owner call", async () => {
        const other = this.wallet[1];
        await expect(this.presale.connect(other).settingPresale(1000, 1000, Date.now(),86400, 1,1,1000, 800000)).to.be.revertedWith('Only operator role can call function');
    });

    // it("Test setting without approve transfer PSR", async () => {
    //     await expect(this.presale.settingPresale(1000, 1000, Date.now(),86400, 1,1,1000)).to.be.revertedWith('ERC20: transfer amount exceeds allowance');
    // });

    it("Test setting success", async () => {
        const whitelistSlot = BigNumber.from('1000');
        const waitingListSlot = 1000;
        const start = Math.floor(Date.now() / 1000) + 3600;
        const duration = 86400;
        const numerator = 1;
        const denominator = 1;
        const maxBuy = BigNumber.from('1000');
        const tokenApprove = whitelistSlot.mul(maxBuy).mul(BigNumber.from('1000000000000000000'));
        await this.psr.approve(this.presale.address, tokenApprove.toString());
        await this.presale.settingPresale(whitelistSlot, waitingListSlot, start ,duration, numerator,denominator,maxBuy, start - 600);
        // let balance = await this.psr.balanceOf(this.presale.address)
        // await expect(balance).to.equal(tokenApprove.toString());
        await expect(await this.presale.waitingListSlots()).to.equal(whitelistSlot.toString());
        await expect(await this.presale.whiteListSlots()).to.equal(waitingListSlot.toString());
        await expect(await this.presale.startSale()).to.equal(start.toString());
        await expect(await this.presale.duration()).to.equal(duration.toString());
        await expect(await this.presale.numerator()).to.equal(numerator.toString());
        await expect(await this.presale.denominator()).to.equal(denominator.toString());
        await expect(await this.presale.MAX_BUY_USDT()).to.equal(maxBuy.mul(BigNumber.from('1000000000000000000')).toString());
        await expect(await this.presale.MAX_BUY_PSR()).to.equal(maxBuy.mul(BigNumber.from('1000000000000000000')).mul(denominator).div(numerator).toString());
        await expect(await this.presale.totalTokensSale()).to.equal(tokenApprove.toString());
        await expect(await this.presale.remain()).to.equal(tokenApprove.toString());
    });
});

describe("Presale register and add white list", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.USDT = await ethers.getContractFactory('MockERC20');
        this.Presale = await ethers.getContractFactory('Presale');
        this.Verifier = await ethers.getContractFactory('Verifier');
        this.PSR = await ethers.getContractFactory('PandoraSpirit');
    })

    beforeEach( async () => {
        await resetHardhat();
        this.usdt = await this.USDT.deploy('USDT','USDT', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.busd = await this.USDT.deploy('BUSD','BUSD', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.psr = await this.PSR.deploy('10000000000000000000000000', this.wallet[0].address);
        this.verifier = await this.Verifier.deploy(this.wallet[0].address);
        this.presale = await this.Presale.deploy(this.psr.address, this.usdt.address, this.busd.address, this.verifier.address);
        await this.presale.setOperator(this.wallet[0].address);
    });

    it("Register before setting", async () => {
        const user = this.wallet[5];
        await this.presale.connect(user).register();
        let check = await this.presale.isRegistered(user.address);
        // console.log("list register", await this.presale.listRegister());
        expect(check).to.equal(true);
        expect(await this.presale.totalRegister()).to.equal(1);
    });

    it("Dupplicate register", async () => {
        const user = this.wallet[5];
        await this.presale.connect(user).register();
        await expect(this.presale.connect(user).register()).to.be.revertedWith('User has registered');
    });

    it("Add white list with user not register", async () => {
        const user1 = this.wallet[5];
        const user2 = this.wallet[6];
        await this.presale.connect(user1).register();
        await setting(this.psr, this.presale, 1000, 1000, 0, 86400, 1, 1, 1000);
        await expect(this.presale.addWhiteList([user2.address])).to.be.revertedWith('User not in register list');
        // await expect(this.presale.addWaitingList([user2.address])).to.be.revertedWith('User not in register list');
    });

    it("Add white list over white list slots", async () => {
        const user1 = this.wallet[5];
        const user2 = this.wallet[6];
        const user3 = this.wallet[7];
        const user4 = this.wallet[8];
        const user5 = this.wallet[9];
        await this.presale.connect(user1).register();
        await this.presale.connect(user2).register();
        await this.presale.connect(user3).register();
        await this.presale.connect(user4).register();
        await this.presale.connect(user5).register();
        await setting(this.psr, this.presale, 2, 2, 0, 86400, 1, 1, 1000);
        await expect(this.presale.addWhiteList([user2.address, user1.address, user3.address])).to.be.revertedWith('white list overflow');
        await expect(this.presale.addWaitingList([user2.address, user1.address, user3.address])).to.be.revertedWith('waiting list overflow');
    });

    it("Add white list success", async () => {
        const user1 = this.wallet[5];
        const user2 = this.wallet[6];
        const user3 = this.wallet[7];
        const user4 = this.wallet[8];
        const user5 = this.wallet[9];
        await this.presale.connect(user1).register();
        await this.presale.connect(user2).register();
        await this.presale.connect(user3).register();
        await this.presale.connect(user4).register();
        await this.presale.connect(user5).register();
        await setting(this.psr, this.presale, 2, 2, 0, 86400, 1, 1, 1000);
        await this.presale.addWhiteList([user2.address, user1.address]);
        await this.presale.addWaitingList([user3.address, user4.address]);
        await expect(await this.presale.isWhiteList(user2.address)).to.equal(true);
        await expect(await this.presale.isWhiteList(user1.address)).to.equal(true);
        await expect(await this.presale.isWaitingList(user3.address)).to.equal(true);
        await expect(await this.presale.isWaitingList(user4.address)).to.equal(true);
        await expect(await this.presale.totalWhiteList()).to.equal(2);
        await expect(await this.presale.totalWaitingList()).to.equal(2);
    });

    it("Remove element in list", async () => {
        let whiteList = [];
        let waitingList = [];
        let removeList = [];
        for(let i = 0; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            await this.presale.connect(user).register();
            if (i < 5) {
                whiteList.push(user.address);
            } else {
                waitingList.push(user.address);
            }
            if (i < 3) {
                removeList.push(user.address);
            }
        }
        console.log(whiteList.length);
        console.log(waitingList.length);
        await setting(this.psr, this.presale, 5, 15, 0, 86400, 1, 1, 1000);
        // await expect(this.presale.addWhiteList([user2.address, user1.address, user3.address])).to.be.revertedWith('white list overflow');
        await this.presale.addWhiteList(whiteList);
        await this.presale.addWaitingList(waitingList);
        let whiteListBefore = await this.presale.whiteListUser(0, 100);
        let userCheckWhiteList1 = this.wallet[0];
        let userCheckWhiteList2 = this.wallet[1];
        let userCheckWhiteList3 = this.wallet[2];
        let userCheckWaitingList1 = this.wallet[5];
        let userCheckWaitingList2 = this.wallet[6];
        let userCheckWaitingList3 = this.wallet[7];
        console.log("check white list 1 before", await this.presale.isWhiteList(userCheckWhiteList1.address));
        console.log("check white list 2 before", await this.presale.isWhiteList(userCheckWhiteList2.address));
        console.log("check white list 3 before", await this.presale.isWhiteList(userCheckWhiteList3.address));
        console.log("check waiting list before", await this.presale.isWaitingList(userCheckWaitingList1.address));
        console.log("whiteListBefore", whiteListBefore);
        await this.presale.removeUserInWhiteList(removeList);
        let whiteListAfter = await this.presale.whiteListUser(0, 100);
        console.log("check white list 1 after", await this.presale.isWhiteList(userCheckWhiteList1.address));
        console.log("check white list 2 after", await this.presale.isWhiteList(userCheckWhiteList2.address));
        console.log("check white list 3 after", await this.presale.isWhiteList(userCheckWhiteList3.address));
        console.log("check waiting list 5 after", await this.presale.isWaitingList(userCheckWaitingList1.address));
        console.log("check waiting list 6 after", await this.presale.isWaitingList(userCheckWaitingList2.address));
        console.log("check waiting list 7 after", await this.presale.isWaitingList(userCheckWaitingList3.address));
        console.log("check white list 5 after", await this.presale.isWhiteList(userCheckWaitingList1.address));
        console.log("check white list 6 after", await this.presale.isWhiteList(userCheckWaitingList2.address));
        console.log("check white list 7 after", await this.presale.isWhiteList(userCheckWaitingList3.address));

        console.log("whiteListAfter", whiteListAfter);

        // await this.presale.removeUserInWaitingList(3);
        // await this.presale.updateWaitingListQueue(user2.address, 4);
        // console.log("test index", await this.presale.waitingQueueNumber(user2.address));
        // console.log("await this.presale.totalWaitingList()", await this.presale.totalWaitingList());

    });

});

describe("Buy and commit", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.USDT = await ethers.getContractFactory('MockERC20');
        this.Presale = await ethers.getContractFactory('Presale');
        this.Verifier = await ethers.getContractFactory('Verifier');
        this.PSR = await ethers.getContractFactory('PandoraSpirit');
    });

    beforeEach( async () => {
        await resetHardhat();
        this.usdt = await this.USDT.deploy('USDT','USDT', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.busd = await this.USDT.deploy('BUSD','BUSD', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.psr = await this.PSR.deploy('10000000000000000000000000', this.wallet[0].address);
        this.verifier = await this.Verifier.deploy(this.wallet[0].address);
        this.presale = await this.Presale.deploy(this.psr.address, this.usdt.address, this.busd.address, this.verifier.address);
        await this.presale.setOperator(this.wallet[0].address);
        for(let i = 0; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            await this.presale.connect(user).register();
            await this.usdt.connect(user).mint(user.address, '5000000000000000000000');
            await this.busd.connect(user).mint(user.address, '5000000000000000000000');
            await this.usdt.connect(user).approve(this.presale.address, '5000000000000000000000');
            await this.busd.connect(user).approve(this.presale.address, '5000000000000000000000');
        }
        await setting(this.psr, this.presale, 5, 10, 0, 86400, 10, 8, 1000);
        let whiteList = [];
        let waitingList = [];
        let removeList = [];
        for(let i = 1; i <= 15; i++ ){
            if(i <= 5) {
                whiteList.push(this.wallet[i].address);
            } else {
                waitingList.push(this.wallet[i].address);
            }
            if(i <= 3) {
                removeList.push(this.wallet[i].address);
            }
        }
        console.log("removeList", removeList);
        await this.presale.addWhiteList(whiteList);
        await this.presale.addWaitingList(waitingList);
        await this.presale.removeUserInWhiteList(removeList);
    });

    it("Not white list buy", async () => {
        let user = this.wallet[19];
        let usdtAddress = this.usdt.address;
        let startSale = await this.presale.startSale();

        await timeTravel(startSale.toNumber());
        await expect(this.presale.connect(user).buy(usdtAddress, parseUnits('1000', '18'))).to.be.revertedWith('User not in white list');
        await expect(this.presale.connect(user).reserveSlot(usdtAddress, parseUnits('1000', '18'))).to.be.revertedWith('User not in waiting list');
    });

    it("Buy greater than limit", async () => {
        let userBuy = this.wallet[4];
        let userCommit = this.wallet[10];
        let usdtAddress = this.usdt.address;
        let startSale = await this.presale.startSale();
        await timeTravel(startSale.toNumber());
        await expect(this.presale.connect(userBuy).buy(usdtAddress, parseUnits('1001', '18'))).to.be.revertedWith('User buy overflow allowance');
        await expect(this.presale.connect(userCommit).reserveSlot(usdtAddress, parseUnits('1001', '18'))).to.be.revertedWith('User buy overflow allowance');
    });

    it("Buy success", async () => {
        let userBuy = this.wallet[4];
        let userCommit = this.wallet[10];
        let usdtAddress = this.usdt.address;
        let startSale = await this.presale.startSale();
        let amountBuy = parseUnits('1000', '18');
        await timeTravel(startSale.toNumber());
        await this.presale.connect(userBuy).buy(usdtAddress, parseUnits('1000', '18'));
        await this.presale.connect(userCommit).reserveSlot(usdtAddress, parseUnits('1000', '18'));
        let userData = await this.presale.userInfo(userBuy.address);
        let commitData = await this.presale.waiting(userCommit.address);
        let numerator = await this.presale.numerator();
        let denominator = await this.presale.denominator();
        let totalToken = parseUnits('1000', '18').mul(denominator).div(numerator);
        await expect(userData.totalToken.toString()).to.equal(totalToken.toString());
        await expect(userData.amountUsdt.toString()).to.equal(amountBuy.toString());
        await expect(commitData.amountUsdt.toString()).to.equal(amountBuy.toString());
    })


});


describe("Approve commit of user in waiting list", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.USDT = await ethers.getContractFactory('MockERC20');
        this.Presale = await ethers.getContractFactory('Presale');
        this.Verifier = await ethers.getContractFactory('Verifier');
        this.PSR = await ethers.getContractFactory('PandoraSpirit');
    });

    beforeEach( async () => {
        await resetHardhat();
        this.usdt = await this.USDT.deploy('USDT','USDT', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.busd = await this.USDT.deploy('BUSD','BUSD', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.psr = await this.PSR.deploy('10000000000000000000000000', this.wallet[0].address);
        this.verifier = await this.Verifier.deploy(this.wallet[0].address);
        this.presale = await this.Presale.deploy(this.psr.address, this.usdt.address, this.busd.address, this.verifier.address);
        await this.presale.setOperator(this.wallet[0].address);
        for(let i = 0; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            await this.presale.connect(user).register();
            await this.usdt.connect(user).mint(user.address, '5000000000000000000000');
            await this.busd.connect(user).mint(user.address, '5000000000000000000000');
            await this.usdt.connect(user).approve(this.presale.address, '5000000000000000000000');
            await this.busd.connect(user).approve(this.presale.address, '5000000000000000000000');
        }
        await setting(this.psr, this.presale, 5, 100, 0, 86400, 10, 8, 1000);
        let whiteList = [];
        let waitingList = [];
        for(let i = 1; i < this.wallet.length; i++ ){
            if(i <= 5) {
                whiteList.push(this.wallet[i].address);
            } else {
                waitingList.push(this.wallet[i].address);
            }
        }
        await this.presale.addWhiteList(whiteList);
        await this.presale.addWaitingList(waitingList);
        let userBuy = this.wallet[2];
        let userCommit = this.wallet[10];
        let startSale = await this.presale.startSale();
        await timeTravel(startSale.toNumber());
        await this.presale.connect(userBuy).buy(this.usdt.address, parseUnits('500', '18'));
        await this.presale.connect(userCommit).reserveSlot(this.usdt.address, parseUnits('500', '18'));
    });
    it("Call approve", async () => {
        let startSale = await this.presale.startSale();
        let duration = await this.presale.duration();
        let userCommit = this.wallet[10];
        let commitDataBefore = await this.presale.waiting(userCommit.address);
        for(let i = 6; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            await this.presale.connect(user).reserveSlot(this.usdt.address, parseUnits('1', '18'));
        }
        await timeTravel(startSale.add(duration).toNumber());
        let approve = false;
        let count = 0;
        while(!approve) {
            await this.presale.approveWaitingList(3);
            approve = await this.presale.isApprove();
            count++;
        }
        console.log(count);
        console.log(approve);


        let userData = await this.presale.userInfo(userCommit.address);
        let commitData = await this.presale.waiting(userCommit.address);
        let remain = await this.presale.remain();
        let numerator = await this.presale.numerator();
        let denominator = await this.presale.denominator();
        let totalToken = parseUnits('501', '18').mul(denominator).div(numerator);
        await expect(userData.totalToken.toString()).to.equal(totalToken.toString());
        await expect(userData.amountUsdt.toString()).to.equal(commitDataBefore.amountUsdt.add(parseUnits('1','18')).toString());
        await expect(commitData.amountUsdt.toString()).to.equal('0');
        console.log("user data", userData);
        console.log("commitData", commitData);
        console.log("commit data before", commitDataBefore);
        console.log("remain", remain);
    })
});

describe("Refund user in waiting list", async  () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.USDT = await ethers.getContractFactory('MockERC20');
        this.Presale = await ethers.getContractFactory('Presale');
        this.Verifier = await ethers.getContractFactory('Verifier');
        this.PSR = await ethers.getContractFactory('PandoraSpirit');
    });

    beforeEach( async () => {
        await resetHardhat();
        this.usdt = await this.USDT.deploy('USDT','USDT', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.busd = await this.USDT.deploy('BUSD','BUSD', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.psr = await this.PSR.deploy('10000000000000000000000000', this.wallet[0].address);
        this.verifier = await this.Verifier.deploy(this.wallet[0].address);
        this.presale = await this.Presale.deploy(this.psr.address, this.usdt.address, this.busd.address, this.verifier.address);
        await this.presale.setOperator(this.wallet[0].address);
        for(let i = 0; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            await this.presale.connect(user).register();
            await this.usdt.connect(user).mint(user.address, '5000000000000000000000');
            await this.busd.connect(user).mint(user.address, '5000000000000000000000');
            await this.usdt.connect(user).approve(this.presale.address, '5000000000000000000000');
            await this.busd.connect(user).approve(this.presale.address, '5000000000000000000000');
        }
        await setting(this.psr, this.presale, 1, 10, 0, 86400, 10, 8, 1000);
        let whiteList = [];
        let waitingList = [];
        for(let i = 1; i <= 11; i++ ){
            if(i <= 1) {
                whiteList.push(this.wallet[i].address);
            } else {
                waitingList.push(this.wallet[i].address);
            }
        }
        await this.presale.addWhiteList(whiteList);
        await this.presale.addWaitingList(waitingList);
        let userBuy = this.wallet[1];
        let userCommit = this.wallet[10];
        let startSale = await this.presale.startSale();
        await timeTravel(startSale.toNumber());
        await this.presale.connect(userBuy).buy(this.usdt.address, parseUnits('1000', '18'));
        await this.presale.connect(userCommit).reserveSlot(this.usdt.address, parseUnits('1000', '18'));
    });

    it("Refund after finish", async () => {
        let startSale = await this.presale.startSale();
        let duration = await this.presale.duration();
        let userCommit = this.wallet[10];
        let commitDataBefore = await this.presale.waiting(userCommit.address);
        let balanceOfBefore = await this.usdt.balanceOf(userCommit.address);
        // // console.log("commitDataBefore", commitDataBefore);
        await timeTravel(startSale.add(duration).toNumber());
        // await this.presale.approveWaitingList();
        let approve = false;
        let count = 0;
        while(!approve) {
            let tx = await this.presale.approveWaitingList(3);
            approve = await this.presale.isApprove();
            count++;
        }
        console.log(count);
        console.log(approve);
        await this.presale.connect(userCommit).withdraw();
        let commitDataAfter = await this.presale.waiting(userCommit.address);
        // console.log("commitDataAfter", commitDataAfter);
        let balanceOfAfter = await this.usdt.balanceOf(userCommit.address);
        await expect(commitDataAfter.amountUsdt.toString()).to.equal('0');
        await expect(commitDataAfter.isRefunded).to.equal(true);
        await expect(balanceOfAfter.toString()).to.equal(balanceOfBefore.add(commitDataBefore.amountUsdt).toString());
    });
});

describe("Claim token", async () => {
    before(async () => {
        this.wallet = await ethers.getSigners();
        this.USDT = await ethers.getContractFactory('MockERC20');
        this.Presale = await ethers.getContractFactory('Presale');
        this.Verifier = await ethers.getContractFactory('Verifier');
        this.PSR = await ethers.getContractFactory('PandoraSpirit');
    });

    beforeEach( async () => {
        await resetHardhat();
        this.usdt = await this.USDT.deploy('USDT','USDT', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.busd = await this.USDT.deploy('BUSD','BUSD', this.wallet[0].address, '1000000000000000000000000000000000000');
        this.psr = await this.PSR.deploy('10000000000000000000000000', this.wallet[0].address);
        this.verifier = await this.Verifier.deploy(this.wallet[0].address);
        this.presale = await this.Presale.deploy(this.psr.address, this.usdt.address, this.busd.address, this.verifier.address);
        await this.presale.setOperator(this.wallet[0].address);
        for(let i = 0; i < this.wallet.length; i ++) {
            const user = this.wallet[i];
            await this.presale.connect(user).register();
            await this.usdt.connect(user).mint(user.address, '5000000000000000000000');
            await this.busd.connect(user).mint(user.address, '5000000000000000000000');
            await this.usdt.connect(user).approve(this.presale.address, '5000000000000000000000');
            await this.busd.connect(user).approve(this.presale.address, '5000000000000000000000');
        }
        await setting(this.psr, this.presale, 1, 10, 0, 86400, 10, 8, 1000);
        let whiteList = [];
        let waitingList = [];
        for(let i = 1; i <= 11; i++ ){
            if(i <= 1) {
                whiteList.push(this.wallet[i].address);
            } else {
                waitingList.push(this.wallet[i].address);
            }
        }
        await this.presale.addWhiteList(whiteList);
        await this.presale.addWaitingList(waitingList);
        let userBuy = this.wallet[1];
        let userCommit = this.wallet[10];
        let startSale = await this.presale.startSale();
        let duration = await this.presale.duration();
        await timeTravel(startSale.toNumber());
        await this.presale.connect(userBuy).buy(this.usdt.address, parseUnits('1000', '18'));
        await this.presale.connect(userCommit).reserveSlot(this.usdt.address, parseUnits('1000', '18'));
        await this.verifier.setCliffInfo([startSale.add(duration).toNumber(), startSale.add(duration).add(86400).toNumber(), startSale.add(duration).add(106400).toNumber()],[2000, 3000, 5000], [100, 100, 100]);
        await timeTravel(startSale.add(duration).toNumber());
    });

    it("check claim", async () => {
        let userBuy = this.wallet[1];
        let userInfoBefore = await this.presale.userInfo(userBuy.address);
        let psrAmountBefore = await this.psr.balanceOf(userBuy.address);
        let startSale = await this.presale.startSale();
        let duration = await this.presale.duration();
        await this.presale.connect(userBuy).claim(userBuy.address);
        let userInfoAfter = await this.presale.userInfo(userBuy.address);
        let psrAmountAfter = await this.psr.balanceOf(userBuy.address);
        console.log("userInfoBefore",userInfoBefore);
        console.log("psrAmountBefore",psrAmountBefore.toString());
        console.log("userInfoAfter",userInfoAfter);
        console.log("psrAmountAfter",psrAmountAfter.toString());

        //set cliff for next time
        // await timeTravel(startSale.add(duration).toNumber());
        // await this.presale.connect(userBuy).claim(userBuy.address);
        // let userInfoAfter0 = await this.presale.userInfo(userBuy.address);
        // let psrAmountAfter0 = await this.psr.balanceOf(userBuy.address);
        // console.log("==============================================");
        // console.log("userInfoAfter1",userInfoAfter0);
        // console.log("psrAmountAfter1",psrAmountAfter0.toString());
        await this.verifier.approveClaim([userBuy.address],[100], 1);
        await this.verifier.approveClaim([userBuy.address],[100], 2);
        await timeTravel(startSale.add(duration).add(86400).toNumber());
        await this.presale.connect(userBuy).claim(userBuy.address);
        let userInfoAfter1 = await this.presale.userInfo(userBuy.address);
        let psrAmountAfter1 = await this.psr.balanceOf(userBuy.address);
        console.log("==============================================");
        console.log("userInfoAfter1",userInfoAfter1);
        console.log("psrAmountAfter1",psrAmountAfter1.toString());

        await timeTravel(startSale.add(duration).add(106400).toNumber());
        await this.presale.connect(userBuy).claim(userBuy.address);
        let userInfoAfter2 = await this.presale.userInfo(userBuy.address);
        let psrAmountAfter2 = await this.psr.balanceOf(userBuy.address);
        console.log("==============================================");
        console.log("userInfoAfter2",userInfoAfter2);
        console.log("psrAmountAfter2",psrAmountAfter2.toString());

    });
});