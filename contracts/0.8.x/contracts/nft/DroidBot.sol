// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../libraries/Random.sol";
import "../libraries/NFTLib.sol";
import "../interfaces/IDataStorage.sol";

contract DroidBot is ERC721Burnable, Ownable {
    address public minter;
    uint256 public totalSupply;
    mapping (uint256 => NFTLib.Info) public nftInfo;
    string baseURI;

    /*----------------------------CONSTRUCTOR----------------------------*/

    constructor(string memory _URI) ERC721("DroidBot NFT Token", "DBOT") {
        baseURI = _URI;
    }

    function _baseURI() internal view override returns(string memory) {
        return baseURI;
    }

    /*----------------------------EXTERNAL FUNCTIONS----------------------------*/

    function create(address _receiver, uint256 _lv, uint256 _power) external onlyMinter returns(uint256 _tokenId) {
        require(_receiver != address(0), 'DroidBotNFT: _receiver is the zero address');
        totalSupply++;
        _tokenId = totalSupply;
        _mint(_receiver, _tokenId);
        nftInfo[_tokenId] = NFTLib.Info({
            level : _lv,
            power : _power
        });
        emit DroidBotCreated(_receiver, _tokenId, _lv, _power);
    }

    function upgrade(uint256 _id, uint256 _lv, uint256 _power) external onlyMinter {
        NFTLib.Info storage _token = nftInfo[_id];
        _token.level = _lv;
        _token.power = _power;
        emit DroidBotUpgraded(_id, _lv, _power);
    }

    function info(uint256 _id) external view returns (NFTLib.Info memory) {
        return nftInfo[_id];
    }

    function power(uint256 _id) external view returns(uint256) {
        return nftInfo[_id].power;
    }

    function level(uint256 _id) external view returns(uint256) {
        return nftInfo[_id].level;
    }

    /*----------------------------RESTRICT FUNCTIONS----------------------------*/

    function changeMinter(address _newMinter) external onlyOwner {
        address _oldMinter = minter;
        minter = _newMinter;
        emit MinterChanged(_oldMinter, _newMinter);
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "DroidBot: caller is not the minter");
        _;
    }

    /*----------------------------EVENTS----------------------------*/

    event DroidBotCreated(address indexed receiver, uint256 indexed id, uint256 level, uint256 power);
    event DroidBotEvolved(address indexed receiver, uint256 newDroidBotLevel, uint256 droid0Level, uint256 droid1Level, uint256 indexed newDroidBotId, uint256 newDroidBotPower);
    event DroidBotUpgraded(uint256 indexed tokenId, uint256 newLv, uint256 newPower);
    event MinterChanged(address indexed oldMinter, address indexed newMinter);
}
