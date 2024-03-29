// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Strings.sol";
import {Script, console2} from "forge-std/Script.sol";
import "../src/FusionLock.sol";

contract FusionLockScript is Script {
    function setUp() public {}

    function run() public {
        // Retrieve the deployer's private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start the broadcast using the deployer's private key
        vm.startBroadcast(deployerPrivateKey);

        // Retrieve other parameters from environment variables
        uint256 setWithdrawalStartTime = uint256(vm.envUint("WITHDRAWAL_START_TIME")); // Unix epoch format in seconds
        address initialOwner = vm.envAddress("OWNER");
        address[] memory allowTokens = getAllowTokens();

        // Deploy the FusionLock contract with the retrieved parameters
        new FusionLock(setWithdrawalStartTime, allowTokens, initialOwner);

        // Stop the broadcast after deployment
        vm.stopBroadcast();
    }

    function getAllowTokens() private view returns (address[] memory) {
        uint256 numTokens = vm.envUint("NUM_TOKENS");
        address[] memory allowTokens = new address[](numTokens);

        for (uint32 id = 0; id < numTokens; id++) {
            string memory tokenKey = string.concat("TOKEN_", Strings.toString(id));

            allowTokens[id] = vm.envAddress(tokenKey);
        }

        return allowTokens;
    }
}
