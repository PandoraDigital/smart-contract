//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/IPAN.sol";

contract Minter is Ownable, ReentrancyGuard {
    using SafeERC20 for IPAN;

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    mapping (address => bool) public operators;
    uint256 public PANPerBlock;
    uint256 public lastMinted;
    IPAN public PAN;
    address public devFund;
    uint256 public devFundPercent = 1000;
    uint256 public constant ONE_HUNDRED_PERCENT = 10000;

    modifier onlyOperators() {
        require(operators[msg.sender] == true, "Minter: caller is not the operators");
        _;
    }

    constructor (address _devFund, IPAN _PAN, uint256 _PANPerBlock, uint256 _startMint) {
        devFund = _devFund;
        PANPerBlock = _PANPerBlock;
        PAN = _PAN;
        lastMinted = _startMint;
    }

    function update() public {
        if (block.number > lastMinted) {
            uint256 _amount = (block.number - lastMinted) * PANPerBlock;
            uint256 _toDev = _amount * devFundPercent / ONE_HUNDRED_PERCENT;
            PAN.mint(address(this), _amount);
            PAN.safeTransfer(devFund, _toDev);
            lastMinted = block.number;
        }
    }

    function transfer(address _to, uint256 _amount) external onlyOperators nonReentrant {
        if (_amount >= PAN.balanceOf(address(this))) {
            update();
        }
        require(_amount <= PAN.balanceOf(address(this)), 'Minter: not enough PAN');
        PAN.safeTransfer(_to, _amount);
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        operators[_operator] = _status;
        emit OperatorChanged(_operator, _status);
    }

    function setPANPerBlock(uint256 _PANPerBlock) external onlyOwner {
        uint256 oldPANPerBlock = PANPerBlock;
        PANPerBlock = _PANPerBlock;
        emit PANPerBlockChanged(oldPANPerBlock, _PANPerBlock);
    }

    function changeDevFundPercent(uint256 _newPercent) external onlyOwner {
        uint256 oldDevFundPercent = devFundPercent;
        devFundPercent = _newPercent;
        emit DevFundPercentChanged(oldDevFundPercent, _newPercent);
    }

    function changeDevFund(address _newAddr) external onlyOwner {
        address oldDevFund = devFund;
        devFund = _newAddr;
        emit DevFundChanged(oldDevFund, _newAddr);
    }

    event OperatorChanged(address indexed operator, bool status);
    event PANPerBlockChanged(uint256 oldPANPerBlock, uint256 newPANPerBlock);
    event DevFundPercentChanged(uint256 oldPercent, uint256 newPercent);
    event DevFundChanged(address indexed oldDevFund, address indexed newDevFund);
}
