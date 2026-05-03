// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/InfoChain.sol";

contract InfoChainTest is Test {
    InfoChain public infoChain;
    address[] public forecasters = new address[](5);
    uint256 public constant PRECISION = 1e18;
    uint256 public constant EPOCH_DURATION = 1 hours;

    function setUp() public {
        infoChain = new InfoChain();
        infoChain.setEpochDuration(EPOCH_DURATION);
        
        // Fund & register forecasters
        for (uint i = 0; i < 5; i++) {
            forecasters[i] = makeAddr(string(abi.encodePacked("forecaster", i)));
            vm.deal(forecasters[i], 10 ether);
            vm.prank(forecasters[i]);
            infoChain.stake{value: 1 ether}();
        }
    }

    function test_CommitRevealFlow() public {
        uint256 epochId = infoChain.currentEpochId();
        bytes32 commitment = keccak256(abi.encode([0.2e18, 0.5e18, 0.3e18], 12345));
        
        vm.prank(forecasters[0]);
        infoChain.commit(epochId, commitment);
        
        vm.prank(forecasters[0]);
        vm.expectRevert(); // Already committed
        infoChain.commit(epochId, commitment);
        
        vm.prank(forecasters[0]);
        infoChain.reveal(epochId, [0.2e18, 0.5e18, 0.3e18], 12345);
    }

    function test_RewardDistribution() public {
        uint256 epochId = infoChain.currentEpochId();
        
        // Mock all forecasters commit + reveal
        for (uint i = 0; i < 5; i++) {
            bytes32 comm = keccak256(abi.encode([0.3e18, 0.4e18, 0.3e18], i));
            vm.prank(forecasters[i]);
            infoChain.commit(epochId, comm);
            vm.prank(forecasters[i]);
            infoChain.reveal(epochId, [0.3e18, 0.4e18, 0.3e18], i);
        }

        // Submit off-chain results
        uint256[] memory scores = new uint256[](5);
        uint256[] memory weights = new uint256[](5);
        scores[0] = 0; scores[1] = 376e15; scores[2] = 346e15; scores[3] = 287e15; scores[4] = 168e15;
        weights[0] = 71e15;  weights[1] = 299e15; weights[2] = 273e15; weights[3] = 228e15; weights[4] = 127e15;
        
        vm.prank(infoChain.admin());
        infoChain.submitEpochResults(epochId, forecasters, scores, weights, 914e15, bytes32(0));

        // Verify rewards > 0 for accurate forecasters
        assertGt(infoChain.pendingRewards(forecasters[1]), 0);
        assertEq(infoChain.pendingRewards(forecasters[0]), 0); // Zero score gets zero reward
    }

    function test_AntiWhaleCap() public {
        // Whale stakes 10x more
        vm.prank(forecasters[0]);
        infoChain.stake{value: 9 ether}(); // Total stake ~10 ether, whale has 90%
        
        uint256 epochId = infoChain.currentEpochId();
        bytes32 comm = keccak256(abi.encode([0.5e18, 0.3e18, 0.2e18], 1));
        vm.prank(forecasters[0]);
        infoChain.commit(epochId, comm);
        vm.prank(forecasters[0]);
        infoChain.reveal(epochId, [0.5e18, 0.3e18, 0.2e18], 1);

        uint256[] memory scores = new uint256[](1);
        uint256[] memory weights = new uint256[](1);
        scores[0] = 500e15;
        weights[0] = 800e15; // Simulate high weight
        
        vm.prank(infoChain.admin());
        infoChain.submitEpochResults(epochId, forecasters[0:1], scores, weights, 1e18, bytes32(0));
        
        uint256 reward = infoChain.pendingRewards(forecasters[0]);
        uint256 expectedCap = (infoChain.rewardPoolPerEpoch() * 800e15 / PRECISION) * 5e16 / PRECISION; // 5% cap applied
        assertLe(reward, expectedCap);
    }
}