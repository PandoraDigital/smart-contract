// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPandoPot.sol";

contract RandomNumberGenerator is VRFConsumerBaseV2, Ownable {
    VRFCoordinatorV2Interface COORDINATOR;
    LinkTokenInterface LINK_TOKEN;

    // see https://docs.chain.link/docs/vrf-contracts/#configurations
    address vrfCoordinator = 0xc587d9053cd1118f25F645F9E08BB98c9712A4EE;
    address link_token_contract = 0x404460C6A5EdE2D891e8297795264fDe62ADBB75;
    bytes32 keyHash = 0xba6e730de88d94a5510ae6613898bfb0c3de5d16e609c5b7da808747125506f7;

    // A reasonable default is 100000, but this value could be different on other networks.
    uint32 callbackGasLimit = 2500000;
    uint16 requestConfirmations = 3;
    uint32 public numWords = 3;

    uint256 constant PRECISION = 1e20;

    // Storage parameters
    uint256[] public s_randomWords;
    uint256 public s_requestId;
    uint64 private s_subscriptionId;
    IPandoPot public pandoPot;
    address public operator;
    uint256 public lastUpdateResult;

    bool public lockFullFill = true;

    constructor(address _pandoPot) VRFConsumerBaseV2(vrfCoordinator) {
        pandoPot = IPandoPot(_pandoPot);
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        LINK_TOKEN = LinkTokenInterface(link_token_contract);
        //Create a new subscription when you deploy the contract.
        createNewSubscription();
        s_randomWords = [0, 0, 0];
        operator = msg.sender;
    }

    modifier onlyOperator {
        require(msg.sender == operator, 'RandomNumberGenerator: !operator');
        _;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    function getNumber() external view returns(uint256, uint256, uint256) {
        return (s_randomWords[0], s_randomWords[1], s_randomWords[2]);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;
        pandoPot.finishRound();
        lastUpdateResult = block.timestamp;
        lockFullFill = true;
    }

    function setLockFullFill(bool status) external onlyOperator{
        lockFullFill = status;
    }

    // Create a new subscription when the contract is initially deployed.
    function createNewSubscription() internal {
        // Create a subscription with a new subscription ID.
        address[] memory consumers = new address[](1);
        consumers[0] = address(this);
        s_subscriptionId = COORDINATOR.createSubscription();
        // Add this contract as a consumer of its own subscription.
        COORDINATOR.addConsumer(s_subscriptionId, consumers[0]);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    // Assumes the subscription is funded sufficiently.
    function requestRandomWords() external onlyOperator {
        // Will revert if subscription is not set and funded.
        require(lockFullFill, "RNG: Waiting for full fill!");
        require(block.timestamp >= lastUpdateResult + pandoPot.getRoundDuration(), 'RNG: < roundDuration');
        s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        pandoPot.updatePandoPot();
        lockFullFill = false;
    }

    // Assumes this contract owns link.
    // 1000000000000000000 = 1 LINK
    function topUpSubscription(uint256 amount) external onlyOwner {
        LINK_TOKEN.transferAndCall(address(COORDINATOR), amount, abi.encode(s_subscriptionId));
    }

    function cancelSubscription(address receivingWallet) external onlyOwner {
        // Cancel the subscription and send the remaining LINK to a wallet address.
        COORDINATOR.cancelSubscription(s_subscriptionId, receivingWallet);
        s_subscriptionId = 0;
    }

    // Transfer this contract's funds to an address.
    // 1000000000000000000 = 1 LINK
    function withdraw(uint256 amount, address to) external onlyOwner {
        LINK_TOKEN.transfer(to, amount);
    }

    function changeNumWords(uint32 _numWords) external onlyOwner {
        require(_numWords >= 3, 'RNG: numWords < 3');
        numWords = _numWords;
    }

    function changePandoPot(address _pandoPot) external onlyOwner {
        address _oldPandoPot = address(pandoPot);
        pandoPot = IPandoPot(_pandoPot);
        emit PandoPotChanged(_oldPandoPot, _pandoPot);
    }

    function setOperator(address _newOperator) external onlyOwner {
        address _oldOperator = operator;
        operator = _newOperator;
        emit OperatorChanged(_oldOperator, _newOperator);
    }

    event OperatorChanged(address oldOperator, address newOperator);
    event PandoPotChanged(address oldPandoPot, address newPandoPot);
}