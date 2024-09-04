//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

// import {DeployRaffle} from "script/DeployRaffle.s.sol";
// import {Raffle} from "src/Raffle.sol";

contract CodeConstant {
    uint96 public constant MOCK_BASE_FEE = 0.1 ether;
    uint96 public constant MOCK_GAS_PRICE = 1e8;

    int256 public constant MOCK_WEI_PER_UNIT_LINK = 3e15;

    uint256 constant LOCAL_CHAIN_ID = 31337;
    uint256 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
}

contract HelperConfig is Script, CodeConstant {
    error HelperConfig__InvalidChainId();

    struct NetWorkConfig {
        uint256 entryFee;
        uint256 interval;
        address vrfCoordinator;
        uint256 subscriptionId;
        bytes32 keyHash;
        uint32 callbackGasLimit;
        address link;
        address account;
    }

    NetWorkConfig private localNetWorkConfig;
    mapping(uint256 chainid => NetWorkConfig) private netWorkConfig;

    constructor() {
        netWorkConfig[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getNetWorkConfigByChainId(
        uint256 chainid
    ) public returns (NetWorkConfig memory) {
        if (netWorkConfig[chainid].vrfCoordinator != address(0)) {
            return netWorkConfig[ETH_SEPOLIA_CHAIN_ID];
        } else if (chainid == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetWorkConfig memory) {
        return
            NetWorkConfig({
                entryFee: 0.01 ether,
                interval: 30,
                vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
                subscriptionId: 77113682376656144762576379467727317787801460865064588376580268143731395726051,
                keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                callbackGasLimit: 500000,
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
                account: 0xEC8E6b06C31CbFC078Fa87D5dca574350f3DD4d1
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetWorkConfig memory) {
        if (localNetWorkConfig.vrfCoordinator != address(0)) {
            return localNetWorkConfig;
        }
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinator = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE,
            MOCK_GAS_PRICE,
            MOCK_WEI_PER_UNIT_LINK
        );
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        localNetWorkConfig = NetWorkConfig({
            entryFee: 0.01 ether,
            interval: 30,
            vrfCoordinator: address(vrfCoordinator),
            subscriptionId: 0,
            keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500000,
            link: address(linkToken),
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        });
        return localNetWorkConfig;
    }

    function getConfig() public returns (NetWorkConfig memory) {
        return getNetWorkConfigByChainId(block.chainid);
    }
}
