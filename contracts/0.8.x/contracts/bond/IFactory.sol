// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BondStruct.sol";

interface IFactory is BondStruct {
    function createBondNFT(address issuer, string memory _name, string memory _symbol, string memory _uri) external returns (address);
}
