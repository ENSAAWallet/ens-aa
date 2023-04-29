// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {PublicResolver, ENS, INameWrapper} from "@ensdomains/ens-contracts/contracts/resolvers/PublicResolver.sol";
import {IENSAccount} from "../aa/interfaces/IENSAccount.sol";
import {IENSAccountFactory} from "../aa/interfaces/IENSAccountFactory.sol";

contract AAResolver is PublicResolver {
    uint256 private constant COIN_TYPE_ETH = 60;
    IENSAccountFactory public immutable ensAccountFactory;

    constructor(
        ENS _ens,
        INameWrapper wrapperAddress,
        address _trustedETHController,
        address _trustedReverseRegistrar,
        IENSAccountFactory _ensAccountFactory
    )
        PublicResolver(
            _ens,
            wrapperAddress,
            _trustedETHController,
            _trustedReverseRegistrar
        )
    {
        ensAccountFactory = _ensAccountFactory;
    }

    function setAddr(
        bytes32 node,
        address a
    ) external virtual override authorised(node) {
        setAddr(node, COIN_TYPE_ETH, addressToBytes(a));

        _updateENSAccount(node, COIN_TYPE_ETH, addressToBytes(a));
    }

    function setAddr(
        bytes32 node,
        uint256 coinType,
        bytes memory a
    ) public virtual override authorised(node) {
        emit AddressChanged(node, coinType, a);
        if (coinType == COIN_TYPE_ETH) {
            emit AddrChanged(node, bytesToAddress(a));
        }
        versionable_addresses[recordVersions[node]][node][coinType] = a;
        _updateENSAccount(node, coinType, a);
    }

    function _updateENSAccount(
        bytes32 node,
        uint256 coinType,
        bytes memory a
    ) internal returns (bool) {
        address account = IENSAccountFactory(ensAccountFactory).getNodeAccount(
            node
        );
        if (account == address(0)) {
            return false;
        }
        IENSAccount(account).updateNode(coinType, a);
        return true;
    }
}
