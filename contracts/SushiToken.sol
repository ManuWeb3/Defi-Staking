// SPDX-License-Identifier: MIT ... added by me
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract SushiToken is ERC20 {
    constructor (
        /*string memory name,
        string memory symbol,
        uint256 supply*/
    ) ERC20("Sushi Reward Token", "SRT") {
        // _mint(msg.sender, supply);
    }

    // called by StakingManager.sol inside harvestRewards that are nothing but SushiTokens
    function mint(address _to, uint256 _amount) internal {
        _mint(_to, _amount);
    }
}