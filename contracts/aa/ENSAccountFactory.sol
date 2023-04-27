// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {ENSAccount} from "./ENSAccount.sol";
import "@ensdomains/ens-contracts/contracts/resolvers/Resolver.sol";
import "@ensdomains/ens-contracts/contracts/wrapper/NameWrapper.sol";
import "./interfaces/IENSAccountFactory.sol";

contract ENSAccountFactory is IENSAccountFactory {
    ENSAccount public immutable accountImplementation;
    mapping(bytes32 => address) public accountMapping;

    constructor(
        IEntryPoint _entryPoint,
        NameWrapper _ensNameWrapper,
        Resolver _ensResolver
    ) {
        accountImplementation = new ENSAccount(
            _entryPoint,
            _ensNameWrapper,
            _ensResolver
        );
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(
        bytes32 node,
        uint256 salt
    ) public returns (ENSAccount ret) {
        require(accountMapping[node] == address(0), "already deployed");
        address addr = getAddress(node, salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return ENSAccount(payable(addr));
        }
        ret = ENSAccount(
            payable(
                new ERC1967Proxy{salt: bytes32(salt)}(
                    address(accountImplementation),
                    abi.encodeCall(ENSAccount.initialize, (node))
                )
            )
        );
        accountMapping[node] = address(ret);
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(
        bytes32 node,
        uint256 salt
    ) public view returns (address) {
        return
            Create2.computeAddress(
                bytes32(salt),
                keccak256(
                    abi.encodePacked(
                        type(ERC1967Proxy).creationCode,
                        abi.encode(
                            address(accountImplementation),
                            abi.encodeCall(ENSAccount.initialize, (node))
                        )
                    )
                )
            );
    }

    function getNodeAccount(
        bytes32 node
    ) public view returns (address account) {
        account = accountMapping[node];
    }
}
