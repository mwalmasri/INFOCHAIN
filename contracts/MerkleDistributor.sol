// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./InfoToken.sol";

/**
 * @title MerkleDistributor
 * @notice Gas-optimized reward distribution via Merkle proofs
 * @dev Reduces O(N) submission to O(1) per claim + O(1) root update
 */
contract MerkleDistributor is ReentrancyGuard {
    InfoToken public immutable token;
    bytes32 public currentRoot;
    uint256 public currentEpoch;
    
    mapping(bytes32 => bool) public claimed;
    mapping(uint256 => bytes32) public epochRoots;
    
    event RewardClaimed(address indexed claimant, uint256 amount, uint256 epoch);
    event RootUpdated(uint256 indexed epoch, bytes32 newRoot);
    
    constructor(InfoToken _token) {
        token = _token;
    }
    
    struct Claim {
        address account;
        uint256 amount;
        uint256 epoch;
    }
    
    function hashClaim(Claim memory claim) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(claim.account, claim.amount, claim.epoch));
    }
    
    function setMerkleRoot(uint256 epoch, bytes32 root) external {
        // In production: restrict to authorized scorer/oracle
        epochRoots[epoch] = root;
        if (epoch > currentEpoch) {
            currentEpoch = epoch;
            currentRoot = root;
        }
        emit RootUpdated(epoch, root);
    }
    
    function claim(
        uint256 epoch,
        Claim calldata claim,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        require(epoch <= currentEpoch, "Future epoch");
        bytes32 root = epochRoots[epoch];
        require(root != bytes32(0), "Root not set");
        
        bytes32 leaf = hashClaim(claim);
        require(MerkleProof.verify(merkleProof, root, leaf), "Invalid proof");
        
        bytes32 claimId = keccak256(abi.encodePacked(claim.account, claim.epoch));
        require(!claimed[claimId], "Already claimed");
        
        claimed[claimId] = true;
        token.transfer(claim.account, claim.amount);
        
        emit RewardClaimed(claim.account, claim.amount, epoch);
    }
    
    function isClaimed(address account, uint256 epoch) external view returns (bool) {
        bytes32 claimId = keccak256(abi.encodePacked(account, epoch));
        return claimed[claimId];
    }
    
    // Batch claim for gas efficiency (optional)
    function claimBatch(
        uint256 epoch,
        Claim[] calldata claims,
        bytes32[][] calldata proofs
    ) external nonReentrant {
        require(claims.length == proofs.length, "Length mismatch");
        require(epoch <= currentEpoch, "Future epoch");
        bytes32 root = epochRoots[epoch];
        require(root != bytes32(0), "Root not set");
        
        for (uint256 i = 0; i < claims.length; i++) {
            Claim memory claim = claims[i];
            bytes32 leaf = hashClaim(claim);
            require(MerkleProof.verify(proofs[i], root, leaf), "Invalid proof");
            
            bytes32 claimId = keccak256(abi.encodePacked(claim.account, claim.epoch));
            require(!claimed[claimId], "Already claimed");
            
            claimed[claimId] = true;
            token.transfer(claim.account, claim.amount);
            emit RewardClaimed(claim.account, claim.amount, epoch);
        }
    }
}