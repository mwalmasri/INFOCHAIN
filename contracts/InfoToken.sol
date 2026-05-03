// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title InfoToken ($INFO)
 * @notice Native token for InfoChain Protocol with staking, vesting, and governance utilities
 */
contract InfoToken is ERC20, ERC20Permit, Ownable, Pausable, ReentrancyGuard {
    uint256 public constant PRECISION = 1e18;
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * PRECISION; // 1B tokens
    uint256 public constant EMISSION_RATE = 50_000 * PRECISION; // 50k tokens/epoch
    
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 released;
        uint256 startTime;
        uint256 duration;
        bool active;
    }
    
    struct StakeInfo {
        uint256 amount;
        uint256 lockedUntil;
        uint256 lastRewardEpoch;
    }
    
    mapping(address => VestingSchedule) public vesting;
    mapping(address => StakeInfo) public stakes;
    mapping(address => uint256) public delegatedStake;
    mapping(address => mapping(address => bool)) public delegates;
    
    uint256 public totalStaked;
    uint256 public currentEpoch;
    
    event Staked(address indexed user, uint256 amount, uint256 lockDuration);
    event Unstaked(address indexed user, uint256 amount);
    event Vested(address indexed beneficiary, uint256 amount);
    event Delegated(address indexed delegator, address indexed delegate, uint256 amount);
    event EpochAdvanced(uint256 indexed epoch, uint256 emission);
    
    constructor() 
        ERC20("InfoChain", "INFO") 
        ERC20Permit("InfoChain")
    {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
    
    // ===== STAKING =====
    
    function stake(uint256 amount, uint256 lockDuration) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        require(lockDuration <= 365 days, "Lock too long");
        
        _transfer(msg.sender, address(this), amount);
        
        StakeInfo storage stake = stakes[msg.sender];
        stake.amount += amount;
        stake.lockedUntil = block.timestamp + lockDuration;
        stake.lastRewardEpoch = currentEpoch;
        
        totalStaked += amount;
        
        emit Staked(msg.sender, amount, lockDuration);
    }
    
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        StakeInfo storage stake = stakes[msg.sender];
        require(stake.amount >= amount, "Insufficient stake");
        require(block.timestamp >= stake.lockedUntil, "Tokens locked");
        
        stake.amount -= amount;
        totalStaked -= amount;
        
        _transfer(address(this), msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }
    
    // ===== VESTING =====
    
    function createVestingSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 duration
    ) external onlyOwner {
        require(!vesting[beneficiary].active, "Schedule exists");
        require(totalAmount > 0, "Amount must be > 0");
        require(duration > 0, "Duration must be > 0");
        
        vesting[beneficiary] = VestingSchedule({
            totalAmount: totalAmount,
            released: 0,
            startTime: startTime,
            duration: duration,
            active: true
        });
        
        // Lock tokens in contract
        _transfer(msg.sender, address(this), totalAmount);
    }
    
    function claimVested() external nonReentrant whenNotPaused {
        VestingSchedule storage schedule = vesting[msg.sender];
        require(schedule.active, "No vesting schedule");
        
        uint256 vested = _calculateVestedAmount(schedule);
        uint256 claimable = vested - schedule.released;
        require(claimable > 0, "Nothing to claim");
        
        schedule.released += claimable;
        _transfer(address(this), msg.sender, claimable);
        
        emit Vested(msg.sender, claimable);
    }
    
    function _calculateVestedAmount(VestingSchedule storage schedule) internal view returns (uint256) {
        if (block.timestamp < schedule.startTime) return 0;
        if (block.timestamp >= schedule.startTime + schedule.duration) return schedule.totalAmount;
        
        uint256 elapsed = block.timestamp - schedule.startTime;
        return (schedule.totalAmount * elapsed) / schedule.duration;
    }
    
    // ===== DELEGATION (for governance) =====
    
    function delegate(address delegatee, uint256 amount) external {
        require(stakes[msg.sender].amount >= amount, "Insufficient stake");
        
        if (delegates[msg.sender][delegatee]) {
            delegatedStake[delegatee] -= amount;
            delete delegates[msg.sender][delegatee];
        } else {
            delegatedStake[delegatee] += amount;
            delegates[msg.sender][delegatee] = true;
        }
        
        emit Delegated(msg.sender, delegatee, amount);
    }
    
    function getEffectiveStake(address account) external view returns (uint256) {
        return stakes[account].amount + delegatedStake[account];
    }
    
    // ===== EPOCH & EMISSION =====
    
    function advanceEpoch() external onlyOwner {
        currentEpoch++;
        uint256 emission = EMISSION_RATE;
        _mint(address(this), emission); // Mint new tokens to contract for rewards
        emit EpochAdvanced(currentEpoch, emission);
    }
    
    // ===== ADMIN =====
    
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
}