#!/bin/bash

export PRIVATE_KEY=0x<exported-privatekey>
export RPC_URL=<eth-rpc-url>
export WITHDRAWAL_START_TIME=1709463387 # GMT: Sunday, 3 March 2024 10:56:27, expected Unix epoch format in seconds
export OWNER=<set-owner-address>
export NUM_TOKENS=26 # Following tokens are also mentioned in the readme
export TOKEN_0=0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0 # wstETH
export TOKEN_1=0xae78736cd615f374d3085123a210448e74fc6393 # rETH
export TOKEN_2=0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a # aUSDT
export TOKEN_3=0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c # aUSDC
export TOKEN_4=0x018008bfb33d285247A21d44E50697654f754e63 # aDAI
export TOKEN_5=0x9d39a5de30e57443bff2a8307a4256c8797a3497 # sUSDe
export TOKEN_6=0x5Ee5bf7ae06D1Be5997A1A72006FE6C607eC6DE8 # awBTC
export TOKEN_7=0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2 # wETH
export TOKEN_8=0x18084fba666a33d37592fa2633fd49a74dd93a88 # tBTC v2
export TOKEN_9=0x2260fac5e5542a773aa44fbcfedf7c193bc2c599 # wBTC
export TOKEN_10=0xdac17f958d2ee523a2206206994597c13d831ec7 # USDT
export TOKEN_11=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 # USDC
export TOKEN_12=0x853d955acef822db058eb8505911ed77f175b99e # FRAX
export TOKEN_13=0x6b175474e89094c44da98b954eedeac495271d0f # DAI
export TOKEN_14=0x4c9edd5852cd905f086c759e8383e09bff1e68b3 # USDe
export TOKEN_15=0xbdbb63f938c8961af31ead3deba5c96e6a323dd1 # eDLLR
export TOKEN_16=0xbdab72602e9ad40fc6a6852caf43258113b8f7a5 # eSOV
export TOKEN_17=0x418d75f65a02b3d53b2418fb8e1fe493759c7605 # wh.BNB
export TOKEN_18=0xd31a59c85ae9d8edefec411d448f90841571b89c # wh.SOL
export TOKEN_19=0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1 # ARB
export TOKEN_20=0x7c9f4c87d911613fe9ca58b579f737911aad2d43 # wh.MATIC
export TOKEN_21= # aBTC, Not yet deployed, add contract address before deployment
export TOKEN_22= # sBTC, Not yet deployed, add contract address before deployment
export TOKEN_23= # ALEX, Not yet deployed, add contract address before deployment
export TOKEN_24= # OP, Not yet deployed, add contract address before deployment
export TOKEN_25= # STX, Not yet deployed, add contract address before deployment

forge script script/FusionLock.s.sol --rpc-url=$RPC_URL --broadcast
