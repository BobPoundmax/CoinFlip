// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
Extended MIT License with Revenue Sharing Clause
--------------------------------------------------

Copyright (c) 2025 Ivan Vinnikov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

1. The above copyright notice and this permission notice shall be included
   in all copies or substantial portions of the Software.

2. Revenue Sharing Requirement:
   If this Software or any derivative work generates revenue through yield
   farming, staking, transaction fees, or any similar mechanism, the entity
   using this Software or any derivative work thereof is required to transfer
   1% of the total generated revenue to the following wallet address:
   
       0x9e787a20B2A328d54F98B63469824eDf0d9FF546
   
   This payment must be made at least once per month. The entity using the
   Software may establish additional commission or fee structures as desired;
   however, the revenue sharing obligation defined in this section shall always
   remain in effect and must be fulfilled independently of any other fees imposed.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

contract CoinFlip {
    address public owner;
    uint private feePercentage = 1; // 1% fee from each bet
    uint private nextBetId = 1; // Unique bet ID tracker

    enum BetChoice { Black, White }
    enum BetStatus { InQueue, Won, Lost }

    struct Bet {
        uint id;
        address player;
        uint amount;
        BetChoice choice;
        BetStatus status;
        BetChoice winnerChoice;
        uint payout;
        bytes32 betHash;
    }

    Bet[] private betQueue;
    mapping(uint => Bet) private allBets; // Store bets by ID
    mapping(bytes32 => Bet) private betByHash;
    mapping(address => bytes32[]) private playerBetHashes;
    uint private totalPoolBalance;

    event BetPlaced(uint indexed betId, address indexed player, uint amount, BetChoice choice, uint queuePosition, bytes32 betHash);
    event BetResolved(uint indexed betId, address indexed player, BetChoice choice, BetChoice winnerChoice, BetStatus result, uint payout, uint amountSent);

    constructor() {
        owner = msg.sender;
    }

    function betBlack() public payable returns (bytes32) {
        require(msg.value > 0, "Bet must be greater than 0");
        return placeBet(msg.sender, BetChoice.Black);
    }
    
    function betWhite() public payable returns (bytes32) {
        require(msg.value > 0, "Bet must be greater than 0");
        return placeBet(msg.sender, BetChoice.White);
    }

    function placeBet(address player, BetChoice choice) private returns (bytes32) {
        require(msg.value > 0, "Bet must be greater than 0");

        uint fee = (msg.value * feePercentage) / 100;
        uint betAmount = msg.value; // Keep original bet amount

        payable(owner).transfer(fee); // Send fee to owner immediately
        totalPoolBalance += (msg.value - fee); // Add remaining amount to pool

        bytes32 betHash = keccak256(abi.encodePacked(player, nextBetId, block.timestamp));

        Bet memory newBet = Bet(nextBetId, player, betAmount, choice, BetStatus.InQueue, BetChoice.Black, 0, betHash);
        allBets[nextBetId] = newBet;
        betByHash[betHash] = newBet;
        playerBetHashes[player].push(betHash);
        betQueue.push(newBet);

        uint queuePosition = betQueue.length;

        emit BetPlaced(nextBetId, player, betAmount, choice, queuePosition, betHash);
        nextBetId++;

        resolveBets();
        return betHash;
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

        uint256 random = randomNumber(bet.player, msg.sender);
        BetChoice winnerChoice = (random % 2 == 0) ? BetChoice.Black : BetChoice.White;
        bool playerWins = (bet.choice == winnerChoice);

        if (playerWins) {
            payable(bet.player).transfer(payout);
            bet.status = BetStatus.Won;
            bet.payout = payout;
            totalPoolBalance -= payout;
        } else {
            bet.status = BetStatus.Lost;
            bet.payout = 0;
        }
        bet.winnerChoice = winnerChoice;

        allBets[bet.id] = bet;
        betByHash[bet.betHash] = bet;
        
        emit BetResolved(bet.id, bet.player, bet.choice, winnerChoice, bet.status, bet.payout, msg.value);
        removeFirstBet();
    }

    function removeFirstBet() private {
        for (uint i = 1; i < betQueue.length; i++) {
            betQueue[i - 1] = betQueue[i];
        }
        betQueue.pop();
    }

    function getBetStatus(bytes32 betHash) public view returns (bytes32, address, string memory, string memory, uint) {
        require(betByHash[betHash].id != 0, "Bet not found");
        Bet memory bet = betByHash[betHash];

        string memory choiceString = bet.choice == BetChoice.Black ? "Black" : "White";
        string memory statusString;
        if (bet.status == BetStatus.InQueue) statusString = "InQueue";
        else if (bet.status == BetStatus.Won) statusString = "Won";
        else statusString = "Lost";

        return (bet.betHash, bet.player, choiceString, statusString, bet.amount);
    }

    function getAllBets() public view returns (bytes32[] memory) {
        return playerBetHashes[msg.sender];
    }

    function randomNumber(address player, address sender) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.number,
            blockhash(block.number - 1),
            player,
            sender,
            address(this).balance,
            gasleft()
        )));
    }
}
