// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IPandoPot {
    function enter(address, uint256, uint256) external;
    function updateLuckyNumber(uint256, uint256, uint256) external;
    function finishRound() external;
    function getRoundDuration() external view returns (uint256);
    function updatePandoPot() external;
}