//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


contract TimeLockV2 is AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WALLET_ROLE = keccak256("WALLET_ROLE");
    uint256 internal constant _DONE_TIMESTAMP = uint256(1);

    mapping(bytes32 => uint256) private confirmations;
    mapping(bytes32 => uint256) private _timestamps;
    mapping(bytes32 => mapping(address => bool)) private isConfirmed;
    mapping(bytes32 => bool) private isCanceled;
    mapping(bytes32 => address) private proposers;

    uint256 public required;
    uint256 public minDelay;
    uint256 public nAdmins;

    constructor(address _admin, uint256 _minDelay) {
        _setupRole(PROPOSER_ROLE, _admin);
        _setupRole(EXECUTOR_ROLE, _admin);
        _setupRole(ADMIN_ROLE, _admin);
        _setupRole(WALLET_ROLE, address(this));
        required = 1;
        nAdmins = 1;
        minDelay = _minDelay;
    }

    /* ========== MODIFIERS ========== */
    modifier onlyRoleOrOpenRole(bytes32 role) {
        if (!hasRole(role, address(0))) {
            _checkRole(role, _msgSender());
        }
        _;
    }

    /* ========== PUBLIC FUNCTIONS ========== */
    /**
       * @dev Returns whether an id correspond to a registered operation. This
     * includes both Pending, Ready and Done operations.
     */
    function isOperation(bytes32 id) public view virtual returns (bool pending) {
        return getTimestamp(id) > 0;
    }

    /**
     * @dev Returns whether an operation is pending or not.
     */
    function isOperationPending(bytes32 id) public view virtual returns (bool pending) {
        return getTimestamp(id) > _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns whether an operation is ready or not.
     */
    function isOperationReady(bytes32 id) public view virtual returns (bool ready) {
        uint256 timestamp = getTimestamp(id);
        return timestamp > _DONE_TIMESTAMP && timestamp <= block.timestamp;
    }

    /**
     * @dev Returns whether an operation is done or not.
     */
    function isOperationDone(bytes32 id) public view virtual returns (bool done) {
        return getTimestamp(id) == _DONE_TIMESTAMP;
    }

    function getConfirmation(bytes32 _id) public view returns(uint256 _confirmation) {
        return confirmations[_id];
    }

    function isConfirm(bytes32 _id, address _acc) public view returns(bool) {
        return isConfirmed[_id][_acc];
    }

    function getMinDelay() public view virtual returns (uint256 duration) {
        return minDelay;
    }

    function getTimestamp(bytes32 id) public view virtual returns (uint256 timestamp) {
        return _timestamps[id];
    }

    function getProposer(bytes32 id) public view returns(address proposer) {
        return proposers[id];
    }

    function getStatus(bytes32 id) public view returns(bool status) {
        return isCanceled[id];
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _schedule(bytes32 _id, uint256 _delay) internal {
        require(!isOperation(_id), "Timelock: operation already scheduled");
        require(_delay >= getMinDelay(), "TimelockController: insufficient delay");
        _timestamps[_id] = block.timestamp + _delay;
    }

    function _call(
        bytes32 _id,
        uint256 _index,
        address _target,
        uint256 _value,
        bytes calldata _data
    ) private {
        (bool _success, ) = _target.call{value: _value}(_data);
        require(_success, "Timelock: underlying transaction reverted");
        emit CallExecuted(_id, _index, _target, _value, _data);
    }

    function _hashOperation(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _predecessor,
        bytes32 _salt
    ) public pure virtual returns (bytes32 _hash) {
        return keccak256(abi.encode(_target, _value, _data, _predecessor, _salt));
    }

    function _beforeCall(bytes32 _id, bytes32 _predecessor) private view {
        require(isOperationReady(_id), "Timelock: operation is not ready");
        require(_predecessor == bytes32(0) || isOperationDone(_predecessor), "TimelockController: missing dependency");
    }


    function _afterCall(bytes32 _id) private {
        require(isOperationReady(_id), "Timelock: operation is not ready");
        _timestamps[_id] = _DONE_TIMESTAMP;
    }

    function _vote(
        bytes32 _id
    ) internal {
        confirmations[_id]++;
        isConfirmed[_id][msg.sender] = true;
    }

    function _execute(
        bytes32 _id,
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _predecessor
    ) internal {
        _beforeCall(_id, _predecessor);
        _call(_id, 0, _target, _value, _data);
        _afterCall(_id);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function schedule(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _predecessor,
        bytes32 _salt,
        uint256 _delay
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 _id = _hashOperation(_target, _value, _data, _predecessor, _salt);
        require(confirmations[_id] == 0, "Timelock: operation already scheduled");
        _vote(_id);
        _schedule(_id, _delay);
        proposers[_id] = msg.sender;
        isCanceled[_id] = false;
        emit Scheduled(_id, _target, _value, _data, _predecessor, _salt, _delay);
    }

    function vote(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _predecessor,
        bytes32 _salt)
    external onlyRole(ADMIN_ROLE){
        bytes32 _id = _hashOperation(_target, _value, _data, _predecessor, _salt);
        require(!isConfirm(_id, msg.sender), "Timelock: admin already voted");
        require(!isCanceled[_id], "Timelock: proposer already canceled");
        _vote(_id);
        emit Voted(_id, _target, _value, _data);
    }

    function execute(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _predecessor,
        bytes32 _salt
    ) external payable onlyRoleOrOpenRole(EXECUTOR_ROLE) {
        bytes32 _id = _hashOperation(_target, _value, _data, _predecessor, _salt);
        require(!isCanceled[_id], "Timelock: proposer already canceled");
        if (confirmations[_id] >= required) {
            _beforeCall(_id, _predecessor);
            _call(_id, 0, _target, _value, _data);
            _afterCall(_id);
        }
    }

    function revoke(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _predecessor,
        bytes32 _salt
    ) external onlyRole(ADMIN_ROLE) {
        bytes32 _id = _hashOperation(_target, _value, _data, _predecessor, _salt);
        require(isConfirm(_id, msg.sender), "Timelock: admin haven't voted yet");
        require(!isCanceled[_id], "Timelock: proposer already canceled");
        isConfirmed[_id][msg.sender] = false;
        confirmations[_id]--;
        emit Revoked(_id, _target, _value, _data);
    }

    function cancel(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _predecessor,
        bytes32 _salt
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 _id = _hashOperation(_target, _value, _data, _predecessor, _salt);
        require(msg.sender == proposers[_id], "Timelock: !proposer");
        require(!isCanceled[_id], "Timelock: proposer already canceled");
        isCanceled[_id] = true;
        emit Cancel(_id, true);
    }

    function changeRequired(uint256 _newValue) external onlyRole(WALLET_ROLE) {
        require(_newValue > 0, "Timelock: required = 0");
        require(_newValue <= nAdmins, "Timelock: > nAdmins");
        uint256 oldValue = required;
        required = _newValue;
        emit RequiredChanged(oldValue, _newValue);
    }

    function changeMinDelay(uint256 _newDelay) external onlyRole(WALLET_ROLE){
        require(_newDelay > 0, "Timelock: minDelay = 0");
        uint256 oldValue = minDelay;
        minDelay = _newDelay;
        emit MinDelayChanged(oldValue, _newDelay);
    }

    function grantRole(bytes32 _role, address _account) public override onlyRole(WALLET_ROLE) {
        require(_role != WALLET_ROLE, "Cant add Wallet role");
        if (_role == ADMIN_ROLE && !hasRole(_role, _account)) {
            nAdmins++;
        }
        _grantRole(_role, _account);
    }

    function revokeRole(bytes32 _role, address _account) public override onlyRole(WALLET_ROLE) {
        require(_role != WALLET_ROLE, "Cant revoke wallet role");
        if (_role == ADMIN_ROLE && hasRole(_role, _account)) {
            nAdmins--;
        }
        _revokeRole(_role, _account);
    }
    /* ========== EVENTS ========== */
    event Voted(bytes32 indexed id, address target, uint256 value, bytes data);
    event Scheduled(bytes32 indexed id, address target, uint256 value, bytes data, bytes32 predecessor, bytes32 salt, uint256 delay);
    event Revoked(bytes32 indexed id, address target, uint256 value, bytes data);
    event RequiredChanged(uint256 oldRequired, uint256 newRequired);
    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);
    event MinDelayChanged(uint256 oldMinDelay, uint256 newMinDelay);
    event Cancel(bytes32 indexed id, bool status);

}
