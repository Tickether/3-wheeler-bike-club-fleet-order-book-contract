// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {FleetOrderBook} from "../src/FleetOrderBook.sol";

contract FleetOrderBookScript is Script {
    FleetOrderBook public fleetOrderBook;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        fleetOrderBook = new FleetOrderBook();

        vm.stopBroadcast();
    }
}