// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./BaseFixture.sol";


contract TestVault is BaseFixture {
    function setUp() public override {
        super.setUp();
    }

    function testSetup() public {
        assertEq(goldAURA.admin(), address(1377));
    }
}