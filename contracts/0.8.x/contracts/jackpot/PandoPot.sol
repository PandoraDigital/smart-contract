//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "../interfaces/IRandomNumberGenerator.sol";

contract PandoPot is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    enum PRIZE_STATUS {AVAILABLE, CLAIMED, LIQUIDATED}
    // 0 : mega, 1 : minor, 2 : leaderboard
    struct PrizeInfo {
        uint256 USD;
        uint256 PSR;
        uint256 expire;
        uint256 nClaimed;
        uint256 totalWinner;
    }

    struct LeaderboardPrizeInfo {
        uint256 USD;
        uint256 PSR;
        uint256 expire;
        PRIZE_STATUS status;
    }

    struct RoundInfo {
        uint256 megaNumber;
        uint256 minorNumber1;
        uint256 minorNumber2;
        uint256 finishedAt;
        uint256 status; //0 : need Update prizeInfo
    }

    address public USD;
    address public PSR;
    address public randomNumberGenerator;

    uint256 public constant PRECISION = 10000000000;
    uint256 public constant unlockPeriod = 2 * 365 * 1 days;
    uint256 public constant ONE_HUNDRED_PERCENT = 10000;
    uint256 public timeBomb = 2 * 30 * 1 days;
    uint256 public prizeExpireTime = 14 * 1 days;
    uint256 public megaPrizePercentage = 2500;
    uint256 public minorPrizePercentage = 100;
    uint256 public roundDuration = 1 hours;

    uint256 public lastDistribute;
    uint256 public USDForCurrentPot;
    uint256 public PSRForCurrentPot;
    uint256 public totalPSRAllocated;
    uint256 public lastUpdatePot;

    uint256 public USDForTimeBomb;
    uint256 public PSRForTimeBomb;

    uint256 public currentRoundId;
    uint256 public currentDistributeId;

    //round => number => address => quantity
    mapping (uint256 => mapping (uint256 => mapping(address => uint))) public megaTickets;
    mapping (uint256 => mapping (uint256 => mapping(address => uint))) public minorTickets;

    mapping (uint256 => mapping (uint256 => mapping(address => uint))) public nMegaTicketsClaimed;
    mapping (uint256 => mapping (uint256 => mapping(address => uint))) public nMinorTicketsClaimed;

    //round => number => quantity
    mapping (uint256 => mapping(uint256 => uint256)) public nMegaTickets;
    mapping (uint256 => mapping(uint256 => uint256)) public nMinorTickets;
    //round => prize
    mapping (uint256 => PrizeInfo) public megaPrize;
    mapping (uint256 => PrizeInfo) public minorPrize;

    //round => address => prize
    mapping (uint256 => mapping(address => LeaderboardPrizeInfo)) public leaderboardPrize;
    mapping (uint256 => RoundInfo) public roundInfo;

    mapping (address => bool) public whitelist;
    uint256[] public seeds;

    uint256 public pendingUSD;

    uint256 public megaSampleSpace = 1e6;
    uint256 public minorSampleSpace = 1e4;

    uint256 public currentMegaNumber;
    uint256 public currentMinorNumber1;
    uint256 public currentMinorNumber2;

    /*----------------------------CONSTRUCTOR----------------------------*/
    constructor (address _USD, address _PSR, address _randomNumberGenerator) {
        USD = _USD;
        PSR = _PSR;
        randomNumberGenerator = _randomNumberGenerator;
        lastDistribute = block.timestamp;
        lastUpdatePot = block.timestamp;
        currentRoundId = 1;
        roundInfo[0].finishedAt = block.timestamp;
        roundInfo[0].status = 1;
    }

    /*----------------------------INTERNAL FUNCTIONS----------------------------*/

    function _transferToken(address _token, address _receiver, uint256 _amount) internal {
        if (_amount > 0) {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }
    }

    function _generateTicket(uint256 _rand, uint256 _sample, uint256 _nSeeds) internal view returns(uint256) {
        if (_nSeeds > 0) {
            return (uint256(keccak256(abi.encodePacked((_rand * seeds[_rand % _nSeeds]))))% _sample);
        }
        return (_rand % _sample);
    }

    function _updateRound(uint256 _id) internal {
        RoundInfo storage _roundInfo = roundInfo[_id];
        uint256 _expire = _roundInfo.finishedAt + prizeExpireTime;
        if (_roundInfo.status == 0) {
            _roundInfo.status = 1;
            _updateLuckyNumber(_id);
            _roundInfo.megaNumber = currentMegaNumber;
            _roundInfo.minorNumber1 = currentMinorNumber1;
            _roundInfo.minorNumber2 = currentMinorNumber2;

            (uint256 _megaUSD, uint256 _megaPSR) = _calcMegaPrize(_id, currentMegaNumber, _expire);
            (uint256 _minorUSD1, uint256 _minorPSR1) = _calcMinorPrize(_id, currentMinorNumber1, _expire);
            (uint256 _minorUSD2, uint256 _minorPSR2) = _calcMinorPrize(_id, currentMinorNumber2, _expire);
            uint256 _totalUSD = _megaUSD + (_minorUSD1 > 0 ? _minorUSD1 : _minorUSD2);
            uint256 _totalPSR = _megaPSR + (_minorPSR1 > 0 ? _minorPSR1 : _minorPSR2);
            pendingUSD += _totalUSD;
            PSRForCurrentPot -= _totalPSR;

            emit RoundCompleted(_id, _expire, currentMegaNumber, currentMinorNumber1, currentMinorNumber2, _megaUSD, _megaPSR, _minorUSD1, _minorPSR1, _minorUSD2, _minorPSR2);
        }
    }

    function _updateLuckyNumber(uint256 _id) internal {
        if (_id > 1) {
            seeds.push(currentMegaNumber);
            seeds.push(currentMinorNumber1);
            seeds.push(currentMinorNumber2);
        }
        (uint256 _megaNumber, uint256 _minorNumber1, uint256 _minorNumber2) = IRandomNumberGenerator(randomNumberGenerator).getNumber();
        currentMegaNumber = (_megaNumber % megaSampleSpace) * block.timestamp % megaSampleSpace;
        currentMinorNumber1 = (_minorNumber1 % minorSampleSpace) * block.timestamp % minorSampleSpace;
        currentMinorNumber2 = (_minorNumber2 % minorSampleSpace) * block.timestamp % minorSampleSpace;
    }

    function _calcMegaPrize(uint256 _roundId, uint256 _megaNumber, uint256 _expire) internal returns(uint256, uint256) {
        PrizeInfo memory _prize = PrizeInfo({
        USD: 0,
        PSR: 0,
        expire: _expire,
        nClaimed: 0,
        totalWinner: nMegaTickets[_roundId][_megaNumber]
        });
        if (_prize.totalWinner > 0) {
            _prize.USD = USDForCurrentPot * megaPrizePercentage / ONE_HUNDRED_PERCENT;
            _prize.PSR = PSRForCurrentPot * megaPrizePercentage / ONE_HUNDRED_PERCENT;
            lastDistribute = _expire - prizeExpireTime;
        }
        megaPrize[_roundId] = _prize;
        return (_prize.USD, _prize.PSR);
    }

    function _calcMinorPrize(uint256 _roundId, uint256 _minorNumber, uint256 _expire) internal returns(uint256, uint256) {
        PrizeInfo storage _prize = minorPrize[_roundId];
        uint256 _totalWinner = nMinorTickets[_roundId][_minorNumber];
        if ( _totalWinner > 0) {
            if (_prize.USD == 0 || _prize.PSR == 0) {
                _prize.USD = USDForCurrentPot * minorPrizePercentage / ONE_HUNDRED_PERCENT;
                _prize.PSR = PSRForCurrentPot * minorPrizePercentage / ONE_HUNDRED_PERCENT;
                _prize.expire = _expire;
                _prize.nClaimed = 0;
            }
            _prize.totalWinner += _totalWinner;
        }

        return (_prize.USD, _prize.PSR);
    }

    function _liquidate(uint256 _type, uint256 _roundId, address _owner) internal {
        uint256 _totalUSD = 0;
        uint256 _totalPSR = 0;

        if (_type == 0 || _type == 1) {
            PrizeInfo storage _megaPrize = megaPrize[_roundId];
            PrizeInfo storage _minorPrize = minorPrize[_roundId];
            require(_megaPrize.expire < block.timestamp || _minorPrize.expire < block.timestamp, 'PandoPot: !expire');
            if (_megaPrize.totalWinner > _megaPrize.nClaimed) {
                _totalUSD = _megaPrize.USD * (_megaPrize.totalWinner - _megaPrize.nClaimed) / _megaPrize.totalWinner;
                _totalPSR = _megaPrize.PSR * (_megaPrize.totalWinner - _megaPrize.nClaimed) / _megaPrize.totalWinner;
                _megaPrize.nClaimed = _megaPrize.totalWinner;
            }
            if (_minorPrize.totalWinner > _minorPrize.nClaimed) {
                _totalUSD += _minorPrize.USD * (_minorPrize.totalWinner - _minorPrize.nClaimed) / _minorPrize.totalWinner;
                _totalPSR += _minorPrize.PSR * (_minorPrize.totalWinner - _minorPrize.nClaimed) / _minorPrize.totalWinner;
                _minorPrize.nClaimed = _minorPrize.totalWinner;
            }
        } else {
            LeaderboardPrizeInfo storage _prize = leaderboardPrize[_roundId][_owner];
            require(_prize.expire < block.timestamp, 'PandoPot: !expire');
            require(_prize.status == PRIZE_STATUS.AVAILABLE, 'PandoPot: !AVAILABLE');
            _prize.status = PRIZE_STATUS.LIQUIDATED;
            _totalUSD = _prize.USD;
            _totalPSR = _prize.PSR;
        }
        pendingUSD -= _totalUSD;
        PSRForCurrentPot += _totalPSR;
        emit Liquidated(_type, _roundId, _owner, _totalUSD, _totalPSR);
    }

    /*----------------------------EXTERNAL FUNCTIONS----------------------------*/

    function getRoundDuration() external view returns(uint256) {
        return roundDuration;
    }

    function enter(address _receiver, uint256 _rand, uint256 _quantity) external whenNotPaused nonReentrant onlyWhitelist() {
        uint256 _megaTicket;
        uint256 _minorTicket;
        uint256 _currentRoundId = currentRoundId;
        uint256[] memory _megaTickets = new uint[](_quantity);
        uint256[] memory _minorTickets = new uint[](_quantity);
        uint256 _sampleSpace = megaSampleSpace;
        uint256 _minorSpace = minorSampleSpace;
        uint256 _nSeeds = seeds.length;
        uint256 _salt = block.timestamp;
        for (uint256 i = 0; i < _quantity; i++) {
            _megaTicket = _generateTicket(_rand, _sampleSpace, _nSeeds);
            _minorTicket = _generateTicket(_rand, _minorSpace, _nSeeds);

            megaTickets[_currentRoundId][_megaTicket][_receiver]++;
            minorTickets[_currentRoundId][_minorTicket][_receiver]++;

            nMegaTickets[_currentRoundId][_megaTicket]++;
            nMinorTickets[_currentRoundId][_minorTicket]++;
            _megaTickets[i] = _megaTicket;
            _minorTickets[i] = _minorTicket;
            _rand = uint256(
                keccak256(
                    abi.encodePacked(
                        _salt
                        + _rand + i
                    )
                )
            ) % _sampleSpace;
        }
        emit NewMegaTicket(_currentRoundId, _receiver, _megaTickets);
        emit NewMinorTicket(_currentRoundId, _receiver, _minorTickets);
    }
    //0 : mega
    //1 : minor
    //2 : distribute

    function claim(uint256 _type, uint256 _roundId, uint256 _ticketNumber, address _receiver) external whenNotPaused nonReentrant {
        updatePandoPot();
        require(_type < 3, 'PandoPot: Invalid type');
        uint256 _USDAmount = 0;
        uint256 _PSRAmount = 0;

        if (_type != 2) {
            RoundInfo memory _roundInfo = roundInfo[_roundId];
            require(_roundInfo.status == 1, 'PandoPot: Round hasnt been finished yet');
            if (_type == 0) {
                require(megaTickets[_roundId][_ticketNumber][msg.sender] > 0 && _roundInfo.megaNumber == _ticketNumber, 'PandoPot: no prize');
                require(megaTickets[_roundId][_ticketNumber][msg.sender] > nMegaTicketsClaimed[_roundId][_ticketNumber][msg.sender], 'Pandot: claimed');
                nMegaTicketsClaimed[_roundId][_ticketNumber][msg.sender]++;

                PrizeInfo storage _prizeInfo = megaPrize[_roundId];
                if (_prizeInfo.expire >= block.timestamp) {
                    uint256 _nWiningTicket = megaTickets[_roundId][_ticketNumber][msg.sender];
                    uint256 _totalWinner = _prizeInfo.totalWinner;
                    _USDAmount = _prizeInfo.USD * _nWiningTicket / _totalWinner;
                    _PSRAmount = _prizeInfo.PSR * _nWiningTicket / _totalWinner;
                    _prizeInfo.nClaimed++;
                } else {
                    _liquidate(_type, _roundId, msg.sender);
                }
            } else {
                if (_type == 1) {
                    require(minorTickets[_roundId][_ticketNumber][msg.sender] > 0 &&
                        (_roundInfo.minorNumber1 == _ticketNumber || _roundInfo.minorNumber2 == _ticketNumber), 'PandoPot: no prize');
                    require(minorTickets[_roundId][_ticketNumber][msg.sender] > nMinorTicketsClaimed[_roundId][_ticketNumber][msg.sender], 'Pandot: claimed');
                    nMinorTicketsClaimed[_roundId][_ticketNumber][msg.sender]++;

                    PrizeInfo storage _prizeInfo = minorPrize[_roundId];
                    if (_prizeInfo.expire >= block.timestamp) {
                        uint256 _nWiningTicket = minorTickets[_roundId][_ticketNumber][msg.sender];
                        uint256 _totalWinner = _prizeInfo.totalWinner;
                        _USDAmount = _prizeInfo.USD * _nWiningTicket / _totalWinner;
                        _PSRAmount = _prizeInfo.PSR * _nWiningTicket / _totalWinner;
                        _prizeInfo.nClaimed++;
                    } else {
                        _liquidate(_type, _roundId, msg.sender);
                    }
                }
            }
        }
        else {
            LeaderboardPrizeInfo storage _prize = leaderboardPrize[_roundId][msg.sender];
            require(_prize.USD + _prize.PSR > 0, 'PandoPot: no prize');
            if (_prize.expire >= block.timestamp) {
                require(_prize.status == PRIZE_STATUS.AVAILABLE, 'PandoPot: prize not available');
                _prize.status = PRIZE_STATUS.CLAIMED;
                _USDAmount = _prize.USD;
                _PSRAmount = _prize.PSR;
            } else {
                _liquidate(_type, _roundId, msg.sender);
            }
        }

        _transferToken(USD, _receiver, _USDAmount);
        _transferToken(PSR, _receiver, _PSRAmount);
        pendingUSD -= _USDAmount;
        emit Claimed(_type, _roundId, _ticketNumber, _USDAmount, _PSRAmount, _receiver);
    }

    function distribute(address[] memory _leaderboards, uint256[] memory ratios) external onlyOwner whenNotPaused {
        require(_leaderboards.length == ratios.length, 'PandoPot: leaderboards != ratios');
        require(block.timestamp - lastDistribute >= timeBomb, 'PandoPot: not enough timebomb');
        uint256 _cur = 0;
        for (uint256 i = 0; i < ratios.length; i++) {
            _cur += ratios[i];
        }
        require(_cur == PRECISION, 'PandoPot: ratios incorrect');
        currentDistributeId++;
        updatePandoPot();
        uint256 _nRatios = ratios.length;
        uint256[] memory _usdAmounts = new uint256[](_nRatios);
        uint256[] memory _psrAmounts = new uint256[](_nRatios);

        for (uint256 i = 0; i < _leaderboards.length; i++) {

            uint256 _USDAmount = USDForTimeBomb * ratios[i] / PRECISION;
            uint256 _PSRAmount = PSRForTimeBomb * ratios[i] / PRECISION;

            LeaderboardPrizeInfo memory _prize = LeaderboardPrizeInfo({
            USD : _USDAmount,
            PSR : _PSRAmount,
            expire : block.timestamp + prizeExpireTime,
            status : PRIZE_STATUS.AVAILABLE
            });
            leaderboardPrize[currentDistributeId][_leaderboards[i]] = _prize;
            _usdAmounts[i] = _USDAmount;
            _psrAmounts[i] = _PSRAmount;
        }
        pendingUSD += USDForTimeBomb;
        USDForTimeBomb = 0;
        PSRForTimeBomb = 0;
        lastDistribute = block.timestamp;
        emit Distributed(currentDistributeId, block.timestamp + prizeExpireTime, _leaderboards, _usdAmounts, _psrAmounts);
    }

    function updatePandoPot() public {
        _updateRound(currentRoundId - 1);
        USDForCurrentPot = IERC20(USD).balanceOf(address(this)) - USDForTimeBomb - pendingUSD;
        PSRForCurrentPot += totalPSRAllocated * (block.timestamp - lastUpdatePot) / unlockPeriod;

        if (block.timestamp - lastDistribute >= timeBomb) {
            if (PSRForTimeBomb == 0 && USDForTimeBomb == 0) {
                USDForTimeBomb = USDForCurrentPot * megaPrizePercentage / ONE_HUNDRED_PERCENT;
                PSRForTimeBomb = PSRForCurrentPot * megaPrizePercentage / ONE_HUNDRED_PERCENT;
                PSRForCurrentPot -= PSRForTimeBomb;
            }
        }
        lastUpdatePot = block.timestamp;
    }

    function liquidate(uint256 _type, uint256 _roundId, address[] memory _owners) external whenNotPaused {
        require(_type < 3, 'PandoPot: invalid type');
        for(uint256 i = 0; i < _owners.length; i++){
            _liquidate(_type, _roundId, _owners[i]);
        }
        updatePandoPot();
    }

    function currentPot() external view returns(uint256, uint256) {
        uint256 _USD = IERC20(USD).balanceOf(address(this)) - USDForTimeBomb - pendingUSD;
        uint256 _PSR = totalPSRAllocated * (block.timestamp - lastUpdatePot) / unlockPeriod + PSRForCurrentPot;

        if (currentRoundId > 1) {
            uint256 _preRound = currentRoundId - 1;
            if (roundInfo[_preRound].status == 0) {
                if(nMegaTickets[_preRound][currentMegaNumber] > 0){
                    _USD -= USDForCurrentPot * megaPrizePercentage / ONE_HUNDRED_PERCENT;
                    _PSR -= PSRForCurrentPot * megaPrizePercentage / ONE_HUNDRED_PERCENT;
                }
                if (nMinorTickets[_preRound][currentMinorNumber1] > 0 || nMinorTickets[_preRound][currentMinorNumber2] > 0) {
                    _USD -= USDForCurrentPot * minorPrizePercentage / ONE_HUNDRED_PERCENT;
                    _PSR -= PSRForCurrentPot * minorPrizePercentage / ONE_HUNDRED_PERCENT;
                }
            }
        }

        return (_USD, _PSR);
    }

    function finishRound() external onlyRNG {
        require(block.timestamp > roundDuration + roundInfo[currentRoundId - 1].finishedAt, 'PandoPot: < roundDuration');
        roundInfo[currentRoundId].finishedAt = block.timestamp;
        currentRoundId++;
        emit RoundIdUpdated(currentRoundId);
    }

    // 0: wrong
    // 1: valid
    // 2: expired
    // 3: claimed
    function checkTicketStatus(uint256 _roundId, uint256 _type, address _owner, uint256 _ticketNumber) external view returns (uint256) {
        if (_type == 0) {
            if (roundInfo[_roundId].megaNumber == _ticketNumber) {
                if (roundInfo[_roundId].finishedAt + prizeExpireTime < block.timestamp) {
                    return 2;
                }
                if (megaTickets[_roundId][_ticketNumber][_owner] > nMegaTicketsClaimed[_roundId][_ticketNumber][_owner]) {
                    return 1;
                }
                return 3;
            }
        } else {
            if (_type == 1) {
                if (roundInfo[_roundId].minorNumber1 == _ticketNumber || roundInfo[_roundId].minorNumber2 == _ticketNumber) {
                    if (roundInfo[_roundId].finishedAt + prizeExpireTime < block.timestamp) {
                        return 2;
                    }
                    if (megaTickets[_roundId][_ticketNumber][_owner] > nMegaTicketsClaimed[_roundId][_ticketNumber][_owner]) {
                        return 1;
                    }
                    return 3;
                }
            }
        }
        return 0;
    }

    /*----------------------------RESTRICTED FUNCTIONS----------------------------*/

    modifier onlyWhitelist() {
        require(whitelist[msg.sender], 'PandoPot: caller is not in the whitelist');
        _;
    }

    modifier onlyRNG() {
        require(msg.sender == randomNumberGenerator, 'PandoPot: !RNG');
        _;
    }

    function toggleWhitelist(address _addr) external onlyOwner {
        whitelist[_addr] = !whitelist[_addr];
        emit WhitelistChanged(_addr, whitelist[_addr]);
    }

    function allocatePSR(uint256 _amount) external onlyOwner {
        totalPSRAllocated += _amount;
        IERC20(PSR).safeTransferFrom(msg.sender, address(this), _amount);
        emit PSRAllocated(_amount);
    }

    function changeTimeBomb(uint256 _second) external onlyOwner {
        uint256 oldSecond = timeBomb;
        timeBomb = _second;
        emit TimeBombChanged(oldSecond, _second);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw() external onlyOwner whenPaused {
        IERC20 _USD = IERC20(USD);
        IERC20 _PSR = IERC20(PSR);
        uint256 _USDAmount = _USD.balanceOf(address(this));
        uint256 _PSRAmount = _PSR.balanceOf(address(this));
        _USD.safeTransfer(owner(), _USDAmount);
        _PSR.safeTransfer(owner(), _PSRAmount);
        emit EmergencyWithdraw(owner(), _USDAmount, _PSRAmount);
    }

    function changeRewardExpireTime(uint256 _newExpireTime) external onlyOwner whenPaused {
        uint256 _oldExpireTIme = prizeExpireTime;
        prizeExpireTime = _newExpireTime;
        emit RewardExpireTimeChanged(_oldExpireTIme, _newExpireTime);
    }

    function changePrizePercent(uint256 _mega, uint256 _minor) external onlyOwner whenPaused {
        require(_mega <= ONE_HUNDRED_PERCENT && _minor < ONE_HUNDRED_PERCENT, 'PandoPot: prize percent invalid');
        uint256 _oldMega = megaPrizePercentage;
        uint256 _oldMinor = minorPrizePercentage;
        megaPrizePercentage = _mega;
        minorPrizePercentage = _minor;
        emit PricePercentageChanged(_oldMega, _oldMinor, _mega, _minor);
    }

    function changeRandomNumberGenerator(address _rng) external onlyOwner whenPaused {
        address _oldRNG = randomNumberGenerator;
        randomNumberGenerator = _rng;
        emit RandomNumberGeneratorChanged(_oldRNG, _rng);
    }

    function changeRoundDuration(uint256 _newDuration) external onlyOwner whenPaused {
        uint256 _oldDuration = roundDuration;
        roundDuration = _newDuration;
        emit RoundDurationChanged(_oldDuration, _newDuration);
    }

    /*----------------------------EVENTS----------------------------*/

    event NewMegaTicket(uint256 roundId, address user, uint256[] numbers);
    event NewMinorTicket(uint256 roundId, address user, uint256[] numbers);

    event Claimed(uint256 _type, uint256 roundId, uint256 ticketNumber, uint256 USD, uint256 PSR, address receiver);
    event Liquidated(uint256 _type, uint256 id, address owner, uint256 USD, uint256 PSR);
    event WhitelistChanged(address indexed whitelist, bool status);
    event PSRAllocated(uint256 amount);
    event TimeBombChanged(uint256 oldValueSecond, uint256 newValueSecond);
    event EmergencyWithdraw(address owner, uint256 USD, uint256 PSR);
    event RewardExpireTimeChanged(uint256 oldExpireTime, uint256 newExpireTime);
    event PricePercentageChanged(uint256 oldMegaPercentage, uint256 oldMinorPercentage, uint256 megaPercentage, uint256 minorPercentage);
    event RandomNumberGeneratorChanged(address indexed _oldRNG, address indexed _RNG);
    event RoundCompleted(uint256 roundId, uint256 expireTime, uint256 megaNumber, uint256 minorNumber1, uint256 minorNumber2, uint256 megaUSD, uint256 megaPSR, uint256 minorUSD1, uint256 minorPSR1, uint256 minorUSD2, uint256 minorPSR2);
    event RoundIdUpdated(uint256 newRoundId);
    event Distributed(uint256 distributeId, uint256 expire, address[] leaderboards, uint256[] usdAmounts, uint[] psrAmounts);
    event RoundDurationChanged(uint256 oldDuration, uint256 newDuration);
}