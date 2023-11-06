// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import { ERC20 } from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @dev This mock is needed for:
/// - Test `want` deposits & withdrawals in testnet<>ui
contract ERC20WantMock is ERC20 {
    constructor() ERC20("AuraMock", "AM") { }

    function mintWant(uint256 _amount) external {
        _mint(msg.sender, _amount);
    }
}
