// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface IENSAccount {
    error UnSupportedSignMode(uint256 mode);

    function updateNode(uint256 coinType, bytes memory a) external;
}
