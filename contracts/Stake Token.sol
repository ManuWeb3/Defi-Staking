// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakeToken is ERC20 {
    constructor () ERC20("Stake Token", "ST") {
        uint256 s_supply = 10000;   // 10,000 total supply and initial balance of msg.sender
        _mint(msg.sender, s_supply);
    }
    /*
    function mint(address _to, uint256 _amount) internal {
        _mint(_to, _amount);
    }
    */
}