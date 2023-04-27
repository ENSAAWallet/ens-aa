// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

// https://docs.ens.domains/ens-improvement-proposals/ensip-9-multichain-address-resolution
library LibCoinType {
    uint256 internal constant COIN_TYPE_BTC = 0;
    uint256 internal constant COIN_TYPE_LTC = 2;
    uint256 internal constant COIN_TYPE_DOGE = 3;
    uint256 internal constant COIN_TYPE_MONA = 22;
    uint256 internal constant COIN_TYPE_ETH = 60;
    uint256 internal constant COIN_TYPE_ETC = 61;
    uint256 internal constant COIN_TYPE_RBTC = 137;
    uint256 internal constant COIN_TYPE_XRP = 144;
    uint256 internal constant COIN_TYPE_BCH = 145;
    uint256 internal constant COIN_TYPE_BNB = 714;
}
