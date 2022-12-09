//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../IBondNFT.sol";
import "../../../interfaces/IUserLevel.sol";


contract BondStaking is Ownable, IERC721Receiver, Pausable {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 incentiveAmount;
        uint256 bonus;
        uint256 bonusIncentive;
    }

    struct PoolInfo {
        uint256 accRewardPerShare;
        uint256 lastRewardTime;
        uint256 rewardPerSecond;
        uint256 endRewardTime;
        uint256 startRewardTime;
        address token;
        bool isIncentive;
    }
    //struct for response
    struct PendingRewardResponse {
        address rewardToken;
        uint256 pendingAmount;
        bool isIncentivePool;
        int256 rewardDebt;
    }

    uint256 public totalValue;
    uint256 public totalBonus;
    uint256 public totalValueIncentive;
    uint256 public totalBonusIncentive;

    // pool
    mapping(uint256 => PoolInfo) public poolInfo;
    uint256 public totalPool;

    mapping(address => EnumerableSet.UintSet) private depositedNftIds;
    mapping(address => UserInfo) public userInfo; // user => userInfo
    mapping(address => mapping(uint256 => int256)) public userRewardDebt; // user => pid => debt

    EnumerableSet.UintSet private activePool;

    IBondNFT public bondNFT;
    IUserLevel public userLevel;

    // governance
    uint256 private constant ACC_REWARD_PRECISION = 1e12;
    address public reserveFund;

    uint256 public incentiveThreshold = 500 ether;
    uint256 public minimumValue;


    /* ========== Modifiers =============== */

    modifier onlyReserveFund() {
        require(reserveFund == msg.sender, "NFTStakingPool: caller is not the reserveFund");
        _;
    }


    constructor(address _bondNFT, uint256 _incentiveThreshold, uint256 _minimumValue, address[] memory _tokens, bool[] memory _isIncentive) {

        for (uint256 i = 0; i < _tokens.length; i++) {
            _addPoolReward(_tokens[i], _isIncentive[i]);
        }
        bondNFT = IBondNFT(_bondNFT);
        require(_incentiveThreshold >= _minimumValue, "BondStaking: _minimumValue <= _incentiveThreshold");
        incentiveThreshold = _incentiveThreshold;
        minimumValue = _minimumValue;
        emit IncentiveThresholdChanged(0, incentiveThreshold);
        emit MinimumValueChanged(0, _minimumValue);

    }

    /* ========== VIEW FUNCTIONS ========== */

    function getDepositedNft(address _user) external view returns (uint256[] memory _nftIds){
        return depositedNftIds[_user].values();
    }

    function getUserInfo(address _account) public view returns (uint256, uint256) {
        UserInfo memory _user = userInfo[_account];
        return (_user.amount + _user.bonus, _user.incentiveAmount + _user.bonusIncentive);
    }


    function getRewardForDuration(uint256 _from, uint256 _to, uint256 _pid) public view returns (uint256) {
        require(_pid <= totalPool, "BondStaking: Overflow");
        PoolInfo memory _pool = poolInfo[_pid];
        uint256 _rewardPerSecond = _pool.rewardPerSecond;
        if (_from >= _to || _from >= _pool.endRewardTime) return 0;
        if (_to <= _pool.startRewardTime) return 0;
        if (_from <= _pool.startRewardTime) {
            if (_to <= _pool.endRewardTime) return (_to - _pool.startRewardTime) * _rewardPerSecond;
            else return (_pool.endRewardTime - _pool.startRewardTime) * _rewardPerSecond;
        }
        if (_to <= _pool.endRewardTime) return (_to - _from) * _rewardPerSecond;
        else return (_pool.endRewardTime - _from) * _rewardPerSecond;
    }

    function getRewardPerSecond(uint256 _pid) public view returns (uint256) {
        return getRewardForDuration(block.timestamp, block.timestamp + 1, _pid);
    }

    function pendingReward(address _user, uint256 _pid) public view returns (uint256 _pending) {
        require(_pid <= totalPool, "BondStaking: Overflow");
        PoolInfo memory _pool = poolInfo[_pid];
        uint256 _accRewardPerShare = _pool.accRewardPerShare;
        uint256 _totalValue;
        uint256 _amount;
        if (_pool.isIncentive) {
            (, _totalValue) = _getTotalValue();
            (, _amount) = getUserInfo(_user);
        } else {
            (_totalValue,) = _getTotalValue();
            (_amount,) = getUserInfo(_user);
        }
        if (block.timestamp > _pool.lastRewardTime && _totalValue != 0) {
            uint256 rewardAmount = getRewardForDuration(_pool.lastRewardTime, block.timestamp, _pid);
            _accRewardPerShare += (rewardAmount * ACC_REWARD_PRECISION) / _totalValue;
        }
        _pending = uint256(int256(_amount * _accRewardPerShare / ACC_REWARD_PRECISION) - userRewardDebt[_user][_pid]);
    }

    function pendingRewards(address _user) external view returns (PendingRewardResponse[] memory, UserInfo memory) {
        UserInfo memory user = userInfo[_user];
        uint256 _length = activePool.length();
        PendingRewardResponse[] memory _pendingReward = new PendingRewardResponse[](_length);
        for (uint256 i = 0; i < activePool.length(); i ++) {
            uint256 _pid = activePool.at(i);
            PoolInfo memory _pool = poolInfo[_pid];
            PendingRewardResponse memory _response = PendingRewardResponse({
                rewardToken : _pool.token,
                pendingAmount : pendingReward(_user, _pid),
                isIncentivePool : _pool.isIncentive,
                rewardDebt : userRewardDebt[_user][_pid]
            });
            _pendingReward[i] = _response;
        }
        return (_pendingReward, user);
    }

    function getActivePool() external view returns (uint256[] memory) {
        return activePool.values();
    }


    /* ========== EXTERNAL FUNCTIONS ========== */

    function updatePool(uint256 _pid) public {
        require(_pid <= totalPool, "BondStaking: Overflow");
        PoolInfo storage _pool = poolInfo[_pid];
        uint256 _totalValue;
        if (_pool.isIncentive) {
            (, _totalValue) = _getTotalValue();
        } else {
            (_totalValue,) = _getTotalValue();
        }
        if (block.timestamp > _pool.lastRewardTime) {
            if (_totalValue > 0) {
                uint256 rewardAmount = getRewardForDuration(_pool.lastRewardTime, block.timestamp, _pid);
                _pool.accRewardPerShare += rewardAmount * ACC_REWARD_PRECISION / _totalValue;
            }
            _pool.lastRewardTime = block.timestamp;
            emit LogUpdatePool(_pool.lastRewardTime, _totalValue, _pool.accRewardPerShare, _pid);
        }
    }

    function massUpdatePool() public {
        (uint256 _totalValue, ) = _getTotalValue();
        (,uint256 _totalValueIncentive) = _getTotalValue();
        for (uint256 i = 0; i < activePool.length(); i ++) {
            uint256 _pid = activePool.at(i);
            PoolInfo storage _pool = poolInfo[activePool.at(i)];
            if (_pool.isIncentive) {
                _updatePool(_pool, _totalValueIncentive, _pid);
            } else {
                _updatePool(_pool, _totalValue, _pid);
            }
        }
    }


    function deposit(uint256[] memory _tokenIds, address _to) external whenNotPaused {
        // update amount deposit
        UserInfo storage _user = userInfo[_to];

        // amount
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];
            depositedNftIds[_to].add(_tokenId);
            bondNFT.safeTransferFrom(msg.sender, address(this), _tokenId);
        }

        (uint256 _value, uint256 _incentiveValue) = _getValueOfIds(depositedNftIds[_to].values());
        uint256 _incValue = 0;
        uint256 _incIncentive;

        require(_value >= _user.amount, 'BondStaking: Invalid deposit');

        _incValue = _value - _user.amount;

        if (_incentiveValue > _user.incentiveAmount) {
            _incIncentive = _incentiveValue - _user.incentiveAmount;
            _user.incentiveAmount = _incentiveValue;
        }
        _user.amount = _value;

        // update pool and reward debt
        // update pool will update accRewardPerShare with old total value
        // after that, calculate reward debt for user
        _updateRewardDebt(_to, _incValue, _incIncentive, true);

        // after calculate accRewardPerShare, update total value
        totalValue += _incValue;
        totalValueIncentive += _incIncentive;
        _updateAccount(msg.sender);

        emit Deposit(msg.sender, _tokenIds, _incValue, _incIncentive, _to);
    }


    function withdraw(uint256[] memory _tokenIds, address _to) public  {
        UserInfo storage _user = userInfo[msg.sender];

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];
            require(depositedNftIds[msg.sender].remove(_tokenId), "BondStaking: not contain id");
            bondNFT.safeTransferFrom(address(this), _to, _tokenId);
        }
        (uint256 _value, uint256 _incentiveValue) = _getValueOfIds(depositedNftIds[msg.sender].values());
        uint256 _withdrawValue = 0;
        uint256 _withdrawIncentive = 0;
        require(_user.amount >= _value, 'BondStaking: Invalid withdraw');

        _withdrawValue = _user.amount - _value;
        _user.amount = _value;

        if (_incentiveValue < _user.incentiveAmount) {
            _withdrawIncentive = _user.incentiveAmount - _incentiveValue;
            _user.incentiveAmount = _incentiveValue;
        }

        _updateRewardDebt(_to, _withdrawValue, _withdrawIncentive, false);

        totalValue -= _withdrawValue;
        totalValueIncentive -= _withdrawIncentive;
        _updateAccount(msg.sender);

        emit Withdraw(msg.sender, _tokenIds, _withdrawValue, _withdrawIncentive, _to);
    }

    function harvest(address _to) public whenNotPaused {
        _updatePoolAndHarvest(_to, msg.sender);
    }

    // withdraw and harvest
    // first: calculate amount to harvest
    // second: withdraw nft

    function withdrawAndHarvest(uint256[] memory _tokenIds, address _to) public whenNotPaused {
        _withdrawAndHarvest(_tokenIds, _to);
    }

    function withdrawAll(address _to) public {
        uint256[] memory _tokenIds = depositedNftIds[msg.sender].values();
        withdraw(_tokenIds, _to);
    }

    function withdrawAndHarvestAll(address _to) public whenNotPaused {
        uint256[] memory _tokenIds = depositedNftIds[msg.sender].values();
        withdrawAndHarvest(_tokenIds, _to);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param _to Receiver of the LP tokens.
    function emergencyWithdraw(address _to) public {
        UserInfo storage _user = userInfo[msg.sender];
        uint256 _value = _user.amount;
        uint256 _valueIncentive = _user.incentiveAmount;
        _user.amount = 0;
        _user.incentiveAmount = 0;
        totalValue -= _value;
        totalValueIncentive -= _valueIncentive;
        for (uint256 i = 0; i < activePool.length(); i++) {
            userRewardDebt[msg.sender][activePool.at(i)] = 0;
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        uint256[] memory _tokenIds = depositedNftIds[msg.sender].values();
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];
            require(depositedNftIds[msg.sender].remove(_tokenId), "BondStaking: not contain id");
            bondNFT.safeTransferFrom(address(this), _to, _tokenId);
        }
        emit EmergencyWithdraw(msg.sender, _tokenIds, _value, _to);
    }

    function update(address _account) external {
        massUpdatePool();
        _updateAccount(_account);
    }

    function onERC721Received(
        address operator,
        address, //from
        uint256, //tokenId
        bytes calldata //data
    ) public view override returns (bytes4) {
        require(
            operator == address(this),
            "BondStaking: received Nft from unauthenticated contract"
        );

        return
        bytes4(
            keccak256("onERC721Received(address,address,uint256,bytes)")
        );
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _getBonus(uint256 _value, address _user) internal view returns (uint256) {
        if (address(userLevel) != address(0)) {
            (uint256 _n, uint256 _d) = userLevel.getBonus(_user, address(this));
            return _value * _n / _d;
        }
        return 0;
    }

    function _getTotalValue() internal view returns (uint256, uint256) {
        return (totalValue + totalBonus, totalValueIncentive + totalBonusIncentive);
    }

    function _updateAccount(address _account) internal {
        UserInfo storage _user = userInfo[_account];
        uint256 _oldBonus = _user.bonus;
        uint256 _oldBonusIncentive = _user.bonusIncentive;
        uint256 _newBonus = _getBonus(_user.amount, _account);
        uint256 _newBonusIncentive = _getBonus(_user.incentiveAmount, _account);

        bool _isDeposit = _newBonus > _oldBonus;

        for (uint256 i = 0; i < activePool.length(); i++) {
            uint256 _pid = activePool.at(i);
            PoolInfo memory _pool = poolInfo[_pid];
            if (_pool.isIncentive) {
                if (_isDeposit) {
                    userRewardDebt[_account][_pid] += int256((_newBonusIncentive - _oldBonusIncentive) * _pool.accRewardPerShare / ACC_REWARD_PRECISION);
                } else {
                    userRewardDebt[_account][_pid] -= int256((_oldBonusIncentive - _newBonusIncentive) * _pool.accRewardPerShare / ACC_REWARD_PRECISION);
                }
            } else {
                if (_isDeposit) {
                    userRewardDebt[_account][_pid] += int256((_newBonus - _oldBonus) * _pool.accRewardPerShare / ACC_REWARD_PRECISION);
                } else {
                    userRewardDebt[_account][_pid] -= int256((_oldBonus - _newBonus) * _pool.accRewardPerShare / ACC_REWARD_PRECISION);
                }
            }
        }

        if(_isDeposit) {
            totalBonusIncentive += _newBonusIncentive - _oldBonusIncentive;
            totalBonus += _newBonus - _oldBonus;
        } else {
            totalBonusIncentive -= _oldBonusIncentive - _newBonusIncentive;
            totalBonus -= _oldBonus - _newBonus;
        }


        _user.bonusIncentive = _newBonusIncentive;
        _user.bonus = _newBonus;
    }

    function _getValueOfIds(uint256[] memory _ids) internal view returns (uint256 _value, uint256 _incentiveValue) {
        uint256 _minimumValue = minimumValue;
        uint256 _incentiveThreshold = incentiveThreshold;
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 _amount = bondNFT.info(_ids[i]).amount;
            require(_amount >= _minimumValue, "BondStaking: value must be greater than minimum");
            if (_amount >= _incentiveThreshold) {
                _incentiveValue += _amount;
            }
            _value += _amount;
        }
        return (_value, _incentiveValue);
    }

    function _addPoolReward(address _token, bool _isIncentive) internal {
        totalPool ++;
        PoolInfo memory _pool = PoolInfo({
            startRewardTime : block.timestamp,
            lastRewardTime : block.timestamp,
            isIncentive : _isIncentive,
            token : _token,
            accRewardPerShare : 0,
            rewardPerSecond : 0,
            endRewardTime : 0
        });
        poolInfo[totalPool] = _pool;
        activePool.add(totalPool);
        emit PoolAdded(totalPool, _token, _isIncentive);
    }

    function _updatePool(PoolInfo storage _pool, uint256 _totalValue, uint256 _pid) internal returns (uint256){
        if (block.timestamp > _pool.lastRewardTime) {
            if (_totalValue > 0) {
                uint256 rewardAmount = getRewardForDuration(_pool.lastRewardTime, block.timestamp, _pid);
                _pool.accRewardPerShare += rewardAmount * ACC_REWARD_PRECISION / _totalValue;
            }
            _pool.lastRewardTime = block.timestamp;
            emit LogUpdatePool(_pool.lastRewardTime, _totalValue, _pool.accRewardPerShare, _pid);
        }
        return _pool.accRewardPerShare;
    }

    // _isDepositOrWithdraw: true: deposit , false: withdraw
    function _updateRewardDebt(address _user, uint256 _value, uint256 _incentiveValue, bool _isDepositOrWithdraw) internal {
        uint256 _totalValue = totalValue;
        uint256 _totalValueIncentive = totalValueIncentive;
        for (uint256 i = 0; i < activePool.length(); i ++) {
            uint256 _pid = activePool.at(i);
            PoolInfo storage _pool = poolInfo[_pid];
            if (_pool.isIncentive) {
                uint256 _rewardPerShare = _updatePool(_pool, _totalValueIncentive, _pid);
                if (_isDepositOrWithdraw) {
                    userRewardDebt[_user][_pid] += int256(_incentiveValue * _rewardPerShare / ACC_REWARD_PRECISION);
                } else {
                    userRewardDebt[_user][_pid] -= int256(_incentiveValue * _rewardPerShare / ACC_REWARD_PRECISION);
                }
            } else {
                uint256 _rewardPerShare = _updatePool(_pool, _totalValue, _pid);
                if (_isDepositOrWithdraw) {
                    userRewardDebt[_user][_pid] += int256(_value * _rewardPerShare / ACC_REWARD_PRECISION);
                } else {
                    userRewardDebt[_user][_pid] -= int256(_value * _rewardPerShare / ACC_REWARD_PRECISION);
                }
            }
        }
    }

    function _updatePoolAndHarvest(address _to, address _user) internal {
        uint256 _totalValue = totalValue;
        uint256 _totalValueIncentive = totalValueIncentive;
        UserInfo memory user = userInfo[_user];
        for (uint256 i = 0; i < activePool.length(); i ++) {
            uint256 _pid = activePool.at(i);
            PoolInfo storage _pool = poolInfo[_pid];
            uint256 _pendingReward = 0;
            uint256 _rewardPerShare;
            int256 _accumulatedReward;

            if (_pool.isIncentive) {
                _rewardPerShare = _updatePool(_pool, _totalValueIncentive, _pid);
                _accumulatedReward = int256((user.incentiveAmount + user.bonusIncentive) * _rewardPerShare / ACC_REWARD_PRECISION);
            } else {
                _rewardPerShare = _updatePool(_pool, _totalValue, _pid);
                _accumulatedReward = int256((user.amount + user.bonus)* _rewardPerShare / ACC_REWARD_PRECISION);
            }
            _pendingReward = uint256(_accumulatedReward - userRewardDebt[_user][_pid]);

            //update reward debt
            userRewardDebt[_user][_pid] = _accumulatedReward;
            if (_pendingReward > 0) {
                IERC20(_pool.token).safeTransfer(_to, _pendingReward);
            }
            emit Harvest(msg.sender, _pendingReward, _pid, _pool.isIncentive);
        }
    }


    //TODO: optimize duplicate updatePool
    function _withdrawAndHarvest(uint256[] memory tokenIds, address to) internal {
        _updatePoolAndHarvest(to, msg.sender);
        withdraw(tokenIds, to);
    }

    function _allocateReward(uint256 _addedReward, uint256 _days, uint256 _pid) internal {
        PoolInfo storage _pool = poolInfo[_pid];
        _updatePool(_pool, _pool.isIncentive ? totalValueIncentive : totalValue, _pid);
        uint256 _pendingSeconds = (_pool.endRewardTime > block.timestamp) ? (_pool.endRewardTime - block.timestamp) : 0;
        uint256 _newPendingReward = (_pool.rewardPerSecond * _pendingSeconds) + _addedReward;
        uint256 _newPendingSeconds = _pendingSeconds + (_days * (1 days));
        uint256 _newRewardPerSecond = _newPendingReward / _newPendingSeconds;
        uint256 _oldRewardPerSecond = _pool.rewardPerSecond;
        _pool.rewardPerSecond = _newRewardPerSecond;
        if (_days > 0) {
            if (_pool.endRewardTime < block.timestamp) {
                _pool.endRewardTime = block.timestamp + (_days * (1 days));
            } else {
                _pool.endRewardTime = _pool.endRewardTime + (_days * (1 days));
            }
        }
        IERC20(_pool.token).safeTransferFrom(msg.sender, address(this), _addedReward);
        emit RewardPerSecondChanged(_oldRewardPerSecond, _newRewardPerSecond, _pid);
        emit AllocateReward(_addedReward, _days, _pid, _pool.startRewardTime, _pool.endRewardTime);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    function allocateMoreRewards(uint256 _addedReward, uint256 _days, uint256 _pid) external onlyReserveFund {
        _allocateReward(_addedReward, _days, _pid);
    }

    function addRewardForPools(uint256 _days, uint256[] memory _rewards) external onlyReserveFund {
        uint256 _length = activePool.length();
        require(_rewards.length == _length, "BondStaking: invalid length");
        for (uint256 i = 0; i < _length; i++) {
            uint256 _pid = activePool.at(i);
            _allocateReward(_rewards[i], _days, _pid);
        }
    }

    function setReserveFund(address _reserveFund) external onlyOwner {
        address _oldReserveFund = reserveFund;
        reserveFund = _reserveFund;
        emit ReserveFundChanged(_oldReserveFund, _reserveFund);
    }

    function rescueFund(address _token, uint256 _amount) external onlyOwner {
        require(_amount > 0 && _amount <= IERC20(_token).balanceOf(address(this)), "BondStaking: invalid amount");
        IERC20(_token).safeTransfer(owner(), _amount);
        emit FundRescued(owner(), _amount, _token);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function updateIncentiveThreshold(uint256 _value) external onlyOwner {
        uint256 _old = incentiveThreshold;
        incentiveThreshold = _value;
        emit IncentiveThresholdChanged(_old, _value);
    }

    function updateMinimumValue(uint256 _value) external onlyOwner {
        uint256 old = minimumValue;
        minimumValue = _value;
        emit MinimumValueChanged(old, _value);
    }

    function setUserLevelAddress(address _userLevel) external onlyOwner {
        userLevel = IUserLevel(_userLevel);
        emit UserLevelChanged(_userLevel);
    }
    /* =============== EVENTS ==================== */

    event Deposit(address indexed user, uint256[] nftId, uint256 amount, uint256 incentive, address indexed to);
    event Withdraw(address indexed user, uint256[] nftId, uint256 amount, uint256 incentive, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256[] nftId, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 amount, uint256 pid, bool isIncentive);
    event LogUpdatePool(uint256 lastRewardTime, uint256 lpSupply, uint256 accRewardPerShare, uint256 pid);
    event RewardPerSecondChanged(uint256 oldRewardPerSecond, uint256 newRewardPerSecond, uint256 pid);
    event FundRescued(address indexed receiver, uint256 amount, address token);
    event ReceivingFundChanged(address indexed oldReceivingFund, address indexed newReceivingFund);
    event ReserveFundChanged(address indexed oldReserveFund, address indexed newReserveFund);
    event PoolAdded(uint256 pid, address token, bool isIncentive);
    event IncentiveThresholdChanged(uint256 _old, uint256 _new);
    event MinimumValueChanged(uint256 _old, uint256 _new);
    event AllocateReward(uint256 _addedReward, uint256 _days, uint256 _pid, uint256 _startRewardTime, uint256 _endRewardTime);
    event UserLevelChanged(address indexed userLevel);
}