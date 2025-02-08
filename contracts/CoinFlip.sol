// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CoinFlip {
    address public owner;
    uint public feePercentage = 1; // 1% fee from each bet
    uint public nextBetId = 1; // Unique bet ID tracker

    enum BetChoice { Black, White }
    enum BetStatus { InQueue, Won, Lost }

    struct Bet {
        uint id;
        address player;
        uint amount;
        BetChoice choice;
        BetStatus status;
    }

    Bet[] public betQueue;
    mapping(uint => Bet) public allBets; // Store bets by ID
    uint public totalPoolBalance;
    uint public totalCollectedFees;

    event BetPlaced(uint indexed betId, address indexed player, uint amount, BetChoice choice, uint queuePosition);
    event BetResolved(uint indexed betId, address indexed player, BetStatus result);
    event BetWaiting(uint indexed betId, address indexed player, uint amount, BetChoice choice, uint queuePosition);

    constructor() {
        owner = msg.sender;
    }

    // Player places a bet on Black
    function betBlack() public payable {
        require(msg.value > 0, "Bet must be greater than 0");
        placeBet(msg.sender, msg.value, BetChoice.Black);
    }

    // Player places a bet on White
    function betWhite() public payable {
        require(msg.value > 0, "Bet must be greater than 0");
        placeBet(msg.sender, msg.value, BetChoice.White);
    }

    function placeBet(address player, uint amount, BetChoice choice) private {
        uint fee = (amount * feePercentage) / 100;
        uint betAmount = amount - fee;

        totalCollectedFees += fee; // Store the fee for contract owner
        totalPoolBalance += betAmount;

        Bet memory newBet = Bet(nextBetId, player, betAmount, choice, BetStatus.InQueue);
        allBets[nextBetId] = newBet;
        betQueue.push(newBet);

        uint queuePosition = betQueue.length;

        emit BetPlaced(nextBetId, player, betAmount, choice, queuePosition);
        nextBetId++;

        resolveBets(); // Check if any bets can be processed
    }

    function resolveBets() private {
        while (betQueue.length > 0 && canProcessNextBet()) {
            processBet();
        }
    }

    function canProcessNextBet() private view returns (bool) {
        if (betQueue.length == 0) return false;
        return (betQueue[0].amount * 2) <= totalPoolBalance;
    }

    function processBet() private {
        Bet storage bet = betQueue[0];
        uint betAmount = bet.amount;
        uint payout = betAmount * 2;

        // Simulating coin flip (should use Chainlink VRF for true randomness)
        uint rand = uint(keccak256(abi.encodePacked(block.timestamp, bet.player))) % 2;
        bool playerWins = (rand == 0);

        if (playerWins) {
            payable(bet.player).transfer(payout);
            bet.status = BetStatus.Won;
            totalPoolBalance -= payout;
        } else {
            bet.status = BetStatus.Lost;
        }

        emit BetResolved(bet.id, bet.player, bet.status);
        removeFirstBet();
    }

    function removeFirstBet() private {
        for (uint i = 1; i < betQueue.length; i++) {
            betQueue[i - 1] = betQueue[i];
        }
        betQueue.pop();
    }

    function getPoolBalance() public view returns (uint) {
        return totalPoolBalance;
    }

    function getBetStatus(uint betId) public view returns (string memory) {
        require(allBets[betId].player != address(0), "Invalid bet ID");
        Bet storage bet = allBets[betId];

        string memory queueInfo = "";
        if (bet.status == BetStatus.InQueue) {
            uint queuePosition = getQueuePosition(betId);
            queueInfo = string(abi.encodePacked(
                "Bet is in queue. ID: ", uintToString(bet.id),
                ", Queue Position: ", uintToString(queuePosition),
                "."
            ));
        }

        if (bet.status == BetStatus.Won) {
            return string(abi.encodePacked(
                "Bet ID: ", uintToString(bet.id), 
                ". Won ", uintToString(bet.amount * 2), " ETH."
            ));
        } else if (bet.status == BetStatus.Lost) {
            return string(abi.encodePacked(
                "Bet ID: ", uintToString(bet.id), 
                ". Lost ", uintToString(bet.amount), " ETH."
            ));
        } else {
            return queueInfo;
        }
    }

    function getQueuePosition(uint betId) public view returns (uint) {
        for (uint i = 0; i < betQueue.length; i++) {
            if (betQueue[i].id == betId) {
                return i + 1; // Position in queue (1-based index)
            }
        }
        return 0; // Not in queue
    }

    function uintToString(uint v) private pure returns (string memory) {
        if (v == 0) {
            return "0";
        }
        uint len;
        uint temp = v;
        while (temp != 0) {
            len++;
            temp /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (v != 0) {
            k = k - 1;
            bstr[k] = bytes1(uint8(48 + v % 10));
            v /= 10;
        }
        return string(bstr);
    }

    function withdrawFees() public {
        require(msg.sender == owner, "Only owner can withdraw fees");
        payable(owner).transfer(totalCollectedFees);
        totalCollectedFees = 0;
    }
}
