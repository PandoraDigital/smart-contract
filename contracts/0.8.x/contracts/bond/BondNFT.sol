// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "./BondStruct.sol";


contract BondNFT is ERC721Upgradeable, BondStruct {
    using BitMaps for BitMaps.BitMap;

    string private _baseUri;

    // config
    address public issuer; // address of bond issuer
    BitMaps.BitMap private _lock;
    mapping(uint256 => BondInfo) public bondInfo;
    uint256 private _currentId;
    uint256 private _totalBurn;
    address private _owner;

    modifier onlyIssuer() {
        require(msg.sender == issuer, "BondNFT: only issuer");
        _;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "BondNFT: caller is not the owner");
        _;
    }

    event Lock(bool isLock, uint256 _id);
    event Issue(uint256 _id, BondInfo _info);
    event UpdateIssuer(address _old, address _new);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function initialize(string memory _uri, string memory name_, string memory symbol_, address issuer_) initializer public returns (bool) {
        __ERC721_init(name_, symbol_);
        issuer = issuer_;
        _baseUri = _uri;
        _owner = tx.origin;
        return true;
    }

    //custom functions
    function issue(address receiver_, uint256 quantity_, uint256 amount_, uint256 maturity_, uint256 interest_, uint256 batchId_) external onlyIssuer {
        for (uint i = 0; i < quantity_; i ++) {
            _currentId ++;
            _mint(receiver_, _currentId);
            bondInfo[_currentId].issueDate = block.timestamp;
            bondInfo[_currentId].lastHarvest = block.timestamp;
            bondInfo[_currentId].maturity = maturity_;
            bondInfo[_currentId].amount = amount_;
            bondInfo[_currentId].interest = interest_;
            bondInfo[_currentId].batchId = batchId_;
            emit Issue(_currentId, bondInfo[_currentId]);
        }
    }

    function redeem(uint256[] memory tokenIds) external onlyIssuer {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(ERC721Upgradeable._isApprovedOrOwner(msg.sender, tokenIds[i]), "BondNFT: not owner or approval");
            _burn(tokenIds[i]);
        }
        _totalBurn += tokenIds.length;
    }

    function lock(uint256[] memory tokenIds) external onlyIssuer {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(ERC721Upgradeable._isApprovedOrOwner(msg.sender, tokenIds[i]), "BondNFT: not owner or approval");
            require(!_lock.get(tokenIds[i]), "BondNFT: already locked");
            _lock.set(tokenIds[i]);
            emit Lock(true, tokenIds[i]);
        }

    }

    function unlock(uint256[] memory tokenIds) external onlyIssuer {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(ERC721Upgradeable._isApprovedOrOwner(msg.sender, tokenIds[i]), "BondNFT: not owner or approval");
            require(_lock.get(tokenIds[i]), "BondNFT: id not locked");
            _lock.unset(tokenIds[i]);
            emit Lock(false, tokenIds[i]);
        }
    }

    function burn(uint256 tokenId) public virtual {
        //solhint-disable-next-line max-line-length
        require(ERC721Upgradeable._isApprovedOrOwner(_msgSender(), tokenId), "BondNFT: caller is not owner nor approved");
        _burn(tokenId);
        _totalBurn++;
    }

    function updateLastHarvest(uint256[] memory tokenIds, address user) external onlyIssuer {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(ERC721Upgradeable._isApprovedOrOwner(user, tokenIds[i]), "BondNFT: not owner or approval");
            bondInfo[tokenIds[i]].lastHarvest = block.timestamp;
        }
    }

    function updateIssuer(address _new) external onlyOwner {
        require(_new != address(0), "BondNFT: !zero address");
        address _old = issuer;
        issuer = _new;
        emit UpdateIssuer(_old, _new);
    }

    // Internal functions
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override virtual {
        require(!_lock.get(tokenId), "BondNFT: already locked");
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    // View functions
    function isLocked(uint256 tokenId_) external view returns (bool) {
        return _lock.get(tokenId_);
    }

    function currentSupply() external view returns (uint256) {
        return _currentId - _totalBurn;
    }

    function info(uint256 tokenId_) external view returns (BondInfo memory) {
        return bondInfo[tokenId_];
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    // Owner functions

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
}
