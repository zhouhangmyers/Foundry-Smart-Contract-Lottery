//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig, CodeConstant} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstant {
    HelperConfig public helperConfig;
    Raffle public raffle;

    uint256 entryFee;
    uint256 interval;
    address vrfCoordinator;
    uint256 subscriptionId;
    bytes32 keyHash;
    uint32 callbackGasLimit;
    address link;
    address account;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 1000 ether;

    event PlayerEntered(address indexed player);

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        HelperConfig.NetWorkConfig memory config = helperConfig.getConfig();

        entryFee = config.entryFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        subscriptionId = config.subscriptionId;
        keyHash = config.keyHash;
        callbackGasLimit = config.callbackGasLimit;
        link = config.link;
        account = config.account;

        vm.deal(PLAYER, STARTING_BALANCE);
    }

    function testRaffleInitializedInOpenState() external view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleNotSendEnoughFound() external {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotSendEnoughFound.selector);
        raffle.entranceFee();
    }

    function testRaffleUpdatesDataStructure() external {
        vm.prank(PLAYER);
        raffle.entranceFee{value: entryFee}();
        assertEq(raffle.getPlayers(0), PLAYER);
    }

    function testEnteringRaffleEmitsEvent() external {
        vm.expectEmit(true, false, false, false, address(raffle));
        emit PlayerEntered(PLAYER);
        vm.prank(PLAYER);
        raffle.entranceFee{value: entryFee}();
    }

    function testDontAllowPlayerToEnterWhileCalculating() external {
        vm.prank(PLAYER);
        raffle.entranceFee{value: entryFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__EntryRaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.entranceFee{value: entryFee}();
    }

    function testChekUpkeepReturnsFalseIfItHasNoBalance() external {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool success,) = raffle.checkUpkeep("");
        assert(!success);
    }

    function testCheckUpkeepReturnsFalseIfItHasNoOpen() external {
        vm.prank(PLAYER);
        raffle.entranceFee{value: entryFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

        (bool success,) = raffle.checkUpkeep("");
        assert(!success);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////// 测试performUpkeep函数
    //////////////////////////////////////////////////////////////////////////////////////////////*/
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() external {
        vm.prank(PLAYER); // 模拟 PLAYER 的行为
        raffle.entranceFee{value: entryFee}(); // PLAYER 进入 raffle，支付 entranceFee

        vm.warp(block.timestamp + interval + 1); // 将 EVM 的时间戳推进
        vm.roll(block.number + 1); // 将 EVM 的区块号推进

        //Act / Assert
        raffle.performUpkeep(""); // 执行 performUpkeep
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() external {
        //Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState state = raffle.getRaffleState();

        vm.prank(PLAYER); // 模拟 PLAYER 的行为
        raffle.entranceFee{value: entryFee}();
        currentBalance += entryFee;
        numPlayers += 1;

        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, state)
        );

        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.entranceFee{value: entryFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerfromUpkeepUpdatesRaffleStateAndEmitsRequestId() external raffleEntered {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[0].topics[1];

        Raffle.RaffleState state = raffle.getRaffleState();
        assert(state == Raffle.RaffleState.CALCULATING);
        assert(requestId > 0);
    }

    /*////////////////////////////////////////////////////////////////////////
                                // FULFILLRANDOMWORDS
    ////////////////////////////////////////////////////////////////////////*/

    modifier skipTest() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            // because we using VRFCoordinatorV2_5Mock must be using vrfCoordinator on local chain
            return;
        }
        _;
    }

    function testFulfillRandomWordsOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEntered
        skipTest
    {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWrodsPicksAWinnerResetsAndSendsMoney() external raffleEntered skipTest {
        uint256 additionalEntrans = 3;
        uint160 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint160 i = startingIndex; i < additionalEntrans + startingIndex; i++) {
            hoax(address(i), 1 ether);
            raffle.entranceFee{value: entryFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[0].topics[1];

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        Raffle.RaffleState state = raffle.getRaffleState();
        uint256 winnerBalance = expectedWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        address recentWinner = raffle.getRecentWinner();
        uint256 price = entryFee * (additionalEntrans + 1);

        assert(state == Raffle.RaffleState.OPEN);
        assert(winnerBalance == winnerStartingBalance + price);
        assert(endingTimeStamp > startingTimeStamp);
        assert(recentWinner == expectedWinner);
    }
}
