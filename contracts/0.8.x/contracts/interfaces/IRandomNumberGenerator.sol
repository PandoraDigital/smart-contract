// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IRandomNumberGenerator {
    function computerSeed(uint256) external view returns(uint256);
    function getNumber() external view returns(uint256, uint256, uint256);
}