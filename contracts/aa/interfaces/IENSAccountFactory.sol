// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface IENSAccountFactory {
    function getNodeAccount(bytes32 node) external returns (address account);
}
