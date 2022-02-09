//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import '../interfaces/IVerifier.sol';

contract Presale is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;


    struct UserInfo {
        uint8 status; // 0 - 1 - 2 - 3 - 4 : times claim token
        bool finish; // time next cliff
        uint256 totalToken; // total token receive
        uint256 totalTokenClaim; // total token user has received
        uint256 amountUsdt; // amount of usdt user buy
        uint256 amountBusd; // amount of usdt user buy
    }

    struct WaitingInfo {
        uint256 amountUsdt; // amount of usdt user commit to buy
        uint256 amountBusd; // amount of usdt user commit to buy
        bool isRefunded;
    }

    // register
    EnumerableSet.AddressSet private registerList;

    // white list
    EnumerableSet.AddressSet private whiteList;

    // waiting list
    address[] private waitingList;
    mapping(address => uint256) private index;
    mapping(uint256 => bool) private userReservation;

    mapping(address => UserInfo) public userInfo;
    mapping(address => WaitingInfo) public waiting;

    address[] public contributors;

    // token erc20 info
    IERC20 public PandoraSpirit;
    IERC20 public USDT;
    IERC20 public BUSD;

    //Verifier claim
    IVerifier public verifier;

    //amount usd bought
    uint256 public totalAmountUSDT = 0;
    uint256 public totalAmountBUSD = 0;

    // sale setting
    uint256 public MAX_BUY_USDT = 1000 ether;
    uint256 public MIM_BUY_USDT = 0;
    uint256 public MAX_BUY_PSR = 1000 ether;
    uint256 public totalTokensSale;
    uint256 public remain;
    uint256 public whiteListSlots; // number of white list slot
    uint256 public waitingListSlots; // number of waiting list slot
    uint256 public startSale;
    uint256 public duration;
    // price
    // token buy = usdt * denominator / numerator;
    // rate usdt / psr = numerator / denominator;
    uint256 public numerator = 1;
    uint256 public denominator = 1;

    address public operator;

    //control variable
    bool public isSetting = false;
    bool public isApprove = false;
    bool private isAdminWithdraw = false;

    modifier allowBuy(address _currency, uint256 _amount) {
        require(block.timestamp >= startSale && block.timestamp <= startSale + duration, "Token not in sale");
        require(_currency == address(USDT) || _currency == address(BUSD), "Currency not allowed");
        require(_amount >= MIM_BUY_USDT, "purchase amount needs to be greater than MIM_BUY_USDT");
        _;
    }

    modifier inWhiteList() {
        require(whiteList.contains(msg.sender), "User not in white list");
        _;
    }

    modifier inWaitingList() {
        require(index[msg.sender] > 0, "User not in waiting list");
        _;
    }

    modifier isWithdraw() {
        require(block.timestamp >= startSale + duration, "Not in time withdraw");
        require(isApprove, "Waiting list on buy time");
        _;
    }

    modifier isSettingTime() {
        require(!isSetting, "Contract has called setting");
        _;
        isSetting = true;
    }

    modifier isCallApprove() {
        require(!isApprove, "Contract has called approve");
        require(block.timestamp > startSale + duration, "Can not approve this time");
        _;
        isApprove = true;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Only operator role can check");
        _;
    }


    // event
    event BuySuccess(address indexed user, uint256 indexed amount, uint256 indexed timestamp);
    event CommitSuccess(address indexed user, uint256 indexed amount, uint256 indexed timestamp);
    event ApproveWaitingBuy(address indexed user, uint256 indexed amount, uint256 indexed timestamp);
    event Claim(address indexed _to, uint256 indexed amount, uint256 indexed timestamp);
    event Withdraw(address indexed _to, uint256 indexed timestamp);
    event WhiteListChanged(address indexed user, bool status);
    event WaitingListChanged(address indexed user, bool status);
    event Registered(address indexed user);
    event OperatorChanged(address indexed oldOperator, address indexed newOperator);

    constructor(IERC20 _psr,IERC20 _usdt, IERC20 _busd, IVerifier _verifier) {
        PandoraSpirit = _psr;
        USDT = _usdt;
        BUSD = _busd;
        verifier = _verifier;
    }

    // ================= INTERNAL FUNCTIONS ================= //
    function _getAmountToken(uint256 _amountIn) internal view returns (uint256) {
        return _amountIn * denominator / numerator;
    }

    function _addWhiteList(address _user) internal {
        require(registerList.contains(_user), "User not in register list");
        require(!(index[_user] != 0), "User already in waiting list");
        whiteList.add(_user);
        emit WhiteListChanged(_user, true);
    }

    function _addWaitingList(address _user) internal {
        require(registerList.contains(_user), "User not in register list");
        require(!whiteList.contains(_user), "User already in white list");
        if(index[_user] != 0) return;
        waitingList.push(_user);
        index[_user] = waitingList.length;
        emit WaitingListChanged(_user, true);
    }

    function _approveWaitingList(uint256 _index) internal returns (bool isBreak) {
        WaitingInfo storage _info = waiting[waitingList[_index]];
        UserInfo storage _userInfo = userInfo[waitingList[_index]];

        isBreak = true;
        if(_getAmountToken(_info.amountBusd) >= remain ) {
            uint256 exceed = (_getAmountToken(_info.amountBusd) - remain) * numerator / denominator;
            _userInfo.amountBusd += _info.amountBusd - exceed;
            _userInfo.amountUsdt = 0;
            _info.amountBusd = exceed;
        } else if(_getAmountToken(_info.amountUsdt) >= remain ) {
            uint256 exceed = (_getAmountToken(_info.amountUsdt) - remain) * numerator / denominator;
            _userInfo.amountUsdt += _info.amountUsdt - exceed;
            _userInfo.amountBusd = 0;
            _info.amountUsdt = exceed;
        } else if(_getAmountToken(_info.amountBusd + _info.amountUsdt) >= remain ) {
            uint256 exceed = (_getAmountToken(_info.amountBusd + _info.amountUsdt) - remain) * numerator / denominator;
            if(_info.amountBusd >= exceed) {
                _userInfo.amountBusd += _info.amountBusd - exceed;
                _userInfo.amountUsdt = _info.amountUsdt;
                _info.amountBusd = exceed;
                _info.amountUsdt = 0;
            } else {
                _userInfo.amountUsdt += _info.amountUsdt - exceed;
                _userInfo.amountBusd = _info.amountBusd;
                _info.amountUsdt = exceed;
                _info.amountBusd = 0;
            }
        } else {
            _userInfo.amountBusd += _info.amountBusd;
            _userInfo.amountUsdt += _info.amountUsdt;
            _info.amountUsdt = 0;
            _info.amountBusd = 0;
            isBreak = false;
        }

        _userInfo.totalToken = _getAmountToken(_userInfo.amountBusd + _userInfo.amountUsdt);
        totalAmountBUSD += _userInfo.amountBusd;
        totalAmountUSDT += _userInfo.amountUsdt;
        contributors.push(waitingList[_index]);
        remain -= _userInfo.totalToken;

        emit ApproveWaitingBuy(waitingList[_index], _userInfo.totalToken, block.timestamp);
    }

    function _buy(address _currency, uint256 _amount) internal {
        UserInfo storage _info = userInfo[msg.sender];
        require(_amount + _info.amountBusd + _info.amountUsdt <= MAX_BUY_USDT, "User buy overflow allowance");

        // transfer usd to contract
        IERC20(_currency).safeTransferFrom(msg.sender, address(this), _amount);

        // store info
        uint256 _amountPSR = _getAmountToken(_amount);
        // store number of usdt buy
        if(_currency == address(USDT)) {
            _info.amountUsdt += _amount;
            totalAmountUSDT += _amount;
        } else {
            _info.amountBusd += _amount;
            totalAmountBUSD += _amount;
        }
        //        _info.nextCliff = startSale + duration;
        _info.totalToken += _amountPSR;

        //update global
        remain -= _amountPSR;

        //add to contributors
        contributors.push(msg.sender);

        //event
        emit BuySuccess(msg.sender, _info.totalToken, block.timestamp);
    }

    // ================= EXTERNAL FUNCTIONS ================= //
    function settingPresale(
        uint256 _whitelistSlots,
        uint256 _waitingListSlots,
        uint256 _startSale,
        uint256 _duration,
        uint256 _numerator,
        uint256 _denominator,
        uint256 _maxBuy
    )
    external
    onlyOwner
    isSettingTime
    {
        require(_startSale > block.timestamp, "_start sale in past");
        require(_numerator > 0 && _denominator > 0, "Price can not be zero");
        whiteListSlots = _whitelistSlots;
        waitingListSlots = _waitingListSlots;
        startSale = _startSale;
        duration = _duration;
        numerator = _numerator;
        denominator = _denominator;
        MAX_BUY_USDT = _maxBuy * 1 ether;
        MAX_BUY_PSR = _getAmountToken(MAX_BUY_USDT);
        totalTokensSale = _getAmountToken(MAX_BUY_USDT * whiteListSlots);
        remain = totalTokensSale;
        PandoraSpirit.safeTransferFrom(msg.sender, address(this), totalTokensSale);
    }

    function setOperator(address _newOperator) public onlyOwner {
        require(_newOperator != address(0), "Operator must be different address 0");
        address oldOperator = operator;
        operator = _newOperator;
        emit OperatorChanged(oldOperator, _newOperator);
    }

    function addWhiteList(address[] memory _whiteList) external onlyOperator {
        require(_whiteList.length + whiteList.length() <= whiteListSlots, "white list overflow");
        require(block.timestamp < startSale, "Can not add white list after starting sale");
        for(uint i = 0; i < _whiteList.length; i++) {
            _addWhiteList(_whiteList[i]);
        }
    }

    function addWaitingList(address[] memory _waitingList) external onlyOperator{
        require(_waitingList.length + waitingList.length <= waitingListSlots, "waiting list overflow");
        require(block.timestamp < startSale, "Can not add waiting list after starting sale" );
        for(uint i = 0; i < _waitingList.length; i++) {
            _addWaitingList(_waitingList[i]);
        }
    }

    function buy(address _currency, uint256 _amount) public allowBuy(_currency, _amount) inWhiteList whenNotPaused {
        _buy(_currency, _amount);
    }

    // user in waiting list reserve slot to buy
    function reserveSlot(address _currency, uint256 _amount) public allowBuy(_currency, _amount) inWaitingList whenNotPaused {
        WaitingInfo storage _info = waiting[msg.sender];
        require(_amount + _info.amountBusd + _info.amountUsdt <= MAX_BUY_USDT, "User buy overflow allowance");

        // transfer usd to contract
        IERC20(_currency).safeTransferFrom(msg.sender, address(this), _amount);

        // update _info
        if(_currency == address(USDT)) {
            _info.amountUsdt += _amount;
        } else {
            _info.amountBusd += _amount;
        }

        //store user in list
        userReservation[index[msg.sender] - 1] = true;

        //emit event
        emit CommitSuccess(msg.sender, _amount, block.timestamp);
    }

    function approveWaitingList() public isCallApprove {
        if(remain == 0) return;
        uint256 _length = waitingList.length;
        for(uint256 i = 0; i < _length; i++) {
            if(!userReservation[i]) continue;
            if(_approveWaitingList(i)) break;
        }
    }

    function claim(address _to) public nonReentrant {
        require(_to != address(0), "address must be different 0");
        UserInfo storage _userInfo = userInfo[msg.sender];
        require(_userInfo.totalToken > 0 || !_userInfo.finish, "User not in list claim");
        (uint256 amountClaim, bool finish, bool claimable) = verifier.verify(msg.sender, _userInfo.totalToken, _userInfo.status);
        require(claimable, "User can not claim now");
        if(finish) {
            _userInfo.finish = finish;
            amountClaim = _userInfo.totalToken - _userInfo.totalTokenClaim;
        }
        _userInfo.totalTokenClaim += amountClaim;
        _userInfo.status += 1;
        PandoraSpirit.safeTransfer(_to, amountClaim);
        emit Claim(_to, amountClaim, block.timestamp);
    }

    function withdraw() public isWithdraw nonReentrant {
        WaitingInfo storage _waitingInfo = waiting[msg.sender];
        require(_waitingInfo.amountUsdt > 0 || _waitingInfo.amountBusd > 0, "Don't have any fund");

        if(_waitingInfo.amountUsdt > 0) {
            uint256 amountUsdt = _waitingInfo.amountUsdt;
            _waitingInfo.amountUsdt = 0;
            USDT.safeTransfer(msg.sender, amountUsdt);
        }

        if(_waitingInfo.amountBusd > 0) {
            uint256 amountBusd = _waitingInfo.amountBusd;
            _waitingInfo.amountBusd = 0;
            BUSD.safeTransfer(msg.sender, amountBusd);
        }
        _waitingInfo.isRefunded = true;
        emit Withdraw(msg.sender, block.timestamp);
    }

    function register() external {
        bool added = registerList.add(msg.sender);
        require(added, "User has registered");
        emit Registered(msg.sender);
    }

    function removeUserInWhiteList(address[] memory _users) external onlyOperator {
        require(block.timestamp < startSale, "Can not remove white list after starting sale");
        for(uint i = 0; i < _users.length; i++) {
            whiteList.remove(_users[i]);
            emit WhiteListChanged(_users[i], false);
        }
    }

    //NOTE: function can consume more gas to update.
    function removeUserInWaitingList(uint256 _index) external onlyOperator {
        require(block.timestamp < startSale, "Can not remove waiting list after starting sale");
        require(_index < waitingList.length, "Out of range waiting list");

        //remove index
        address user = waitingList[_index];
        index[waitingList[_index]] = 0;

        //remove gap and delete
        for (uint i = _index; i < waitingList.length - 1; i++){
            waitingList[i] = waitingList[i+1];
            //update index
            index[waitingList[i]] = i + 1;
        }
        waitingList.pop();
        emit WhiteListChanged(user, false);
    }

    //NOTE: function can consume more gas to update.
    function updateWaitingListQueue(address _user, uint256 _newIndex) external onlyOperator {
        require(index[_user] > 0, "User must be in waiting list");
        require(_newIndex < waitingList.length, "User must be in waiting list");
        uint256 _index = index[_user] - 1;
        //update address affected
        if(_newIndex > _index) {
            for(uint i = _index; i < _newIndex; i++) {
                waitingList[i] = waitingList[i + 1];
                index[waitingList[i]] = i + 1;
            }
        } else {
            for(uint i = _index; i > _newIndex; i--) {
                waitingList[i] = waitingList[i - 1];
                index[waitingList[i]] = i + 1;
            }
        }
        waitingList[_newIndex] = _user;
        index[_user] = _newIndex + 1;
    }


    // ================= VIEWS FUNCTIONS ================= //
    function isRegistered(address _user) external view returns(bool) {
        return registerList.contains(_user);
    }

    function listRegister() external view returns(address[] memory) {
        return registerList.values();
    }

    function totalRegister() external view returns(uint256) {
        return registerList.length();
    }

    function isWhiteList(address _user) external view returns(bool) {
        return whiteList.contains(_user);
    }

    function whiteListUser() external view returns(address[] memory) {
        return whiteList.values();
    }

    function totalWhiteList() external view returns(uint256) {
        return whiteList.length();
    }

    function isWaitingList(address _user) external view returns(bool) {
        return index[_user] > 0;
    }

    function waitingListUser() external view returns(address[] memory) {
        return waitingList;
    }

    function totalWaitingList() external view returns(uint256) {
        return waitingList.length;
    }

    function getAmountOfAllowBuying(address _user) external view returns(uint256) {
        return MAX_BUY_USDT - (userInfo[_user].amountUsdt + userInfo[_user].amountBusd);
    }

    function getAmountOfAllowWaiting(address _user) external view returns(uint256) {
        return MAX_BUY_USDT - (waiting[_user].amountUsdt + waiting[_user].amountBusd);
    }

    function waitingQueueNumber(address _user) external view returns (uint256) {
        return index[_user];
    }

    function totalContributors() external view returns (uint256) {
        return contributors.length;
    }

    function getContributors() external view returns (address[] memory) {
        return contributors;
    }


    // ================= ADMIN FUNCTIONS ================= //
    function emergencyWithdraw(address _to) external onlyOwner whenPaused {
        PandoraSpirit.safeTransfer(_to, PandoraSpirit.balanceOf(address(this)));
        USDT.safeTransfer(_to, USDT.balanceOf(address(this)));
        BUSD.safeTransfer(_to, BUSD.balanceOf(address(this)));
    }

    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() public onlyOwner whenPaused {
        _unpause();
    }

    function withdrawAdmin(address _to) public onlyOwner {
        require(block.timestamp >= startSale + duration && isApprove && !isAdminWithdraw, "Can not withdraw before end");
        USDT.safeTransfer(_to, totalAmountUSDT);
        BUSD.safeTransfer(_to, totalAmountBUSD);
        if (remain > 0) {
            PandoraSpirit.safeTransfer(_to, remain);
        }
        isAdminWithdraw = true;
    }

    function setMinBuy(uint256 _value) public onlyOwner {
        MIM_BUY_USDT = _value;
    }

    // ================= Testing ================= //
    function setWhiteListSlot(uint256 _newValue, bool _delete) public onlyOperator {
        whiteListSlots = _newValue;
        totalTokensSale = _getAmountToken(MAX_BUY_USDT * whiteListSlots);
        if(_delete) {
            for(uint i = 0; i < whiteList.length(); i ++) {
                whiteList.remove(whiteList.at(i));
            }
        }
    }

    function setWaitingListSlot(uint256 _newValue, bool _delete) public onlyOperator {
        waitingListSlots = _newValue;
        if(_delete) {
            delete waitingList;
        }
    }

    function setStartSale(uint256 _startSale) public onlyOperator {
        startSale = _startSale;
    }

    function setDuration(uint256 _duration) public onlyOperator {
        duration = _duration;
    }

    function setPrice(uint256 _numerator, uint256 _denominator) public onlyOperator {
        numerator = _numerator;
        denominator = _denominator;
        totalTokensSale = _getAmountToken(MAX_BUY_USDT * whiteListSlots);
        remain = totalTokensSale;
    }

    function setMaxBuy(uint256 _newValue) public onlyOperator {
        MAX_BUY_USDT = _newValue;
        totalTokensSale = _getAmountToken(MAX_BUY_USDT * whiteListSlots);
        remain = totalTokensSale;
    }

    function resetControl() public onlyOperator {
        isSetting = false;
        isApprove = false;
        isAdminWithdraw = false;
        totalAmountBUSD = 0;
        totalAmountUSDT = 0;
        delete contributors;
    }

    function setVerifier(IVerifier _newValue) public onlyOperator {
        verifier = _newValue;
    }

    function resetData(address _user) public onlyOperator {
        delete userInfo[_user];
        delete waiting[_user];
    }
}
