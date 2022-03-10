//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "../interfaces/IOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MultiOracle is Ownable {
    mapping (address => address) public oracles;

    function setOracle(address _token, address _oracle) external onlyOwner{
        address oldOracle = oracles[_token];
        oracles[_token] = _oracle;
        emit OracleChanged(_token, oldOracle, _oracle);
    }

    function consult(address _token) external view returns(uint256) {
        address oracle = oracles[_token];
        if (oracle != address (0)) {
            return IOracle(oracle).consult();
        }
        return 0;
    }

    event OracleChanged(address indexed _token, address indexed oldOracle, address indexed newOracle);
}