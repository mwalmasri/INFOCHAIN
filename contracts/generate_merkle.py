#!/usr/bin/env python3
"""
Generate Merkle root and claims from epoch output for gas-optimized distribution.
Usage: python3 scripts/generate_merkle.py epoch_output.json > merkle_output.json
"""
import json, sys, hashlib
from eth_utils import keccak

def hash_leaf(account: str, amount: int, epoch: int) -> bytes:
    """Hash a single claim leaf: keccak256(account || amount || epoch)"""
    data = (
        bytes.fromhex(account.replace("0x", "")) +  # account (20 bytes)
        amount.to_bytes(32, "big") +                # amount (uint256)
        epoch.to_bytes(32, "big")                   # epoch (uint256)
    )
    return keccak(data)

def build_merkle_tree(leaves: list[bytes]) -> tuple[bytes, list[list[bytes]]]:
    """Build Merkle tree, return (root, proofs_for_each_leaf)"""
    if not leaves:
        return bytes(32), []
    
    # Pad to power of 2
    n = 1
    while n < len(leaves):
        n *= 2
    leaves = leaves + [bytes(32)] * (n - len(leaves))
    
    tree = [leaves]
    level = leaves
    
    while len(level) > 1:
        next_level = []
        for i in range(0, len(level), 2):
            left, right = level[i], level[i+1]
            # Sort to ensure consistent hashing
            combined = left + right if left < right else right + left
            next_level.append(keccak(combined))
        tree.append(next_level)
        level = next_level
    
    root = level[0]
    
    # Generate proofs for original leaves
    proofs = []
    for idx in range(len(leaves) // 2):  # Only original leaves
        proof = []
        node_idx = idx
        for lvl in tree[:-1]:  # Exclude root
            sibling_idx = node_idx ^ 1  # XOR to get sibling
            if sibling_idx < len(lvl):
                proof.append(lvl[sibling_idx])
            node_idx //= 2
        proofs.append(proof)
    
    return root, proofs[:len(leaves)//2]  # Trim to original count

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 generate_merkle.py epoch_output.json", file=sys.stderr)
        sys.exit(1)
    
    with open(sys.argv[1]) as f:
        epoch_data = json.load(f)
    
    # Build claims from epoch output
    claims = []
    leaves = []
    epoch = epoch_data.get("epoch_id", 1)
    
    for i, addr in enumerate(epoch_data["forecasters"]):
        amount = epoch_data["reward_weights"][i]  # Already scaled to 1e18
        claim = {"account": addr, "amount": amount, "epoch": epoch}
        claims.append(claim)
        leaves.append(hash_leaf(addr, amount, epoch))
    
    # Build Merkle tree
    root, proofs = build_merkle_tree(leaves)
    
    # Attach proofs to claims
    for i, claim in enumerate(claims):
        claim["proof"] = [p.hex() for p in proofs[i]]
    
    # Output
    output = {
        "merkle_root": root.hex(),
        "epoch": epoch,
        "claims": claims,
        "metadata": {
            "total_claims": len(claims),
            "total_amount": sum(c["amount"] for c in claims),
            "generated_at": __import__("datetime").datetime.utcnow().isoformat()
        }
    }
    
    print(json.dumps(output, indent=2))

if __name__ == "__main__":
    main()