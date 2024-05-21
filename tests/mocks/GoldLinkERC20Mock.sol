// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GoldLinkERC20Mock is ERC20, Ownable {
    uint8 private immutable _decimals;
    address public minter;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        _decimals = decimals_;
        minter = msg.sender;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burnFrom(address to, uint256 amount) external returns (bool) {
        _burn(to, amount);
        return true;
    }

    function burn(address to, uint256 amount) external returns (bool) {
        _burn(to, amount);
        return true;
    }

    function setMinter(address _minter) external {
        require(_minter != address(0));
        minter = _minter;
    }
}
