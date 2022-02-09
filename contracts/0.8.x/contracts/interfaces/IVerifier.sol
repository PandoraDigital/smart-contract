// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IVerifier {
    function verify(address _user, uint256 _totalToken, uint256 _claimTimes) external view returns(uint,bool,bool);
}
