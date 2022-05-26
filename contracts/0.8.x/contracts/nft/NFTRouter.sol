//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../libraries/NFTLib.sol";
import "../interfaces/IPandoBox.sol";
import "../interfaces/IDroidBot.sol";
import "../interfaces/IPandoPot.sol";
import "../interfaces/IDataStorage.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ISwapRouter02.sol";
import "../interfaces/IUserLevel.sol";
import "../interfaces/IAvatar.sol";

contract NFTRouter is Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using ECDSA for bytes;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    enum RequestStatus {AVAILABLE, EXECUTED}
    enum RequestType {BUY, CREATE, UPGRADE, AVATAR}
    struct Request {
        uint256 id;
        uint256 createdAt;
        uint256 seed;
        RequestType rType;
        RequestStatus status;
        uint256[] data;
    }

    mapping(uint256 => uint256) private pandoBoxCreated;
    mapping(address => EnumerableSet.UintSet) private userRequests;
    mapping(uint256 => Request) public requests;

    EnumerableSet.AddressSet validators;

    uint256 public PRECISION;
    uint256 constant ONE_HUNDRED_PERCENT = 10000;
    IDroidBot public droidBot;
    IPandoBox public pandoBox;
    IPandoPot public pandoPot;
    IDataStorage public dataStorage;
    IERC20 public PAN;
    IERC20 public PSR;
    IOracle public PANOracle;
    IOracle public PSROracle;
    ISwapRouter02 public swapRouter;
    IUserLevel public userLevel;
    IAvatar public avatar;

    address[] public PANToPSR;
    uint256 public startTime;
    uint256 public pandoBoxPerDay;
    uint256 public createPandoBoxFee;
    uint256 public upgradeBaseFee;
    uint256 public nRequest;
    uint256 public PSRRatio = 8000;
    uint256 public slippage = 8000;
    uint256 public blockConfirmations = 3;

    modifier onlyUserLevel() {
        require(msg.sender == address(userLevel), "NFTRouter: only user level");
        _;
    }
    /*----------------------------INITIALIZE----------------------------*/

    constructor (
        address _pandoBox,
        address _droidBot,
        address _PAN,
        address _PSR,
        address _pandoPot,
        address _dataStorage,
        address _PANOracle,
        address _PSROracle,
        address _swapRouter,
        uint256 _startTime
    ) {
        pandoBox = IPandoBox(_pandoBox);
        droidBot = IDroidBot(_droidBot);
        PAN = IERC20(_PAN);
        PSR = IERC20(_PSR);
        pandoPot = IPandoPot(_pandoPot);
        dataStorage = IDataStorage(_dataStorage);
        startTime = _startTime;
        PANOracle = IOracle(_PANOracle);
        PSROracle = IOracle(_PSROracle);
        swapRouter = ISwapRouter02(_swapRouter);
        PRECISION = dataStorage.getSampleSpace();
    }

    /*----------------------------INTERNAL FUNCTIONS----------------------------*/

    function _getPandoBoxLv(uint256 _rand) internal view returns (uint256) {
        uint256[] memory _creatingProbability = dataStorage.getPandoBoxCreatingProbability();
        uint256 _cur = 0;
        for (uint256 i = 0; i < _creatingProbability.length; i++) {
            _cur += _creatingProbability[i];
            if (_cur >= _rand) {
                return i;
            }
        }
        return 0;
    }

    function _getNewBotLv(uint256 _boxLv, uint256 _rand, uint256 _salt) internal view returns (uint256, uint256) {
        uint256[] memory _creatingProbability = dataStorage.getDroidBotCreatingProbability(_boxLv);
        uint256 _cur = 0;
        for (uint256 i = 0; i < _creatingProbability.length; i++) {
            _cur += _creatingProbability[i];
            if (_cur >= _rand) {
                uint256 _power = dataStorage.getDroidBotPower(i, _salt);
                return (i, _power);
            }
        }
        return (0, 0);
    }

    function _getUpgradeBotLv(uint256 _bot0Lv, uint256 _bot1Lv, uint256 _rand, uint256 _salt) internal view returns (uint256, uint256){
        uint256[] memory _evolvingProbability = dataStorage.getDroidBotUpgradingProbability(_bot0Lv, _bot1Lv);
        uint256 _cur = 0;
        for (uint256 i = 0; i < _evolvingProbability.length; i++) {
            _cur += _evolvingProbability[i];
            if (_cur >= _rand) {
                uint256 _power = dataStorage.getDroidBotPower(i, _salt);
                return (i, _power);
            }
        }
        return (0, 0);
    }

    function _getBonus(uint256 _value) internal view returns (uint256) {
        if (address(userLevel) != address(0)) {
            (uint256 _n, uint256 _d) = userLevel.getBonus(msg.sender, address(this));
            return _value * _n / _d;
        }
        return 0;
    }

    function _computerSeed() internal view returns (uint256) {
        uint256 seed =
        uint256(
            keccak256(
                abi.encodePacked(
                    (block.timestamp)
                    + block.gaslimit
                    + uint256(keccak256(abi.encodePacked(blockhash(block.number)))) / (block.timestamp)
                    + uint256(keccak256(abi.encodePacked(block.coinbase))) / (block.timestamp)
                    + (uint256(keccak256(abi.encodePacked(tx.origin)))) / (block.timestamp)
                )
            )
        );
        return seed;
    }

    function _getNumberOfTicket(RequestType _type, uint256[] memory _data) internal view returns (uint256){
        if (_type == RequestType.CREATE) {
            return dataStorage.getNumberOfTicket(_data[0]);
        } else {
            if (_type == RequestType.UPGRADE) {
                return dataStorage.getNumberOfTicket(_data[1]);
            }
        }
        return 0;
    }

    function _createRequest(RequestType _type, uint256[] memory _data, address _user) internal {
        nRequest++;
        uint256 _requestId = nRequest;
        requests[_requestId] = Request({
            id : _requestId,
            createdAt : block.number,
            seed : _computerSeed() % PRECISION + 1,
            data : _data,
            rType : _type,
            status : RequestStatus.AVAILABLE
        });
        EnumerableSet.UintSet storage _userRequest = userRequests[_user];
        _userRequest.add(_requestId);
        emit RequestCreated(_user, _type, _requestId, block.number, _data);
    }

    function _executeRequest(uint256 _id, bytes32 _blockHash, address _receiver) internal {
        Request storage _request = requests[_id];
        require(_request.status == RequestStatus.AVAILABLE, 'NFTRouter: request unavailable');
        require(block.number >= _request.createdAt + blockConfirmations, 'NFTRouter: not enough confirmations');

        _request.status = RequestStatus.EXECUTED;

        uint256 _rand = (uint256(keccak256(abi.encodePacked(_blockHash))) % PRECISION + 1) * _request.seed % PRECISION;
        uint256 _salt = (uint256(keccak256(abi.encodePacked(_blockHash))) % PRECISION + 1) * _request.seed / PRECISION % PRECISION;

        uint256 _r3 = (uint256(keccak256(abi.encodePacked(_blockHash))) % PRECISION + 1) * _request.seed / PRECISION / PRECISION % PRECISION;
        if (_r3 == 0) {
            _r3 = _rand;
        }
        uint256 _r4 = (uint256(keccak256(abi.encodePacked(_blockHash))) % PRECISION + 1) * _request.seed / PRECISION / PRECISION / PRECISION % PRECISION;
        if (_r4 == 0) {
            _r4 = _salt;
        }

        if (_request.rType == RequestType.BUY) {
            uint256 _lv = _getPandoBoxLv(_rand);
            uint256 newBoxId = pandoBox.create(_receiver, _lv);
            emit BoxCreated(_receiver, _lv, _request.data[0], newBoxId);
        } else {
            if (_request.rType == RequestType.CREATE) {
                (uint256 _lv, uint256 _power) = _getNewBotLv(_request.data[0], _rand, _salt);
                uint256 newBotId = droidBot.create(_receiver, _lv, _power);
                emit BotCreated(_receiver, _request.data[1], newBotId);
            } else {
                if (_request.rType == RequestType.UPGRADE) {
                    (uint256 _lv, uint256 _power) = _getUpgradeBotLv(_request.data[0], _request.data[1], _rand, _salt);
                    if (_lv > _request.data[0]) {
                        droidBot.upgrade(_request.data[2], _lv, _power);
                    }
                    emit BotUpgraded(_receiver, _request.data[2], _request.data[3]);
                } else {
                    if (_request.rType == RequestType.AVATAR) {
                        uint id_ = avatar.create(msg.sender, _request.data[0], _rand);
                        if (id_ == 0) {
                            revert("NFTRouter: duplicate avatar id");
                        }
                        emit RequestExecuted(_id, _receiver);
                        return;
                    }
                }
            }
        }

        uint256 _nTicket = _getNumberOfTicket(_request.rType, _request.data);
        if (block.number - _request.createdAt - blockConfirmations <= 256) {
            if (_request.rType == RequestType.CREATE && address(pandoPot) != address(0)) {
                pandoPot.enter(_receiver, _r3, _nTicket);
            } else {
                if (_request.rType == RequestType.UPGRADE && address(pandoPot) != address(0)) {
                    pandoPot.enter(_receiver, _r4, _nTicket);
                }
            }
        }
        emit RequestExecuted(_id, _receiver);
    }

    /*----------------------------EXTERNAL FUNCTIONS----------------------------*/

    function createPandoBox(uint256 _option) external {
        require(block.timestamp >= startTime, 'Router: not started');
        uint256 _ndays = (block.timestamp - startTime) / 1 days;
        uint256 _createPandoBoxFee = createPandoBoxFee - _getBonus(createPandoBoxFee);
        if (pandoBoxCreated[_ndays] < pandoBoxPerDay) {
            if (_createPandoBoxFee > 0) {
                if (_option == 0) {// only PAN
                    PAN.safeTransferFrom(msg.sender, address(this), _createPandoBoxFee);
                    uint256 _amountSwap = _createPandoBoxFee * (ONE_HUNDRED_PERCENT - PSRRatio) / ONE_HUNDRED_PERCENT;
                    uint256[] memory _amounts = swapRouter.getAmountsOut(_amountSwap, PANToPSR);
                    uint256 _minAmount = _amounts[_amounts.length - 1] * slippage / ONE_HUNDRED_PERCENT;
                    IERC20(PAN).safeApprove(address(swapRouter), _amountSwap);
                    swapRouter.swapExactTokensForTokens(_amountSwap, _minAmount, PANToPSR, address(this), block.timestamp + 300);
                    ERC20Burnable(address(PAN)).burn(PAN.balanceOf(address(this)));
                    ERC20Burnable(address(PSR)).burn(PSR.balanceOf(address(this)));
                } else {
                    uint256 _price_PAN = PANOracle.consult();
                    uint256 _price_PSR = PSROracle.consult();

                    uint256 _amount_PSR = _createPandoBoxFee * (ONE_HUNDRED_PERCENT - PSRRatio) / ONE_HUNDRED_PERCENT * _price_PAN / _price_PSR;
                    ERC20Burnable(address(PAN)).burnFrom(msg.sender, _createPandoBoxFee * PSRRatio / ONE_HUNDRED_PERCENT);
                    ERC20Burnable(address(PSR)).burnFrom(msg.sender, _amount_PSR);
                }
            }
            pandoBoxCreated[_ndays]++;
            uint256[] memory _data = new uint[](1);
            _data[0] = _option;
            _createRequest(RequestType.BUY, _data, msg.sender);
        }
    }

    function createDroidBot(uint256 _pandoBoxId) external {
        if (pandoBox.ownerOf(_pandoBoxId) == msg.sender) {
            pandoBox.burn(_pandoBoxId);
            NFTLib.Info memory _info = pandoBox.info(_pandoBoxId);

            uint256[] memory _data = new uint[](2);
            _data[0] = _info.level;
            _data[1] = _pandoBoxId;
            _createRequest(RequestType.CREATE, _data, msg.sender);
        }
    }

    function upgradeDroidBot(uint256 _droidBot0Id, uint256 _droidBot1Id) external {
        require(droidBot.ownerOf(_droidBot0Id) == msg.sender && droidBot.ownerOf(_droidBot1Id) == msg.sender, 'NFTRouter : not owner of bot');
        uint256 _l0 = droidBot.level(_droidBot0Id);
        uint256 _l1 = droidBot.level(_droidBot1Id);
        uint256 _id0 = _droidBot0Id;
        uint256 _id1 = _droidBot1Id;
        if (_l0 < _l1) {
            _id0 = _droidBot1Id;
            _id1 = _droidBot0Id;
        }
        NFTLib.Info memory _info0 = droidBot.info(_id0);
        NFTLib.Info memory _info1 = droidBot.info(_id1);

        uint256 _upgradeFee = upgradeBaseFee * (15 ** _info1.level) / (10 ** _info1.level);
        _upgradeFee -= _getBonus(_upgradeFee);
        if (_upgradeFee > 0) {
            ERC20Burnable(address(PSR)).burnFrom(msg.sender, _upgradeFee);
        }

        droidBot.burn(_id1);
        uint256[] memory _data = new uint[](4);
        _data[0] = _info0.level;
        _data[1] = _info1.level;
        _data[2] = _id0;
        _data[3] = _id1;
        _createRequest(RequestType.UPGRADE, _data, msg.sender);
    }

    function createAvatar(uint256 _lv, address _user) external onlyUserLevel {
        uint256[] memory _data = new uint[](1);
        _data[0] = _lv;
        _createRequest(RequestType.AVATAR, _data, _user);
    }

    function pandoBoxRemain() external view returns (uint256) {
        uint256 _ndays = (block.timestamp - startTime) / 1 days;
        return pandoBoxPerDay - pandoBoxCreated[_ndays];
    }

    function getValidators() external view returns (address[] memory) {
        return validators.values();
    }

    function pendingRequest(address _user) external view returns (uint256[] memory) {
        return userRequests[_user].values();
    }

    function getRequest(uint256 _id) external view returns (Request memory) {
        return requests[_id];
    }

    function processRequest(uint256 _id, uint256 _blockNum, bytes32 _blockHash, bytes memory _signature) external {
        // latest
        EnumerableSet.UintSet storage _userRequest = userRequests[msg.sender];
        require(_userRequest.length() > 0, 'NFTRouter: empty request');
        bytes32 _hash;
        if (_id == 0) {
            _id = _userRequest.at(_userRequest.length() - 1);
            require(requests[_id].createdAt + 256 + blockConfirmations > block.number, 'NFTRouter: >256 blocks');
            _hash = blockhash(requests[_id].createdAt + blockConfirmations);
        } else {
            require(_userRequest.contains(_id), 'NFTRouter: !exist request');
            if (requests[_id].createdAt + 256 + blockConfirmations <= block.number) {
                _hash = keccak256(abi.encodePacked(address(this), _blockNum, _blockHash)).toEthSignedMessageHash();
                address _signer = _hash.recover(_signature);
                require(validators.contains(_signer), 'NFTRouter: !validator');
                require(requests[_id].createdAt + blockConfirmations == _blockNum, 'NFTRouter: invalid blockNum');
            } else {
                _hash = blockhash(requests[_id].createdAt + blockConfirmations);
            }
        }
        _userRequest.remove(_id);
        _executeRequest(_id, _hash, msg.sender);
    }

    /*----------------------------RESTRICT FUNCTIONS----------------------------*/

    function setPandoBoxPerDay(uint256 _value) external onlyOwner {
        uint256 oldPandoBoxPerDay = pandoBoxPerDay;
        pandoBoxPerDay = _value;
        emit PandoBoxPerDayChanged(oldPandoBoxPerDay, _value);
    }

    function setCreatePandoBoxFee(uint256 _newFee) external onlyOwner {
        uint256 oldCreatePandoBoxFee = createPandoBoxFee;
        createPandoBoxFee = _newFee;
        emit CreateFeeChanged(oldCreatePandoBoxFee, _newFee);
    }

    function setUpgradeBaseFee(uint256 _newFee) external onlyOwner {
        uint256 oldUpgradeBaseFee = upgradeBaseFee;
        upgradeBaseFee = _newFee;
        emit UpgradeFeeChanged(oldUpgradeBaseFee, _newFee);
    }

    function setPandoPotAddress(address _addr) external onlyOwner {
        address oldPandoPot = address(pandoPot);
        pandoPot = IPandoPot(_addr);
        emit PandoPotChanged(oldPandoPot, _addr);
    }

    function setDataStorageAddress(address _addr) external onlyOwner {
        address oldDataStorage = address(dataStorage);
        dataStorage = IDataStorage(_addr);
        emit DataStorageChanged(oldDataStorage, _addr);
    }

    function setPANOracle(address _addr) external onlyOwner {
        address oldPANOracle = address(PANOracle);
        PANOracle = IOracle(_addr);
        emit PANOracleChanged(oldPANOracle, _addr);
    }

    function setPSROracle(address _addr) external onlyOwner {
        address oldPSROracle = address(PSROracle);
        PSROracle = IOracle(_addr);
        emit PSROracleChanged(oldPSROracle, _addr);
    }

    function setPath(address[] memory _path) external onlyOwner {
        address[] memory oldPath = PANToPSR;
        PANToPSR = _path;
        emit PANtoPSRChanged(oldPath, _path);
    }

    function setPSRRatio(uint256 _ratio) external onlyOwner {
        uint256 oldPSRRatio = PSRRatio;
        PSRRatio = _ratio;
        emit PSRRatioChanged(oldPSRRatio, _ratio);
    }

    function setNftAddress(address _droidBot, address _pandoBox) external onlyOwner {
        address oldDroidBot = address(droidBot);
        address oldPandoBox = address(pandoBox);
        droidBot = IDroidBot(_droidBot);
        pandoBox = IPandoBox(_pandoBox);
        emit DroidBotChanged(oldDroidBot, _droidBot);
        emit PandoBoxChanged(oldPandoBox, _pandoBox);
    }

    function setTokenAddress(address _PSR, address _PAN) external onlyOwner {
        address oldPSR = address(PSR);
        address oldPAN = address(PAN);
        PSR = IERC20(_PSR);
        PAN = IERC20(_PAN);
        emit PSRChanged(oldPSR, _PSR);
        emit PANChanged(oldPAN, _PAN);
    }

    function setSwapRouter(address _swapRouter) external onlyOwner {
        address oldSwapRouter = address(swapRouter);
        swapRouter = ISwapRouter02(_swapRouter);
        emit SwapRouterChanged(oldSwapRouter, _swapRouter);
    }

    function setSlippage(uint256 _value) external onlyOwner {
        require(_value <= ONE_HUNDRED_PERCENT, 'NFT Router: > one_hundred_percent');
        uint256 oldSlippage = slippage;
        slippage = _value;
        emit SlippageChanged(oldSlippage, _value);
    }

    function setUserLevelAddress(address _userLevel) external onlyOwner {
        userLevel = IUserLevel(_userLevel);
        emit UserLevelChanged(_userLevel);
    }

    function addValidator(address _validator) public onlyOwner {
        validators.add(_validator);
        emit ValidatorAdded(_validator);
    }

    function removeValidator(address _validator) public onlyOwner {
        validators.remove(_validator);
        emit ValidatorRemoved(_validator);
    }

    function setAvatarAddress(address _avatar) external onlyOwner {
        avatar = IAvatar(_avatar);
        emit AvatarChanged(_avatar);
    }

    /*----------------------------EVENTS----------------------------*/

    event BoxCreated(address indexed receiver, uint256 level, uint256 option, uint256 indexed newBoxId);
    event BotCreated(address indexed receiver, uint256 indexed boxId, uint256 indexed newBotId);
    event BotUpgraded(address indexed user, uint256 indexed bot0Id, uint256 indexed bot1Id);
    event PandoBoxPerDayChanged(uint256 oldPandoBoxPerDay, uint256 newPandoBoxPerDay);
    event CreateFeeChanged(uint256 oldFee, uint256 newFee);
    event UpgradeFeeChanged(uint256 oldFee, uint256 newFee);
    event PandoPotChanged(address indexed oldPandoPot, address indexed newPandoPot);
    event DataStorageChanged(address indexed oldDataStorate, address indexed newDataStorate);
    event PANOracleChanged(address indexed oldPANOracle, address indexed newPANOracle);
    event PSROracleChanged(address indexed oldPSROracle, address indexed newPSROracle);
    event PANtoPSRChanged(address[] oldPath, address[] newPath);
    event PSRRatioChanged(uint256 oldRatio, uint256 newRatio);
    event PandoBoxChanged(address indexed oldPandoBox, address indexed newPandoBox);
    event DroidBotChanged(address indexed oldDroidBot, address indexed newDroidBot);
    event PSRChanged(address indexed oldPSR, address indexed newPSR);
    event PANChanged(address indexed oldPAN, address indexed newPAN);
    event SwapRouterChanged(address indexed oldSwapRouter, address indexed newSwapRouter);
    event SlippageChanged(uint256 oldSlippage, uint256 newSlippage);
    event UserLevelChanged(address indexed userLevel);
    event RequestCreated(address owner, RequestType requestType, uint256 id, uint256 createdAt, uint256[] data);
    event RequestExecuted(uint256 id, address owner);
    event ValidatorAdded(address validator);
    event ValidatorRemoved(address validator);
    event AvatarChanged(address _avatar);
}
