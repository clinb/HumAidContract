// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HumAid is ERC20, Ownable(address(msg.sender)) {
    uint256 public feePercent = 5; // 0.5% = 5 / 1000

    mapping (address => string) public ngoNames;
    address[] public ngoWallets;

    mapping(address => bool) private _isExcludedFromFee;

    address public treasuryWallet;

    constructor() ERC20("HumAid", "HUM") {
        _isExcludedFromFee[msg.sender] = true;

        // Mint 1 billion HUM to the deployer
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
    }

    function setTreasuryWallet(address _treasuryWallet) external onlyOwner {
        require(_treasuryWallet != address(0), "Invalid treasury address");

        if (treasuryWallet != address(0)) {
            _isExcludedFromFee[treasuryWallet] = false;
        }

        treasuryWallet = _treasuryWallet;

        _isExcludedFromFee[treasuryWallet] = true;
    }

    function pushToNGOWallets(address _address) private { 
        ngoWallets.push(_address);
    }

    function popFromNGOWallets(uint32 _index) private { 
        ngoWallets[_index] = ngoWallets[ngoWallets.length - 1];
        ngoWallets.pop();
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 50, "Fee too high");
        feePercent = _feePercent;
    }

    function excludeFromFee(address account, bool excluded) external onlyOwner {
        _isExcludedFromFee[account] = excluded;
    }

    function isExcludedFromFee(address account) external view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    event NGORegistered(string name, address ngo);
    function registerNGOWallet(address _ngoAddress) private returns (bool){
        require(_ngoAddress != address(0), "Invalid NGO address");
        require(_isExcludedFromFee[_ngoAddress] == false, "This wallet is already registered");
        for (uint i = 0; i < ngoWallets.length; ++i){
            if(ngoWallets[i] == _ngoAddress) return false;
        }
        pushToNGOWallets(_ngoAddress);
        _isExcludedFromFee[_ngoAddress] = true;
        return true;
    }

    function registerNGO(string memory _ngoName, address _ngoAddress) external onlyOwner returns (bool) {
        require(_ngoAddress != address(0), "Invalid NGO address");
        for (uint i = 0; i < ngoWallets.length; ++i){
            if (keccak256(bytes (ngoNames[ngoWallets[i]])) == keccak256(bytes (_ngoName))) return false;
        }
        ngoNames[_ngoAddress] = _ngoName;
        emit NGORegistered(_ngoName, _ngoAddress);
        return registerNGOWallet(_ngoAddress);
    }
    
    event NGOUnregistered(string name, address ngo);
    function unregisterNGOWallet(address _ngoAddress) private returns (bool){
        require(_ngoAddress != address(0), "Invalid NGO address");
        for (uint32 i = 0; i < ngoWallets.length; ++i) 
        {
            if (ngoWallets[i] == _ngoAddress) {
                popFromNGOWallets(i);
                return true;
            }
        }
        return false;
    }

    function unregisterNGO(string memory _ngoName) external onlyOwner returns (bool) {
        address _ngoAddress = address(0);
        for (uint i = 0; i < ngoWallets.length; ++i){
            if (keccak256(bytes (ngoNames[ngoWallets[i]])) == keccak256(bytes (_ngoName))) {
                _ngoAddress = ngoWallets[i];
                break;
            }
        }
        if (_ngoAddress == address(0)) return false;

        delete ngoNames[_ngoAddress];
        emit NGOUnregistered(_ngoName, _ngoAddress);
        return unregisterNGOWallet(_ngoAddress);
    }

    function distributeTreasuryToNGOs() external onlyOwner {
        require(treasuryWallet != address(0), "Treasury wallet not set");
        uint256 ngoCount = ngoWallets.length;
        require(ngoCount > 0, "No NGOs registered");

        uint256 treasuryBalance = balanceOf(treasuryWallet);
        require(treasuryBalance > 0, "No funds to distribute");

        uint256 share = treasuryBalance / ngoCount;
        require(share > 0, "Insufficient funds for distribution");

        for (uint i = 0; i < ngoCount; ++i) {
            super._update(treasuryWallet, ngoWallets[i], share);
        }
    }


    /**
     * Override OpenZeppelin v5 _update instead of _transfer for fee logic.
     */
    function _update(address from, address to, uint256 value) internal override {
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to] || feePercent == 0) {
            super._update(from, to, value);
        } else {
            uint256 fee = (value * feePercent) / 1000;
            uint256 amountAfterFee = value - fee;
            uint256 share = ngoWallets.length != 0 ? fee / ngoWallets.length : 1;
            uint256 remainder = fee - (share * ngoWallets.length);

            for (uint i = 0; i < ngoWallets.length; ++i) {
                super._update(from, ngoWallets[i], share);
            }

            if (remainder > 0) {
                super._update(from, treasuryWallet, remainder);
            }

            super._update(from, to, amountAfterFee);
        }
    }
}
