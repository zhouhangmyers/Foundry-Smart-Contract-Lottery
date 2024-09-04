//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";

contract DeployRaffle is Script {
    function run() public returns (Raffle, HelperConfig) {
        (Raffle raffle, HelperConfig helperConfig) = deployContract();
        return (raffle, helperConfig);
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetWorkConfig memory config = helperConfig.getConfig();
        if (config.subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            uint256 subscriptionId = createSubscription.createSubscription(
                config.vrfCoordinator,
                config.account
            );
            config.subscriptionId = subscriptionId;

            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                config.vrfCoordinator,
                subscriptionId,
                config.link,
                config.account
            );
        }

        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entryFee,
            config.interval,
            config.vrfCoordinator,
            config.subscriptionId,
            config.keyHash,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            config.vrfCoordinator,
            config.account,
            config.subscriptionId,
            address(raffle)
        );
        return (raffle, helperConfig);
    }
}
