import numpy as np
import json

PRECISION = int(1e18)
LAMBDA = 4.0  # from whitepaper
GAMMA = 0.3   # from whitepaper
STAKE_MAX_PCT = 0.05

def brier_score(preds, outcome_idx):
    """Brier (Quadratic) scoring rule"""
    one_hot = np.zeros_like(preds)
    one_hot[outcome_idx] = 1.0
    return 1.0 - np.sum((preds - one_hot)**2, axis=1)

def calibrate_scores_simple(preds, outcomes, window_size=5):
    """
    Simple NumPy-only calibration to penalize overconfidence.
    
    Strategy:
    - Compare predicted confidence (max prob) to empirical accuracy in a sliding window
    - Apply multiplicative penalty when confidence exceeds accuracy
    - Use exponential smoothing for stability
    """
    n = len(preds)
    confidences = np.max(preds, axis=1)
    predictions = np.argmax(preds, axis=1)
    correct = (outcomes == predictions).astype(float)
    
    # Initialize calibration factors
    cal_factors = np.ones(n)
    
    # Simple moving-window reliability check
    for i in range(n):
        # Look back at recent predictions (including current)
        start_idx = max(0, i - window_size + 1)
        recent_conf = confidences[start_idx:i+1]
        recent_correct = correct[start_idx:i+1]
        
        if len(recent_conf) < 2:
            continue  # Not enough data for calibration
            
        # Empirical accuracy in window
        empirical_acc = np.mean(recent_correct)
        avg_conf = np.mean(recent_conf)
        
        # Penalize overconfidence: if avg_conf > empirical_acc, reduce score
        if avg_conf > empirical_acc + 1e-6:  # tolerance for floating point
            # Penalty factor: closer to 0 as overconfidence increases
            overconf_ratio = (avg_conf - empirical_acc) / (avg_conf + 1e-9)
            penalty = 1.0 - 0.5 * overconf_ratio  # max 50% penalty
            cal_factors[i] = penalty
        elif avg_conf < empirical_acc - 1e-6:
            # Bonus for underconfidence (optional, can be disabled)
            underconf_ratio = (empirical_acc - avg_conf) / (empirical_acc + 1e-9)
            bonus = 1.0 + 0.2 * underconf_ratio  # max 20% bonus
            cal_factors[i] = min(bonus, 1.2)  # cap bonus
    
    # Smooth calibration factors to avoid sharp jumps
    if n > 1:
        cal_factors = np.convolve(cal_factors, np.ones(3)/3, mode='same')
    
    return np.clip(cal_factors, 0.5, 1.2)  # bound factors

def compute_entropy(mean_preds):
    """Network forecast entropy H_t"""
    mean_preds = np.clip(mean_preds, 1e-9, 1.0)
    return -np.sum(mean_preds * np.log(mean_preds + 1e-9), axis=1)

def compute_reward_weights(scores, stakes, total_stake):
    """Compute exp(λ*S) normalized to sum PRECISION, apply anti-whale"""
    exp_weights = np.exp(LAMBDA * scores)
    norm_weights = exp_weights / np.sum(exp_weights)
    
    stake_pcts = stakes / total_stake
    anti_whale = np.ones_like(stake_pcts)
    over_cap = np.maximum(0, stake_pcts - STAKE_MAX_PCT)
    anti_whale -= over_cap * 0.5  # dampening factor
    anti_whale = np.clip(anti_whale, 0, 1)
    
    final_weights = norm_weights * anti_whale
    final_weights /= np.sum(final_weights)  # re-normalize
    return (final_weights * PRECISION).astype(np.uint64)

def run_epoch_simulation(n_forecasters=5, n_bins=3):
    np.random.seed(42)
    # Mock predictions: each forecaster outputs probability distribution over bins
    preds = np.random.dirichlet(np.ones(n_bins), size=n_forecasters)
    true_outcome = np.random.randint(0, n_bins)
    
    raw_scores = brier_score(preds, true_outcome)
    
    # Use simple calibration (no scipy dependency)
    cal_factors = calibrate_scores_simple(preds, np.full(n_forecasters, true_outcome))
    cal_scores = np.clip(raw_scores * cal_factors, 0, 1)
    
    # Entropy & VoI
    mean_pred = np.mean(preds, axis=0)
    entropy = compute_entropy(mean_pred.reshape(1, -1))[0]
    voi_multiplier = np.clip(1.0 / max(entropy, 0.1), 0.5, 2.0)  # bounded for stability
    
    # Mock stakes
    stakes = np.random.randint(10, 100, size=n_forecasters).astype(float)
    total_stake = np.sum(stakes)
    weights = compute_reward_weights(cal_scores, stakes, total_stake)
    
    return {
        "cal_scores": (cal_scores * PRECISION).astype(int).tolist(),
        "reward_weights": weights.tolist(),
        "voi_multiplier": int(voi_multiplier * PRECISION),
        "forecasters": [f"0xAddr_{i}" for i in range(n_forecasters)],
        "metadata": {"true_outcome": int(true_outcome), "entropy": float(entropy)}
    }

if __name__ == "__main__":
    results = run_epoch_simulation()
    print(json.dumps(results, indent=2))
    # Output can be piped to contract's submitEpochResults()