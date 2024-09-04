//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    error Raffle__NotSendEnoughFound();
    error Raffle__EntryRaffleNotOpen();
    error Raffle__TransferFailed();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 players, RaffleState state);

    enum RaffleState {
        OPEN, //0
        CALCULATING //1

    }

    RaffleState private s_raffleState;
    uint256 private immutable i_entryFee;
    address payable[] private s_players;
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_keyHash;
    uint32 private immutable i_callbackGasLimit;
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    address payable private s_winner;

    event PlayerEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    constructor(
        uint256 entryFee,
        uint256 interval,
        address vrfCoordinator,
        uint256 subscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entryFee = entryFee;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_keyHash = keyHash;
        i_callbackGasLimit = callbackGasLimit;
    }

    function entranceFee() public payable {
        if (msg.value < i_entryFee) {
            revert Raffle__NotSendEnoughFound();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__EntryRaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit PlayerEntered(msg.sender);
    }

    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = block.timestamp > s_lastTimeStamp + i_interval;
        bool raffleIsOpen = s_raffleState == RaffleState.OPEN;
        bool playersExist = s_players.length > 0;
        bool fundExists = address(this).balance > 0;
        upkeepNeeded = timeHasPassed && raffleIsOpen && playersExist && fundExists;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, s_raffleState);
        }
        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });

        s_vrfCoordinator.requestRandomWords(request);
    }

    function fulfillRandomWords(uint256, /*requestId*/ uint256[] calldata randomWords) internal override {
        s_winner = s_players[randomWords[0] % s_players.length];
        s_players = new address payable[](0);
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;

        emit WinnerPicked(s_winner);

        (bool success,) = s_winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayers(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() public view returns (address) {
        return s_winner;
    }
}
