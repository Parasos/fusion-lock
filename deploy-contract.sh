#!/bin/bash

export PRIVATE_KEY=0x<exported-privatekey>
export RPC_URL=<eth-rpc-url>
export WITHDRAWAL_START_TIME=1709463387 # GMT: Sunday, 3 March 2024 10:56:27, expected Unix epoch format in seconds
export OWNER=<set-owner-address>
export NUM_TOKENS=11 # Following tokens are also mentioned in the readme
export TOKEN_0=0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0 # wstETH
export TOKEN_1=0xae78736cd615f374d3085123a210448e74fc6393 # rETH
export TOKEN_2=0x18084fba666a33d37592fa2633fd49a74dd93a88 # tBTC v2
export TOKEN_3=0x2260fac5e5542a773aa44fbcfedf7c193bc2c599 # wBTC
export TOKEN_4=0xdac17f958d2ee523a2206206994597c13d831ec7 # USDT
export TOKEN_5=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 # USDC
export TOKEN_6=0x6b175474e89094c44da98b954eedeac495271d0f # DAI
export TOKEN_7=0xbdbb63f938c8961af31ead3deba5c96e6a323dd1 # eDLLR
export TOKEN_8=0xbdab72602e9ad40fc6a6852caf43258113b8f7a5 # eSOV
export TOKEN_9=0x7122985656e38bdc0302db86685bb972b145bd3c # STONE
export TOKEN_10=0xe7c3755482d0da522678af05945062d4427e0923 # ALEX

forge script script/FusionLock.s.sol --rpc-url=$RPC_URL --broadcast
