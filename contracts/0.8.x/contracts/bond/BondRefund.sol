// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract BondRefund is Ownable, Pausable,  ReentrancyGuard{
    using SafeERC20 for IERC20;

    mapping(address => bool) public whiteListBond;

    modifier onlyWhiteList () {
        require(whiteListBond[msg.sender], "BondRefund: only bond in whitelist");
        _;
    }

    address constant public BNB = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setWhiteList(address _bond, bool _status) external onlyOwner {
        whiteListBond[_bond] = _status;
    }

    function rescureFund(address _erc20, address payable _to) external payable onlyOwner {
        if(_erc20 == BNB) {
            (bool _sent,) = _to.call{value: address(this).balance}("");
            require(_sent, "AggregatorExecutor: Failed to send BNB");
        } else {
            IERC20(_erc20).safeTransfer(_to, IERC20(_erc20).balanceOf(address(this)));
        }
    }

    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() external whenPaused onlyOwner {
        _unpause();
    }

    function transfer(address _erc20, address _receiver, uint256 _amount) external onlyWhiteList nonReentrant whenNotPaused {
        IERC20(_erc20).safeTransfer(_receiver, _amount);
    }

}
