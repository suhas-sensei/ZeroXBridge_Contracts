// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ZeroXBridgeL1.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
// Mock GPS Statement Verifier for testing

contract MockGpsStatementVerifier is IGpsStatementVerifier {
    bool public shouldVerifySucceed = true;
    mapping(bytes32 => bool) public registeredProofs;

    function setShouldVerifySucceed(bool _shouldSucceed) external {
        shouldVerifySucceed = _shouldSucceed;
    }

    function verifyProofAndRegister(
        uint256[] calldata proofParams,
        uint256[] calldata proof,
        uint256[] calldata publicInputs,
        uint256 cairoVerifierId
    ) external override returns (bool) {
        bytes32 proofHash = keccak256(abi.encodePacked(proof));
        require(!registeredProofs[proofHash], "Proof already registered");

        if (shouldVerifySucceed) {
            registeredProofs[proofHash] = true;
            return true;
        }
        return false;
    }

    function isProofRegistered(uint256[] calldata proof) external view returns (bool) {
        bytes32 proofHash = keccak256(abi.encodePacked(proof));
        return registeredProofs[proofHash];
    }
}

contract ZeroXBridgeTest is Test {
    ZeroXBridgeL1 public bridge;
    MockGpsStatementVerifier public mockVerifier;
    MockERC20 public token;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public relayer = address(0x4);
    address public nonRelayer = address(0x5);

    uint256 public cairoVerifierId = 123456789;

    uint256[] public proofParams;
    uint256[] public proof;

    event FundsUnlocked(address indexed user, uint256 amount, bytes32 commitmentHash);

    event RelayerStatusChanged(address indexed relayer, bool status);

    event FundsClaimed(address indexed user, uint256 amount);

    function setUp() public {
        vm.startPrank(owner);

        // Initialize mock verifier
        mockVerifier = new MockGpsStatementVerifier();

        // Deploy Mock ERC20 Token
        token = new MockERC20("MockToken", "MTK");

        // Initialize bridge with mock verifier
        address admin = address(0x123);
        bridge = new ZeroXBridgeL1(address(mockVerifier), admin, cairoVerifierId, owner, address(token));

        // Setup approved relayer
        bridge.setRelayerStatus(relayer, true);

        // Mint tokens to the contract for testing
        uint256 initialMintAmount = 1000000 * 10 ** 18; // 1 million tokens
        token.mint(address(bridge), initialMintAmount);

        // Initialize proof array with dummy values for testing
        for (uint256 i = 0; i < 10; i++) {
            proofParams.push(i);
            proof.push(i + 100);
        }

        vm.stopPrank();
    }

    // ========================
    // Ownership Tests
    // ========================

    function testOwnership() public view {
        assertEq(bridge.owner(), owner);
    }

    function testFailNonOwnerFunctions() public {
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        bridge.setRelayerStatus(relayer, false);

        vm.expectRevert("Ownable: caller is not the owner");
        bridge.updateGpsVerifier(address(0));

        vm.expectRevert("Ownable: caller is not the owner");

        bridge.updateCairoVerifierId(0);
        vm.stopPrank();
    }

    // ========================
    // Relayer Management Tests
    // ========================

    function testSetRelayerStatus() public {
        vm.startPrank(owner);

        // Test adding a relayer
        vm.expectEmit(true, true, true, true);
        emit RelayerStatusChanged(user1, true);
        bridge.setRelayerStatus(user1, true);
        assertTrue(bridge.approvedRelayers(user1));

        // Test removing a relayer
        vm.expectEmit(true, true, true, true);
        emit RelayerStatusChanged(user1, false);
        bridge.setRelayerStatus(user1, false);
        assertFalse(bridge.approvedRelayers(user1));

        vm.stopPrank();
    }

    function testOnlyApprovedRelayersCanSubmitProofs() public {
        uint256 amount = 1 ether;
        uint256 l2TxId = 12345;
        bytes32 commitmentHash = keccak256(abi.encodePacked(uint256(uint160(user1)), amount, l2TxId, block.chainid));

        // Non-relayer attempt should fail
        vm.startPrank(nonRelayer);
        vm.expectRevert("ZeroXBridge: Only approved relayers can submit proofs");
        bridge.unlock_funds_with_proof(proofParams, proof, user1, amount, l2TxId, commitmentHash);
        vm.stopPrank();

        // Approved relayer should succeed (assuming valid proof)
        vm.prank(relayer);
        bridge.unlock_funds_with_proof(proofParams, proof, user1, amount, l2TxId, commitmentHash);

        // Verify funds were added
        assertEq(bridge.claimableFunds(user1), amount);
    }

    // ========================
    // Configuration Tests
    // ========================

    function testUpdateGpsVerifier() public {
        address newVerifier = address(0x123);

        vm.prank(owner);
        bridge.updateGpsVerifier(newVerifier);

        assertEq(address(bridge.gpsVerifier()), newVerifier);
    }

    function testUpdateCairoVerifierId() public {
        uint256 newVerifierId = 987654321;

        vm.prank(owner);
        bridge.updateCairoVerifierId(newVerifierId);

        assertEq(bridge.cairoVerifierId(), newVerifierId);
    }

    // ========================
    // Proof Verification Tests
    // ========================

    function testSuccessfulProofVerification() public {
        uint256 amount = 2 ** 18; // amount to unlock
        uint256 l2TxId = 12345;
        bytes32 commitmentHash = keccak256(abi.encodePacked(uint256(uint160(user1)), amount, l2TxId, block.chainid));

        // Ensure mock verifier will succeed
        mockVerifier.setShouldVerifySucceed(true);

        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit FundsUnlocked(user1, amount, commitmentHash);
        bridge.unlock_funds_with_proof(proofParams, proof, user1, amount, l2TxId, commitmentHash);

        // Verify funds were added
        assertEq(bridge.claimableFunds(user1), amount);

        // Verify the proof and commitment are marked as used
        bytes32 proofHash = keccak256(abi.encodePacked(proof));
        assertTrue(bridge.verifiedProofs(proofHash));
        assertTrue(bridge.verifiedProofs(commitmentHash));
    }

    function testFailingProofVerification() public {
        uint256 amount = 1 ether;
        uint256 l2TxId = 12345;
        bytes32 commitmentHash = keccak256(abi.encodePacked(uint256(uint160(user1)), amount, l2TxId, block.chainid));

        // Set verifier to fail
        mockVerifier.setShouldVerifySucceed(false);

        vm.prank(relayer);
        // vm.expectRevert("ZeroXBridge: Invalid proof");
        vm.expectRevert(abi.encodePacked("ZeroXBridge: Invalid proof"));

        try bridge.unlock_funds_with_proof(proofParams, proof, user1, amount, l2TxId, commitmentHash) {
            fail();
        } catch (bytes memory revertData) {
            console.log("Revert data:");
            console.logBytes(revertData);
        }

        // Verify no funds were added
        assertEq(bridge.claimableFunds(user1), 0);
    }

    function testInvalidCommitmentHash() public {
        uint256 amount = 1 ether;
        uint256 l2TxId = 12345;
        // Deliberately create wrong commitment hash
        bytes32 wrongCommitmentHash = keccak256(abi.encodePacked("wrong data"));

        vm.prank(relayer);
        vm.expectRevert("ZeroXBridge: Invalid commitment hash");
        bridge.unlock_funds_with_proof(proofParams, proof, user1, amount, l2TxId, wrongCommitmentHash);
    }

    // ========================
    // Replay Attack Prevention Tests
    // ========================

    function testPreventProofReuse() public {
        uint256 amount = 1 ether;
        uint256 l2TxId = 12345;
        bytes32 commitmentHash = keccak256(abi.encodePacked(uint256(uint160(user1)), amount, l2TxId, block.chainid));

        // First attempt should succeed
        vm.prank(relayer);
        bridge.unlock_funds_with_proof(proofParams, proof, user1, amount, l2TxId, commitmentHash);

        // Same proof should be rejected
        vm.prank(relayer);
        vm.expectRevert("ZeroXBridge: Proof has already been used");
        bridge.unlock_funds_with_proof(proofParams, proof, user1, amount, l2TxId, commitmentHash);
    }

    function testPreventCommitmentReuse() public {
        uint256 amount = 1 ether;
        uint256 l2TxId = 12345;
        bytes32 commitmentHash = keccak256(abi.encodePacked(uint256(uint160(user1)), amount, l2TxId, block.chainid));

        // First attempt should succeed
        vm.prank(relayer);
        bridge.unlock_funds_with_proof(proofParams, proof, user1, amount, l2TxId, commitmentHash);

        // Create different proof but same commitment
        uint256[] memory differentProof = new uint256[](proof.length);
        for (uint256 i = 0; i < proof.length; i++) {
            differentProof[i] = proof[i] + 1000; // Make it different
        }

        // Mock verifier needs to be reset for new proof
        MockGpsStatementVerifier newMock = new MockGpsStatementVerifier();
        vm.prank(owner);
        bridge.updateGpsVerifier(address(newMock));

        // Different proof but same commitment should be rejected
        vm.prank(relayer);
        vm.expectRevert("ZeroXBridge: Commitment already processed");
        bridge.unlock_funds_with_proof(proofParams, differentProof, user1, amount, l2TxId, commitmentHash);
    }

    // ========================
    // Claim Function Tests
    // ========================

    function testSuccessfulClaim() public {
        testSuccessfulProofVerification();

        // Set claimable funds for user1
        uint256 amount = bridge.claimableFunds(user1);

        uint256 contractBalance = token.balanceOf(address(bridge));

        console.log("contract funds: ", token.balanceOf(address(bridge)));

        // Expect the FundsClaimed event to be emitted
        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(user1, amount);

        // User claims the funds
        vm.startPrank(user1);
        bridge.claimFunds();
        vm.stopPrank();

        // Assert that the user's claimable funds are now 0
        assertEq(bridge.claimableFunds(user1), 0);

        // Check if the contract's token balance has decreased by the claimed amount
        assertEq(token.balanceOf(address(bridge)), contractBalance - amount);
        assertEq(token.balanceOf(user1), amount);
    }

    function testClaimNoFunds() public {
        vm.startPrank(user1);
        vm.expectRevert("ZeroXBridge: No funds to claim");
        bridge.claimFunds();
        vm.stopPrank();
    }

    function testClaimAfterFundsClaimed() public {
        testSuccessfulProofVerification();

        // Claim the funds
        vm.prank(user1);
        bridge.claimFunds();

        // Try to claim again, should fail because funds are already claimed
        vm.startPrank(user1);
        vm.expectRevert("ZeroXBridge: No funds to claim");
        bridge.claimFunds();
        vm.stopPrank();
    }
}
