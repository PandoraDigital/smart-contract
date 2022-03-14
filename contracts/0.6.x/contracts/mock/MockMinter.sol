// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "./MockERC20.sol";

contract MockMinter {
    MockERC20 public tokenReward;

    constructor(MockERC20 _reward) public {
        tokenReward = _reward;
    }
    function transfer(address _receiver, uint _amount) external {
        tokenReward.mint(_receiver, _amount);
    }
}
