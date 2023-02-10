// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./IBondNFT.sol";
import "./BondStruct.sol";
import "./IFactory.sol";
import "./IBondRefund.sol";

contract BondRouter is Ownable, BondStruct, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;


    uint256 constant public ONE_HUNDRED_PERCENT = 1e6;
    // System
    address public adminWallet;
    address public refundAddress;

    // Batch
    mapping(uint256 => BatchInfo) private batchInfo;
    uint256 public batchId;
    mapping(uint256 => uint256) private withdraw;

    // pending request
    uint256 private requestId;
    mapping(uint256 => PendingRequest) private requests;
    EnumerableSet.UintSet private listRequestId;

    // nft factory
    address public factory;

    //bond nft address
    IBondNFT public bondNFTAddress = IBondNFT(0xCEa0d0B7BEd63FD0cb898A7bc0D1B0960E7d2f78);

    //fee processing when redeem early
    uint256 public penaltyFee = 1e5;

    //operators
    EnumerableSet.AddressSet private operators;

    /* ===================== Modifiers ===================== */
    modifier onlyOperator() {
        require(operators.contains(msg.sender), "BondRouter: only operator");
        _;
    }


    /* ===================== Events ===================== */
    event UpdateBondPrice(uint256 _batchId, uint256[] _prices, InterestRate[] _rates, bool _action);
    event BuyBond(address _user, uint256 _price, uint256 _quantity, uint256 _batchId);
    event Redeem(address _owner, uint256[] ids, address _receiver, uint256 _totalReceiver, uint256 _batchId);
    event Harvest(address _owner, uint256[] ids, address _receiver, uint256 _totalReceiver, uint256 _batchId);
    event CreateBondNFTAddress(address nft);
    event CreateRequest(PendingRequest _request, uint256 id, uint256 _batchId);
    event ExecuteRequest(PendingRequest _request, uint256 id, uint256 _batchId);
    event UpdateStartTime(uint256 _old, uint256 _new, uint256 _batchId);
    event UpdatePenaltyFee(uint256 _old, uint256 _new);
    event UpdateAdminWallet(address _old, address _new);
    event CreateNewBatch(uint256 _batchId, BatchConfig _config, BackedBond[] _backedBond, uint256[] _prices, InterestRate[] _rates);
    event UpdateOperators(address _operator, bool _action);
    event UpdateBatchStatus(uint256 _bacthId, bool _action);
    event UpdateRefundAddress(address _old, address _new);
    event RedeemInfo(uint256 _id, uint256 _value, uint256 _interest, uint256 _currentValue);

    /* ===================== Constructor ===================== */

    constructor(address _nftFactory, address _adminWallet, address _refundAddress) {
        require(_adminWallet != address(0), "BondRouter: admin wallet not a zero");
        factory = _nftFactory;
        operators.add(_adminWallet);
        operators.add(msg.sender);
        adminWallet = _adminWallet;
        refundAddress = _refundAddress;
    }

    /* ===================== Internal functions ===================== */
    function _payment(address _currency, address _receiver, uint256 _amount) internal {
        IBondRefund(refundAddress).transfer(_currency, _receiver, _amount);
    }

    function _lock(IBondNFT _bond, uint256[] memory _ids) internal {
        _bond.lock(_ids);
    }

    function _unlock(IBondNFT _bond, uint256[] memory _ids) internal {
        _bond.unlock(_ids);
    }

    function _redeem(IBondNFT _bond, uint256[] memory _ids) internal {
        _bond.redeem(_ids);
    }

    function _issue(IBondNFT _bond, address _receiver, uint256 _quantity, uint256 _amount, uint256 _maturity, uint256 _interest, uint256 _batchId) internal {
        _bond.issue(_receiver, _quantity, _amount, _maturity, _interest, _batchId);
    }

    function _calInterest(uint256 _interest, uint256 _lastHarvest, uint256 _maturity, uint256 _startTime) internal view returns (uint256) {
        uint256 _endTime = _min(block.timestamp, _maturity);
        uint256 _start = _max(_lastHarvest, _startTime);
        if (block.timestamp < _startTime) {
            return 0;
        }
        return (_endTime - _start) * _interest / (_maturity - _startTime);
    }

    function _calCurrentRate(uint256 _start, uint256 _end, InterestRate memory _rate) internal view returns (uint256) {
        uint256 _timeStamp = _max(_start, block.timestamp);
        return (_rate.max - (((_rate.max - _rate.min) * (_timeStamp - _start)) / (_end - _start)));
    }

    function _createPendingRequest(RequestType _requestType, address _receiver, uint256 _amount, uint256[] memory _ids, uint256 _batchId) internal {
        requestId++;
        requests[requestId].requestType = _requestType;
        requests[requestId].status = RequestStatus.PENDING;
        requests[requestId].to = _receiver;
        requests[requestId].amount = _amount;
        requests[requestId].tokenIds = _ids;
        requests[requestId].createdAt = block.timestamp;
        requests[requestId].batchId = _batchId;
        listRequestId.add(requestId);
        emit CreateRequest(requests[requestId], requestId, _batchId);
    }

    function _updateLastHarvest(IBondNFT _bond, uint256[] memory ids) internal {
        _bond.updateLastHarvest(ids, msg.sender);
    }

    function _updateLastHarvest(uint256 _id) internal {
        uint256[] memory _updateId = new uint256[](1);
        _updateId[0] = _id;
        _updateLastHarvest(bondNFTAddress, _updateId);
    }

    function _executeRequest(uint256 _requestId) internal {
        PendingRequest storage _request = requests[_requestId];

        //        IERC20(batchInfo[_request.batchId].config.currency).safeTransfer(_request.to, _request.amount);
        _payment(batchInfo[_request.batchId].config.currency, _request.to, _request.amount);
        if (_request.requestType == RequestType.REDEEM) {
            _unlock(bondNFTAddress, _request.tokenIds);
            _redeem(bondNFTAddress, _request.tokenIds);
        }
        _request.status = RequestStatus.EXECUTED;
        listRequestId.remove(_requestId);
        emit ExecuteRequest(_request, _requestId, _request.batchId);
    }

    function _buyBond(uint256 _batchId, uint256 _price, uint256 _quantity) internal {
        require(_batchId > 0 && _batchId <= batchId, "BondRouter: !_batchId");
        BatchInfo storage _batchInfo = batchInfo[_batchId];
        require(_batchInfo.bondPrice.contains(_price), "BondRouter: _price not support");
        require(_batchInfo.status, "BondRouter: !active");
        require(block.timestamp < _batchInfo.config.maturity, "BondRouter: !maturity");

        //check input
        uint256 _amountTransfer = _price * _quantity;
        require(_quantity > 0 && _amountTransfer + _batchInfo.raised <= _batchInfo.config.totalFundRaise, "BatchFactory: not valid quantity");

        //transfer fund
        IERC20(_batchInfo.config.currency).safeTransferFrom(msg.sender, adminWallet, _amountTransfer);

        _batchInfo.raised += _amountTransfer;

        uint256 _currentRate = _calCurrentRate(_batchInfo.config.startTime, _batchInfo.config.maturity, _batchInfo.interestRates[_price]);

        uint256 _interest = _price * _currentRate / ONE_HUNDRED_PERCENT;
        //issue bond nft
        _issue(bondNFTAddress, msg.sender, _quantity, _price, _batchInfo.config.maturity, _interest, _batchId);

        emit BuyBond(msg.sender, _price, _quantity, _batchId);
    }

    function _calAmount(uint256 _tokenId, uint256 _batchId, uint256 _startTime) internal view returns (uint256 _interest, uint256 _bondAmount, uint256 _amountBack) {
        BondInfo memory _info = bondNFTAddress.info(_tokenId);
        require(_batchId == _info.batchId, "Batch: !batch id");
        if (_info.lastHarvest <= _info.maturity) {
            _interest += _calInterest(_info.interest, _info.lastHarvest, _info.maturity, _startTime);
        }
        if (_info.maturity > block.timestamp) {
            _bondAmount += _info.amount * (ONE_HUNDRED_PERCENT - penaltyFee) / ONE_HUNDRED_PERCENT;
            _amountBack += _info.amount;
        } else {
            _bondAmount += _info.amount;
        }
    }

    function _executeRedeem(uint256 _batchId, uint256[] memory _ids, address _to) internal {
        require(_batchId > 0 && _batchId <= batchId, "BondRouter: !_batchId");
        BatchInfo storage _info = batchInfo[_batchId];
        uint256 _amountSent = 0;
        uint256 _amountRefund = 0;
        for (uint256 i = 0; i < _ids.length; i++) {
            (uint256 _interestAmount, uint256 _totalAmount, uint256 _amountBack) = _calAmount(_ids[i], _batchId, _info.config.startTime);
            _amountSent += (_totalAmount + _interestAmount);
            _amountRefund += _amountBack;
            _updateLastHarvest(_ids[i]);
            emit RedeemInfo(_ids[i], _amountBack, _interestAmount, _totalAmount);
        }
        if (_amountRefund > 0) {
            _info.raised -= _amountRefund;
        }

        _lock(bondNFTAddress, _ids);
        _createPendingRequest(RequestType.REDEEM, _to, _amountSent, _ids, _batchId);

        emit Redeem(msg.sender, _ids, _to, _amountSent, _batchId);
    }

    function _executeHarvest(uint256 _batchId, uint256[] memory _ids, address _to) internal {
        require(_batchId > 0 && _batchId <= batchId, "BondRouter: !_batchId");

        // calculate amount interest
        BatchConfig memory _info = batchInfo[_batchId].config;
        require(block.timestamp >= _info.startTime, "BondRouter: can not harvest now");

        uint256 _amountSent = 0;
        for (uint256 i = 0; i < _ids.length; i++) {
            (uint256 _interestAmount,,) = _calAmount(_ids[i], _batchId, _info.startTime);
            _amountSent += _interestAmount;
            _updateLastHarvest(_ids[i]);
        }
        //        _createPendingRequest(RequestType.HARVEST, _to, _amountSent, _ids, _batchId);
        _payment(_info.currency, msg.sender, _amountSent);

        emit Harvest(msg.sender, _ids, _to, _amountSent, _batchId);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /* ===================== External functions ===================== */

    //deposit funds and get bond
    function buyBond(BuyingInfo[] memory _buyInfo) external whenNotPaused {
        for (uint256 i = 0; i < _buyInfo.length; i++) {
            _buyBond(_buyInfo[i].batchId, _buyInfo[i].price, _buyInfo[i].quantity);
        }
    }


    // take profit and refund or create request harvest
    function redeem(ClaimInfo[] memory _info, address _to) external whenNotPaused nonReentrant {
        for (uint256 i = 0; i < _info.length; i++) {
            _executeRedeem(_info[i].batchId, _info[i].ids, _to);
        }
    }

    // take profit or create request harvest
    function harvest(ClaimInfo[] memory _info, address _to) external whenNotPaused nonReentrant {
        for (uint256 i = 0; i < _info.length; i++) {
            _executeHarvest(_info[i].batchId, _info[i].ids, _to);
        }
    }


    /* ===================== View functions ===================== */
    function getBatch(uint256 _batchId) external view returns (BatchInfoResponse memory) {

        uint256 length = batchInfo[_batchId].bondPrice.length();
        InterestRate[] memory interestRate = new InterestRate[](length);
        for (uint256 i = 0; i < length; i++) {
            interestRate[i] = batchInfo[_batchId].interestRates[batchInfo[_batchId].bondPrice.at(i)];
        }
        BatchInfoResponse memory response = BatchInfoResponse(
        {
        raised : batchInfo[_batchId].raised,
        bondPrice : batchInfo[_batchId].bondPrice.values(),
        backedBond : batchInfo[_batchId].backedBond,
        config : batchInfo[_batchId].config,
        status : batchInfo[_batchId].status,
        interestRate : interestRate
        });
        return response;
    }

    function getPendingRequest(uint256 _page, uint256 _limit) external view returns (uint256[] memory, uint256 _length) {
        uint256 _from = _page * _limit;
        _length = listRequestId.length();
        uint256 _to = _min((_page + 1) * _limit, listRequestId.length());
        uint256[] memory _result = new uint256[](_to - _from);
        for (uint256 i = 0; _from < _to; i++) {
            _result[i] = listRequestId.at(_from);
            ++_from;
        }
        return (_result, _length);
    }

    function getRequest(uint256 _requestId) external view returns (PendingRequest memory) {
        return requests[_requestId];
    }

    function getClaimable(uint256[] memory _ids) external view returns (uint256 _result) {
        for (uint256 i = 0; i < _ids.length; i++) {
            BondInfo memory _info = bondNFTAddress.info(_ids[i]);
            BatchConfig memory _config = batchInfo[_info.batchId].config;
            (uint256 _interestAmount,,) = _calAmount(_ids[i], _info.batchId, _config.startTime);
            _result += _interestAmount;
        }
        return _result;
    }

    function getCurrentRate(uint256 _start, uint256 _end, InterestRate memory _rate) external view returns (uint256) {
        return _calCurrentRate(_start, _end, _rate);
    }

    function getOperators() external view returns(address[] memory) {
        return operators.values();
    }

    /* ===================== Restrict Access ===================== */
    //    function createBondNFT(string memory _name, string memory _symbol, string memory _uri) external onlyOwner {
    //        require(address(bondNFTAddress) == address(0), "BondRouter: created");
    //        bondNFTAddress = IBondNFT(IFactory(factory).createBondNFT(address(this), _name, _symbol, _uri));
    //        emit CreateBondNFTAddress(address(bondNFTAddress));
    //    }


    function createBatch(BatchConfig memory _config, BackedBond[] memory _backedBond, uint256[] memory _prices, InterestRate[] memory _rates, bool _active)
    external onlyOperator {
        batchId ++;
        require(_config.startTime > block.timestamp, "BondRouter: start time < now");
        require(_config.maturity > _config.startTime, "BondRouter: maturity < start time");
        require(_prices.length == _rates.length, "BondRouter: !length");
        batchInfo[batchId].config = _config;
        for (uint256 i = 0; i < _backedBond.length; i++) {
            batchInfo[batchId].backedBond.push(_backedBond[i]);
        }

        //default
        if (_prices.length > 0) {
            for (uint256 i = 0; i < _prices.length; i++) {
                InterestRate memory _rate = _rates[i];
                require(_rate.max <= ONE_HUNDRED_PERCENT && _rate.min <= ONE_HUNDRED_PERCENT, "BondRouter: greater than ONE_HUNDRED_PERCENT");
                require(_rate.max >= _rate.min, "BondRouter: Max rate must greater min rate");
                batchInfo[batchId].bondPrice.add(_prices[i]);
                batchInfo[batchId].interestRates[_prices[i]] = _rate;
            }
        } else {
            batchInfo[batchId].bondPrice.add(100 ether);
            batchInfo[batchId].bondPrice.add(500 ether);
            batchInfo[batchId].bondPrice.add(1000 ether);
            batchInfo[batchId].bondPrice.add(5000 ether);
            batchInfo[batchId].bondPrice.add(10000 ether);

            batchInfo[batchId].interestRates[100 ether] = InterestRate({max : 100000, min : 50000});
            // 10%
            batchInfo[batchId].interestRates[500 ether] = InterestRate({max : 105000, min : 52500});
            // 12%
            batchInfo[batchId].interestRates[1000 ether] = InterestRate({max : 108000, min : 54000});
            // 14%
            batchInfo[batchId].interestRates[5000 ether] = InterestRate({max : 110000, min : 55000});
            batchInfo[batchId].interestRates[10000 ether] = InterestRate({max : 115000, min : 57500});
            // 16%
        }
        batchInfo[batchId].status = _active;
        emit CreateNewBatch(batchId, _config, _backedBond, batchInfo[batchId].bondPrice.values(), _rates);
    }

    function addOldBatch(BatchConfig memory _config, BackedBond[] memory _backedBond, uint256[] memory _prices, InterestRate[] memory _rates, bool _active)
    external onlyOperator {

        batchId ++;
        require(_prices.length == _rates.length, "BondRouter: !length");
        batchInfo[batchId].config = _config;
        for (uint256 i = 0; i < _backedBond.length; i++) {
            batchInfo[batchId].backedBond.push(_backedBond[i]);
        }

        //default
        if (_prices.length > 0) {
            for (uint256 i = 0; i < _prices.length; i++) {
                InterestRate memory _rate = _rates[i];
                require(_rate.max <= ONE_HUNDRED_PERCENT && _rate.min <= ONE_HUNDRED_PERCENT, "BondRouter: greater than ONE_HUNDRED_PERCENT");
                require(_rate.max >= _rate.min, "BondRouter: Max rate must greater min rate");
                batchInfo[batchId].bondPrice.add(_prices[i]);
                batchInfo[batchId].interestRates[_prices[i]] = _rate;
            }
        } else {
            batchInfo[batchId].bondPrice.add(100 ether);
            batchInfo[batchId].bondPrice.add(500 ether);
            batchInfo[batchId].bondPrice.add(1000 ether);
            batchInfo[batchId].bondPrice.add(5000 ether);
            batchInfo[batchId].bondPrice.add(10000 ether);

            batchInfo[batchId].interestRates[100 ether] = InterestRate({max : 100000, min : 50000});
            // 10%
            batchInfo[batchId].interestRates[500 ether] = InterestRate({max : 105000, min : 52500});
            // 12%
            batchInfo[batchId].interestRates[1000 ether] = InterestRate({max : 108000, min : 54000});
            // 14%
            batchInfo[batchId].interestRates[5000 ether] = InterestRate({max : 110000, min : 55000});
            batchInfo[batchId].interestRates[10000 ether] = InterestRate({max : 115000, min : 57500});
            // 16%
        }
        batchInfo[batchId].status = _active;
        emit CreateNewBatch(batchId, _config, _backedBond, batchInfo[batchId].bondPrice.values(), _rates);
    }

    function updateBondPrice(uint256 _batchId, uint256[] memory _prices, InterestRate[] memory _rates, bool _action) external onlyOperator {
        require(_batchId > 0 && _batchId <= batchId, "BondRouter: !_batchId");
        BatchInfo storage _info = batchInfo[_batchId];

        for (uint256 i = 0; i < _prices.length; i++) {
            if (_action) {
                InterestRate memory _rate = _rates[i];
                require(_prices.length == _rates.length, "BondRouter: invalid length");
                require(_info.bondPrice.add(_prices[i]), "BondRouter: !added");
                require(_rate.max <= ONE_HUNDRED_PERCENT && _rate.min <= ONE_HUNDRED_PERCENT, "BondRouter: greater than ONE_HUNDRED_PERCENT");
                require(_rate.max > _rate.min, "BondRouter: Max rate must greater min rate");
                _info.interestRates[_prices[i]] = _rate;
            } else {
                require(_info.bondPrice.remove(_prices[i]), "BondRouter: !removed");
                _info.interestRates[_prices[i]] = InterestRate({max : 0, min : 0});
            }
        }
        emit UpdateBondPrice(_batchId, _prices, _rates, _action);
    }

    function executeRequest(uint256[] memory _ids) external onlyOperator {
        for (uint256 i = 0; i < _ids.length; i++) {
            require(listRequestId.contains(_ids[i]), "BondRouter: request id not in list");
            _executeRequest(_ids[i]);
        }
    }

    function updateStartTime(uint256 _value, uint256 _batchId) external onlyOperator {
        require(_batchId > 0 && _batchId <= batchId, "BondRouter: !_batchId");
        BatchInfo storage _info = batchInfo[_batchId];
        require(_value >= block.timestamp, "BondRouter: invalid value");
        uint256 _old = _info.config.startTime;
        _info.config.startTime = _value;
        emit UpdateStartTime(_old, _value, _batchId);
    }

    function updatePenaltyFee(uint256 _value) external onlyOperator {
        require(_value < ONE_HUNDRED_PERCENT, "BondRouter: invalid value");
        uint256 _old = penaltyFee;
        penaltyFee = _value;
        emit UpdatePenaltyFee(_old, _value);
    }

    function updateBatchStatus(uint256 _batchId, bool _status) external onlyOperator {
        require(_batchId > 0 && _batchId <= batchId, "BondRouter: !_batchId");
        batchInfo[_batchId].status = _status;
        emit UpdateBatchStatus(_batchId, _status);
    }

    function updateAdminWallet(address _value) external onlyOwner {
        require(_value != address(0), "BondRouter: invalid address");
        address _old = adminWallet;
        adminWallet = _value;
        emit UpdateAdminWallet(_old, _value);
    }

    function updateRefundAddress(address _value) external onlyOwner {
        require(_value != address(0), "BondRouter: invalid address");
        address _old = refundAddress;
        refundAddress = _value;
        emit UpdateRefundAddress(_old, _value);
    }

    function updateBatchFundRaised(uint256 _batchId, uint256 _raised) external onlyOwner {
        require(_batchId > 0 && _batchId <= batchId, "SecurityRouter: !_batchId");
        BatchInfo storage _batch = batchInfo[_batchId];
        _batch.raised +=  _raised;
    }

    function updateOperators(address _operator, bool _action) external onlyOwner {
        require(_operator != address(0), "BondRouter: !zero address");
        if (_action) {
            require(operators.add(_operator), "BondRouter: added");
        } else {
            require(operators.remove(_operator), "BondRouter: removed");
        }
        emit UpdateOperators(_operator, _action);
    }

    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() external whenPaused onlyOwner {
        _unpause();
    }
}
