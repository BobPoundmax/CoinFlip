// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CoinFlipChallenge { 
    address public owner;
    uint public feePercentage = 1; // 1% fee from the winner

    enum BetChoice { Black, White }

    struct Challenge {
        address player;
        uint amount;
        BetChoice choice;
    }

    mapping(bytes32 => Challenge) public challenges; // Mapping challenges by their unique ID (hash)

    event ChallengeCreated(bytes32 challengeId, address indexed player, uint amount, BetChoice choice);
    event AcceptedWithColor(bytes32 challengeId, address indexed acceptor, BetChoice yourColor);
    event ChallengeAccepted(bytes32 challengeId, address indexed player1, address indexed player2, BetChoice winner);
    event ChallengeRefunded(bytes32 challengeId, address indexed player);

    constructor() {
        owner = msg.sender;
    }

    // Function to generate a unique challenge ID (hash)
    function generateChallengeId(address player, uint amount) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(player, block.timestamp, amount, block.number));
    }

    // Create a challenge and return its unique ID
    function makeChallenge(BetChoice _choice) public payable returns (bytes32) {
        require(msg.value > 0, "Bet must be greater than 0");

        bytes32 challengeId = generateChallengeId(msg.sender, msg.value);
        require(challenges[challengeId].player == address(0), "Challenge already exists"); 

        challenges[challengeId] = Challenge(msg.sender, msg.value, _choice);
        emit ChallengeCreated(challengeId, msg.sender, msg.value, _choice);

        return challengeId;
    }

    // Function to generate a random number for fair winner selection
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

    // Accept a challenge using its unique ID (hash)
    function acceptChallenge(bytes32 challengeId) public payable {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.player != address(0), "No active challenge with such ID");
        require(msg.value == challenge.amount, "Amount must match the bet");

        // Automatically assign the acceptor the opposite color
        BetChoice acceptorColor = (challenge.choice == BetChoice.Black) ? BetChoice.White : BetChoice.Black;
        
        // Notify the acceptor of their assigned color
        emit AcceptedWithColor(challengeId, msg.sender, acceptorColor);

        uint totalPot = challenge.amount * 2;

        // Generate a pseudo-random number using both players' addresses
        uint256 random = getRandomResult(challenge.player, msg.sender);
        BetChoice winnerChoice = (random % 2 == 0) ? BetChoice.Black : BetChoice.White;
        
        // Determine the winner
        address winner = (winnerChoice == challenge.choice) ? challenge.player : msg.sender;

        uint fee = (challenge.amount * feePercentage) / 100; // 1% fee from the winner
        uint payout = totalPot - fee;

        payable(winner).transfer(payout);
        payable(owner).transfer(fee);

        delete challenges[challengeId];
        emit ChallengeAccepted(challengeId, challenge.player, msg.sender, winnerChoice);
    }

    function cancelChallenge(bytes32 challengeId) public {
        Challenge storage challenge = challenges[challengeId];
        require(challenge.player == msg.sender, "You did not create this challenge");

        payable(msg.sender).transfer(challenge.amount);

        delete challenges[challengeId];
        emit ChallengeRefunded(challengeId, msg.sender);
    }
}
