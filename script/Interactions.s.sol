//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, CodeConstant} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint256) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetWorkConfig memory config = helperConfig.getConfig();
        address vrfCoordinator = config.vrfCoordinator;
        address account = config.account;
        uint256 subscriptionId = createSubscription(vrfCoordinator, account);
        return subscriptionId;
    }

    function createSubscription(address vrfCoordinator, address account) public returns (uint256) {
        console.log("Creating subscription on Chain Id:", block.chainid);
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock vrfCoordinatorV2_5Mock = VRFCoordinatorV2_5Mock(vrfCoordinator);
        uint256 subscriptionId = vrfCoordinatorV2_5Mock.createSubscription();
        vm.stopBroadcast();

        console.log("Subscription Id:", subscriptionId);
        console.log("Please copy the subscription Id and paste it in the HelperConfig contract");
        return subscriptionId;
    }

    function run() public {
        createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script, CodeConstant {
    uint256 public constant FUND_AMOUNT = 2 ether;

    function run() external {
        fundSubscriptionUsingConfig();
    }

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetWorkConfig memory config = helperConfig.getConfig();
        address vrfCoordinator = config.vrfCoordinator;
        uint256 subscriptionId = config.subscriptionId;
        address link = config.link;
        address account = config.account;
        fundSubscription(vrfCoordinator, subscriptionId, link, account);
    }

    function fundSubscription(address vrfCoordinator, uint256 subscriptionId, address link, address account) public {
        console.log("Funding subscription on Chain Id:", block.chainid);
        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast(account);
            VRFCoordinatorV2_5Mock vrfCoordinatorV2_5Mock = VRFCoordinatorV2_5Mock(vrfCoordinator);
            vrfCoordinatorV2_5Mock.fundSubscription(subscriptionId, FUND_AMOUNT * 100);
            vm.stopBroadcast();
            console.log("Subscription funded");
        } else {
            vm.startBroadcast();
            LinkToken(link).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));
            vm.stopBroadcast();
        }
    }
}

contract AddConsumer is Script {
    function run() external {
        addConsumerUsingConfig();
    }

    function addConsumerUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetWorkConfig memory config = helperConfig.getConfig();
        address vrfCoordinator = config.vrfCoordinator;
        address account = config.account;
        uint256 subscriptionId = config.subscriptionId;
        address mostRecentConsumer = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);

        addConsumer(vrfCoordinator, account, subscriptionId, mostRecentConsumer);
    }

    function addConsumer(address vrfCoordinator, address account, uint256 subscriptionId, address consumer) public {
        console.log("Adding consumer on Chain Id:", block.chainid);
        console.log("Adding consumer contract:", consumer);
        console.log("To vrfCoordinator:", vrfCoordinator);
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock vrfCoordinatorV2_5Mock = VRFCoordinatorV2_5Mock(vrfCoordinator);
        vrfCoordinatorV2_5Mock.addConsumer(subscriptionId, consumer);
        vm.stopBroadcast();
        console.log("Consumer added");
    }
}
