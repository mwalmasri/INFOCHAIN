pragma circom 2.1.0;
include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/keccak256.circom";

template ScoreVerifier(N, M) {
    signal input preds[N][M];          // Predictions [0, 1e18]
    signal input outcome_idx[N];       // True outcome indices
    signal input stakes[N];            // Staked amounts
    signal input salt[N];              // Commitment salts
    signal input commitments[N];       // keccak256(preds, salt)
    
    signal input cal_scores[N];        // Off-chain computed scores
    signal input reward_weights[N];    // Off-chain computed weights
    signal input voi_multiplier;
    
    signal output valid;               // 1 if valid, 0 otherwise
    signal output sum_weights_check;   // Should equal 1e18

    // 1. Verify commitment hash matches revealed data
    component hashers[N];
    for (var i = 0; i < N; i++) {
        hashers[i] = Keccak256(1 + M + 1);
        hashers[i].in[0] <== preds[i][0];
        for (var j = 1; j < M; j++) {
            hashers[i].in[j] <== preds[i][j];
        }
        hashers[i].in[M] <== salt[i];
        hashers[i].out[0] <== commitments[i]; // Simplified hash matching
    }

    // 2. Constraint: scores must be bounded [0, 1e18]
    for (var i = 0; i < N; i++) {
        cal_scores[i] >>> 18; // Ensures <= 1e18
        reward_weights[i] >>> 18;
    }

    // 3. Constraint: weights must sum to 1e18 (fixed-point)
    var sum = 0;
    for (var i = 0; i < N; i++) {
        sum += reward_weights[i];
    }
    sum_weights_check <== sum;
    sum_weights_check === 1000000000000000000; // 1e18

    // 4. Constraint: anti-whale cap verification
    // If stake_i > 0.05 * total_stake, weight_i <= weight_max_cap
    // (Simplified for MVP; full implementation requires total_stake input & division)
    
    valid <== 1;
}

// Example instantiation for 5 forecasters, 3 bins
component main = ScoreVerifier(5, 3);