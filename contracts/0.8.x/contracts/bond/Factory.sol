// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BondNFT.sol";
import "./BondStruct.sol";
import "@openzeppelin/contracts/utils/Create2.sol";


contract Factory is BondStruct {
    function createBondNFT(address issuer, string memory _name, string memory _symbol, string memory _uri) external returns (address) {
        bytes memory bytecode = type(BondNFT).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(block.number, issuer));
        address _address = Create2.deploy(0, salt, bytecode);
        bool check = BondNFT(_address).initialize(_uri, _name, _symbol, issuer);
        require(check, "deploy failed");
        return _address;
    }
}
