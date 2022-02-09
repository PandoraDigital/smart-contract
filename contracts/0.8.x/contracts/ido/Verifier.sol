//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Verifier is Ownable{

    struct CliffInfo {
        uint256 timeCliff;
        uint256 percentage; // % = percentage / 10000
        uint256 proof;
    }
    uint256 constant public ONE_HUNDRED_PERCENT = 10000;
    CliffInfo[] public cliffInfo;
    bool public isSettingClaim = false;
    address public operator;
    // address => claim times => true/false
    mapping(address => mapping(uint => bool)) public status;

    modifier isSetting() {
        require(!isSettingClaim, "");
        _;
        isSettingClaim = true;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Verifier: Only operator can use function");
        _;
    }

    // event
    event LogTaskComplete(address indexed user, uint256 indexed currentValue, uint256 indexed maxValue, uint256 timeStamp);
    event LogRemoveApproval(address indexed user, uint256 indexed timeStamp, string reason);
    event OperatorChanged(address indexed oldOperator, address indexed newOperator);

    constructor(address _operator) {
        operator = _operator;
    }

    function setOperator(address _newOperator) public onlyOwner {
        require(_newOperator != address(0), "Verifier: Address must be different zero");
        address oldOperator = operator;
        operator = _newOperator;
        emit OperatorChanged(oldOperator, _newOperator);
    }

    function setCliffInfo(uint256[] memory _timeCliff, uint256[] memory _percentage, uint256[] memory _proofs) public onlyOperator isSetting {
        require(_timeCliff.length == _percentage.length && _percentage.length == _proofs.length, "Verifier: Length must be equal");
        uint256 sum;
        for(uint256 i = 0; i < _timeCliff.length; i ++) {
            require(_percentage[i] <= ONE_HUNDRED_PERCENT, "Verifier: percentage over 100 %");
            CliffInfo memory _cliffInfo;
            _cliffInfo.percentage = _percentage[i];
            _cliffInfo.timeCliff = _timeCliff[i];
            _cliffInfo.proof = _proofs[i];
            cliffInfo.push(_cliffInfo);
            sum += _percentage[i];
        }
        require(sum == ONE_HUNDRED_PERCENT, "Verifier: total percentage is not 100%");
    }

    function updateProof(uint256 _proof, uint256 _cliffIndex) public onlyOperator returns(bool){
        require(_cliffIndex < cliffInfo.length, "Verifier: cliff not exist");
        cliffInfo[_cliffIndex].proof = _proof;
        return true;
    }

    function approveClaim(address[] memory _users, uint256[] memory _data, uint256 _claimTime) public onlyOperator {
        require(_claimTime < cliffInfo.length, "Verifier: times overflow");
        require(_users.length == _data.length, "Verifier: length of _users and _data not equal");
        for(uint i = 0; i < _users.length; i++) {
            status[_users[i]][_claimTime] = true;
            emit LogTaskComplete(_users[i], _data[i], cliffInfo[_claimTime].proof, block.timestamp);
        }
    }

    function removeApprove(address[] memory _users, string memory _reason,  uint256 _claimTime) public onlyOperator {
        require(_claimTime < cliffInfo.length, "Verifier: times overflow");
        for(uint i = 0; i < _users.length; i++) {
            status[_users[i]][_claimTime] = false;
            emit LogRemoveApproval(_users[i], _claimTime, _reason);
        }
    }

    function verify(address _user, uint256 _totalToken, uint256 _claimTimes) public view returns (uint amountClaim, bool finish, bool claimable) {
        require(_claimTimes < cliffInfo.length, "Verifier: times overflow");
        claimable = (status[_user][_claimTimes] || _claimTimes == 0) && cliffInfo[_claimTimes].timeCliff <= block.timestamp;
        amountClaim = cliffInfo[_claimTimes].percentage * _totalToken / ONE_HUNDRED_PERCENT;
        finish = false;
        if(_claimTimes == cliffInfo.length - 1) {
            finish = true;
        }
    }

    // ============ Testing ================== //
    function reset() public onlyOperator {
        delete cliffInfo;
        isSettingClaim = false;
    }
}
