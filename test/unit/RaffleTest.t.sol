//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Raffle} from "src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {CodeConstants} from "script/HelperConfig.s.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entryFee;
    uint256 interval;
    uint256 subscriptionId;
    address vrfCoordinator;
    bytes32 keyHash;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STATING_BALANCE = 100 ether;

    event RaffleEntered(address indexed players);

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        entryFee = config.entryFee;
        interval = config.interval;
        subscriptionId = config.subscriptionId;
        vrfCoordinator = config.vrfCoordinator;
        keyHash = config.keyHash;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STATING_BALANCE);
    }

    function testRaffleInitializedInOpenState() external view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleIfNotEnoughToEntry() external {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotSendEnoughFund.selector);
        raffle.entryRaffle();
    }

    function testRaffleUpdatesDataSturcture() external {
        vm.prank(PLAYER);
        raffle.entryRaffle{value: entryFee}();
        assertEq(raffle.getPlayers(0), PLAYER);
    }

    function testEnteringRaffleEmitsEvent() external {
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        vm.prank(PLAYER);
        raffle.entryRaffle{value: entryFee}();
    }

    function testDontAllowPlayersToEnterWhileCalculating() external {
        vm.prank(PLAYER); // 模拟 PLAYER 的行为
        raffle.entryRaffle{value: entryFee}(); // PLAYER 进入 raffle，支付 entranceFee

        vm.warp(block.timestamp + interval + 1); // 将 EVM 的时间戳推进
        vm.roll(block.number + 1); // 将 EVM 的区块号推进

        raffle.performUpkeep(""); // 执行 performUpkeep 操作，通常是计算获胜者

        vm.expectRevert(Raffle.Raffle__EntryRaffleNotOpen.selector); // 期望接下来的操作会失败并回滚
        vm.prank(PLAYER); // 再次模拟 PLAYER 的行为
        raffle.entryRaffle{value: entryFee}(); // PLAYER 尝试再次进入 raffle，这次应该失败
    }

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() external {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfItHasNoOpen() external {
        vm.prank(PLAYER);
        raffle.entryRaffle{value: entryFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); //执行完后RaffleState为Calculating

        (bool upkeepNeeded,) = raffle.checkUpkeep(""); //RaffleState为Calculating不为Open
        assert(!upkeepNeeded);
    }

    /*//////////////////////////////////////////////////////////////////////////////
    // 以下是测试 performUpkeep 的测试用例
    //////////////////////////////////////////////////////////////////////////////*/
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() external {
        vm.prank(PLAYER); // 模拟 PLAYER 的行为
        raffle.entryRaffle{value: entryFee}(); // PLAYER 进入 raffle，支付 entranceFee

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
        raffle.entryRaffle{value: entryFee}();
        currentBalance += entryFee;
        numPlayers += 1;

        //Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, state)
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.entryRaffle{value: entryFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    //what if we need to get data from emitted events in our tests?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];

        Raffle.RaffleState state = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(state) == 1);
    }

    /*//////////////////////////////////////////////////////////////////////////////
                            // FULFILLRANDOMWORDS
    //////////////////////////////////////////////////////////////////////////////*/

    modifier skipTest() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEntered
        skipTest
    {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipTest {
        uint256 additionalEntrans = 3;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrans; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            raffle.entryRaffle{value: entryFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState state = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entryFee * (additionalEntrans + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(state) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
