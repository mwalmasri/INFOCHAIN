import os, json, sys
from web3 import Web3
from eth_account import Account
from pathlib import Path

# Load environment variables
RPC_URL = os.getenv("INFOCHAIN_RPC_URL", "http://127.0.0.1:8545")
PRIVATE_KEY = os.getenv("INFOCHAIN_PRIVATE_KEY")
CONTRACT_ADDRESS = os.getenv("INFOCHAIN_ADDRESS", "0x5FbDB2315678afecb367f032d93F642f64180aa3")
ADMIN_ADDRESS = os.getenv("INFOCHAIN_ADMIN")

# Load ABI (generate via `forge inspect InfoChain abi > out/InfoChain.json`)
ABI_PATH = Path("out/InfoChain.json")
if not ABI_PATH.exists():
    raise RuntimeError("ABI not found. Run `forge build` first.")
with open(ABI_PATH) as f:
    ABI = json.load(f)["abi"]

def submit_epoch(json_path: str):
    if not os.path.exists(json_path):
        print(f"❌ File not found: {json_path}")
        sys.exit(1)

    with open(json_path) as f:
        data = json.load(f)

    w3 = Web3(Web3.HTTPProvider(RPC_URL))
    account = Account.from_key(PRIVATE_KEY)
    contract = w3.eth.contract(address=CONTRACT_ADDRESS, abi=ABI)

    tx = contract.functions.submitEpochResults(
        epochId=data.get("epoch_id", 1),
        forecasters=data["forecasters"],
        calScores=data["cal_scores"],
        rewardWeights=data["reward_weights"],
        voiMultiplier=data["voi_multiplier"],
        zkProof=bytes(32)  # Replace with actual ZK proof when ready
    ).build_transaction({
        "from": account.address,
        "gas": 2_000_000,
        "gasPrice": w3.eth.gas_price,
        "nonce": w3.eth.get_transaction_count(account.address),
        "chainId": w3.eth.chain_id
    })

    signed = w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

    print(f"✅ Transaction sent: {tx_hash.hex()}")
    print(f"📊 Status: {'✅ Success' if receipt.status == 1 else '❌ Failed'}")
    print(f"⛽ Gas used: {receipt.gasUsed}")
    return receipt

if __name__ == "__main__":
    json_file = sys.argv[1] if len(sys.argv) > 1 else "epoch_output.json"
    submit_epoch(json_file)