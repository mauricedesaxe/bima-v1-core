// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract StakedBTC is ERC20, ERC20Permit {
    constructor() ERC20("Staked BTC", "stBTC") ERC20Permit("Staked BTC") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}