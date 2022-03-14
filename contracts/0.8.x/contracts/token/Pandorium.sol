//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Pandorium is ERC20Burnable, Ownable {
    uint256 public totalBurned;
    address public minter;

    constructor() ERC20('Pandorium', 'PAN'){
        minter = msg.sender;
    }

    /*----------------------------EXTERNAL FUNCTIONS----------------------------*/

    function burn(uint256 _amount) public override {
        totalBurned += _amount;
        ERC20Burnable.burn(_amount);
    }

    function burnFrom(address _account, uint256 _amount)  public override {
        totalBurned += _amount;
        ERC20Burnable.burnFrom(_account, _amount);
    }

    function mint(address _account, uint256 _amount) public onlyMinter {
        _mint(_account, _amount);
    }

    /*----------------------------RESTRICT FUNCTIONS----------------------------*/

    function changeMinter(address _newMinter) public onlyOwner {
        address _oldMinter = minter;
        minter = _newMinter;
        emit MinterChanged(_oldMinter, _newMinter);
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Pandorium : caller is not the minter");
        _;
    }

    /*----------------------------EVENTS----------------------------*/

    event MinterChanged(address indexed oldMinter, address indexed newMinter);
}
