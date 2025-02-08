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


contract CoinFlipChallenge { 
    address public owner;
    uint public feePercentage = 1; // 1% fee from the winner

    enum BetChoice { Black, White }

    struct Challenge {
        address player;
        uint amount;
        BetChoice choice;
        address opponent;
        BetChoice winnerChoice;
        bool isCompleted;
    }

    mapping(bytes32 => Challenge) private challenges; // Now private to protect data
    mapping(address => bytes32[]) private userChallenges; // Stores a list of challenges for each user

    event ChallengeCreated(bytes32 challengeId, address indexed player, uint amount, BetChoice choice);
    event AcceptedWithColor(bytes32 challengeId, address indexed acceptor, BetChoice yourColor);
    event ChallengeAccepted(bytes32 challengeId, address indexed player1, address indexed player2, BetChoice winner, string result);
    event ChallengeRefunded(bytes32 challengeId, address indexed player);

    constructor() {
        owner = msg.sender;
    }

    function generateChallengeId(address player, uint amount) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(player, block.timestamp, amount, block.number));
    }

    function makeChallenge() public payable returns (bytes32) {
        require(msg.value > 0, "Bet must be greater than 0");

        bytes32 challengeId = generateChallengeId(msg.sender, msg.value);
        require(challenges[challengeId].player == address(0), "Challenge already exists"); 

        challenges[challengeId] = Challenge(msg.sender, msg.value, BetChoice.Black, address(0), BetChoice.Black, false);
        userChallenges[msg.sender].push(challengeId); // Save the challenge for the user
        emit ChallengeCreated(challengeId, msg.sender, msg.value, BetChoice.Black);

        return challengeId;
    }

    function getRandomResult(address player1, address player2) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.number,
            blockhash(block.number - 1),
            player1,
            player2,
            address(this).balance,
            gasleft()
        )));
    }

    function acceptChallenge(bytes32 challengeId) public payable {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.player != address(0), "No active challenge with such ID");
        require(!challenge.isCompleted, "Challenge already completed");
        require(msg.value == challenge.amount, string(abi.encodePacked("Amount must be exactly ", _uintToString(challenge.amount), " wei")));

        BetChoice acceptorColor = (challenge.choice == BetChoice.Black) ? BetChoice.White : BetChoice.Black;
        emit AcceptedWithColor(challengeId, msg.sender, acceptorColor);

        uint totalPot = challenge.amount * 2;
        uint256 random = getRandomResult(challenge.player, msg.sender);
        BetChoice winnerChoice = (random % 2 == 0) ? BetChoice.Black : BetChoice.White;
        address winner = (winnerChoice == challenge.choice) ? challenge.player : msg.sender;

        uint fee = (totalPot * feePercentage) / 100;
        uint payout = totalPot - fee;

        payable(winner).transfer(payout);
        payable(owner).transfer(fee);

        challenge.opponent = msg.sender;
        challenge.winnerChoice = winnerChoice;
        challenge.isCompleted = true;

        userChallenges[msg.sender].push(challengeId); // Save the challenge for the second player

        string memory resultMessage = (winner == msg.sender) ? "You won!" : "You lost!";
        emit ChallengeAccepted(challengeId, challenge.player, msg.sender, winnerChoice, resultMessage);
    }

    function cancelChallenge(bytes32 challengeId) public {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.player == msg.sender, "You did not create this challenge");
        require(!challenge.isCompleted, "Challenge already completed");

        payable(msg.sender).transfer(challenge.amount);
        delete challenges[challengeId];
        emit ChallengeRefunded(challengeId, msg.sender);
    }

    function getAllChallenges() public view returns (bytes32[] memory) {
        return userChallenges[msg.sender];
    }

    function getChallengeStatus(bytes32 challengeId) public view returns (string memory) {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.player != address(0), "Challenge not found");

        string memory status;
        if (!challenge.isCompleted) {
            status = "Waiting for an opponent";
        } else if (challenge.winnerChoice == challenge.choice) {
            status = "Winner: Challenge creator";
        } else {
            status = "Winner: Challenge acceptor";
        }

        return string(
            abi.encodePacked(
                "Created by: ", _addressToString(challenge.player),
                "\nBet size: ", _uintToString(challenge.amount),
                "\nAccepted by: ", _addressToString(challenge.opponent),
                "\nStatus: ", status
            )
        );
    }

    function _addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function _uintToString(uint _value) internal pure returns (string memory) {
        if (_value == 0) {
            return "0";
        }
        uint temp = _value;
        uint digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint(_value % 10)));
            _value /= 10;
        }
        return string(buffer);
    }
}
