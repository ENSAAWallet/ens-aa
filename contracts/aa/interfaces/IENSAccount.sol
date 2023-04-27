// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface IENSAccount {
    error UnSupportedSignMode(uint256 mode);
    error UnvalidKeyScore(uint256 score);

    function updateExiry() external returns (uint64);

    function updateNode(uint256 coinType, bytes memory addr) external;
}
