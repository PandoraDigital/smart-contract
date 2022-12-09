// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BondStruct.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBondNFT is BondStruct, IERC721 {
    function info(uint256 id) external view returns (BondInfo memory _info);

    function unlock(uint256[] memory tokenIds) external;

    function lock(uint256[] memory tokenIds) external;

    function redeem(uint256[] memory tokenIds) external;

    function issue(address receiver_, uint256 quantity_, uint256 amount_, uint256 maturity_, uint256 interest_, uint256 _batchId) external;

    function updateLastHarvest(uint256[] memory tokenIds, address user) external;

    function currentSupply() external view returns (uint256);

    function updateIssuer(address _new) external;
}
