// SPDX-License-Identifier: MIT pragma solidity ^0.8.20;

/**
 * @title InfoChain Protocol MVP
 * @notice Core on-chain settlement layer for verifiable information value
 * @dev Uses 1e18 fixed-point scaling. Off-chain computes exp(), calibration, VoI.
 */
contract InfoChain {
    uint256 public constant PRECISION = 1e18;
    uint256 public constant ALPHA = 85e16; // 0.85 reputation decay
    uint256 public constant STAKE_MAX_PCT = 5e16; // 5% anti-whale cap
    uint256 public constant MIN_STAKE = 0.1 ether;

    struct Epoch {
        uint256 startTime;
        uint256 endTime;
        bool active;
        bool revealed;
        bool scored;
        mapping(address => bytes32) commitments;
        mapping(address => uint256[]) predictions;
        address[] forecasters;
    }

    struct ForecasterData {
        uint256 stake;
        int256 reputation; // scaled 1e18
        uint256 lastUpdated;
    }

    uint256 public currentEpochId;
    uint256 public epochDuration = 1 days;
    uint256 public rewardPoolPerEpoch = 1000 ether;
    address public admin;

    mapping(uint256 => Epoch) public epochs;
    mapping(address => ForecasterData) public forecasters;
    mapping(address => uint256) public pendingRewards;

    modifier onlyAdmin() { require(msg.sender == admin, "Not admin"); _; }
    modifier onlySelfOrAdmin(address _addr) {
        require(msg.sender == _addr || msg.sender == admin, "Unauthorized");
        _;
    }

    event Staked(address indexed forecaster, uint256 amount);
    event Committed(uint256 epochId, address indexed forecaster, bytes32 hash);
    event Revealed(uint256 epochId, address indexed forecaster);
    event ScoresSubmitted(uint256 epochId, address[] forecasters, uint256[] weights, uint256 voi);
    event RewardsClaimed(address indexed forecaster, uint256 amount);

    constructor() {
        admin = msg.sender;
        currentEpochId = 1;
        epochs[1].startTime = block.timestamp;
        epochs[1].endTime = block.timestamp + epochDuration;
        epochs[1].active = true;
    }

    function stake() external payable {
        require(msg.value >= MIN_STAKE, "Min stake");
        forecasters[msg.sender].stake += msg.value;
        if (forecasters[msg.sender].lastUpdated == 0) {
            forecasters[msg.sender].lastUpdated = block.timestamp;
        }
        emit Staked(msg.sender, msg.value);
    }

    function commit(uint256 epochId, bytes32 predictionHash) external {
        Epoch storage ep = epochs[epochId];
        require(ep.active && !ep.revealed, "Invalid epoch");
        require(ep.commitments[msg.sender] == bytes32(0), "Already committed");
        if (forecasters[msg.sender].stake < MIN_STAKE) revert("Insufficient stake");
        
        ep.commitments[msg.sender] = predictionHash;
        bool isNew = true;
        for (uint i = 0; i < ep.forecasters.length; i++) {
            if (ep.forecasters[i] == msg.sender) isNew = false;
        }
        if (isNew) ep.forecasters.push(msg.sender);
        emit Committed(epochId, msg.sender, predictionHash);
    }

    function reveal(uint256 epochId, uint256[] memory prediction, uint256 salt) external {
        Epoch storage ep = epochs[epochId];
        require(ep.active && !ep.revealed, "Invalid epoch");
        bytes32 expected = ep.commitments[msg.sender];
        require(expected != bytes32(0), "Not committed");
        require(keccak256(abi.encode(prediction, salt)) == expected, "Hash mismatch");

        ep.predictions[msg.sender] = prediction;
        ep.revealed = true; // Simplified: epoch-wide reveal flag
        emit Revealed(epochId, msg.sender);
    }

    /**
     * @notice Submit off-chain computed scores, normalized reward weights, and VoI
     * @dev In production: verify zkProof on-chain. MVP uses admin trust model.
     */
    function submitEpochResults(
        uint256 epochId,
        address[] calldata _forecasters,
        uint256[] calScores, // raw normalized scores [0, 1e18]
        uint256[] calRewardWeights, // pre-computed exp(lambda*S) normalized to sum 1e18
        uint256 voIMultiplier, // scaled 1e18
        bytes calldata zkProof
    ) external onlyAdmin {
        Epoch storage ep = epochs[epochId];
        require(ep.revealed && !ep.scored, "Already scored");
        require(_forecasters.length == calScores.length && calScores.length == calRewardWeights.length, "Length mismatch");

        // 1. Distribute rewards proportionally to weights * anti-whale * VoI
        uint256 totalReward = 0;
        for (uint i = 0; i < _forecasters.length; i++) {
            address f = _forecasters[i];
            uint256 stakePct = (forecasters[f].stake * PRECISION) / (ep.active ? 1e18 : 1e18); // Simplified total stake tracking
            uint256 antiWhale = PRECISION - (stakePct > STAKE_MAX_PCT ? (stakePct - STAKE_MAX_PCT) / 2 : 0);
            antiWhale = antiWhale > PRECISION ? PRECISION : antiWhale;
            
            uint256 reward = (calRewardWeights[i] * voIMultiplier) / PRECISION;
            reward = (reward * antiWhale) / PRECISION;
            pendingRewards[f] += reward;
            totalReward += reward;

            // 2. Update reputation: Rep_new = α*Rep_old + (1-α)*Score
            int256 oldRep = forecasters[f].reputation;
            int256 scoreScaled = int256(calScores[i]);
            forecasters[f].reputation = int256((ALPHA * oldRep + (PRECISION - ALPHA) * scoreScaled) / PRECISION);
            forecasters[f].lastUpdated = block.timestamp;
        }

        ep.scored = true;
        emit ScoresSubmitted(epochId, _forecasters, calRewardWeights, voIMultiplier);
    }

    function claimRewards() external {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "No rewards");
        pendingRewards[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        emit RewardsClaimed(msg.sender, amount);
    }

    function slash(address forecaster, uint256 amount) external onlySelfOrAdmin(forecaster) {
        require(forecasters[forecaster].stake >= amount, "Insufficient stake");
        forecasters[forecaster].stake -= amount;
        // In production: route slashed funds to treasury or burn
    }

    receive() external payable {}
}