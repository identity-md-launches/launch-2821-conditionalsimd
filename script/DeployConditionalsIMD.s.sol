// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {ConditionalsIMD} from "../src/ConditionalsIMD.sol";

/// @notice Reference deployment for local or test networks only. On the IMD launch the token is
/// deployed by the launch factory from its attested creation code; this script is never used to
/// broadcast there. The token takes no constructor arguments.
contract DeployConditionalsIMD is Script {
    function deploy() public returns (ConditionalsIMD token) {
        token = new ConditionalsIMD();
    }

    function run() external returns (ConditionalsIMD token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
