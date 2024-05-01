// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./dependencies/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CIVInvest is ERC20, Ownable {

    string private _symbol = "CIVUSD";

    mapping(address => uint256) private _balances;

    constructor() ERC20("CIVInvest") Ownable(msg.sender) {
        _mint(msg.sender, 1000 * 10 ** decimals());
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}