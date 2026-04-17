// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockYieldVault is ERC4626, Ownable {
    constructor(
        IERC20 asset_,
        address initialOwner
    )
        ERC20("Mock Yield Vault Share", "myvSHARE")
        ERC4626(asset_)
        Ownable(initialOwner)
    {}

    function addYield(uint256 amount) external onlyOwner {
        require(amount > 0, "amount=0");
        bool ok = IERC20(asset()).transferFrom(msg.sender, address(this), amount);
        require(ok, "yield transfer failed");
    }
}
