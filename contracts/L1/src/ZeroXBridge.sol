// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGpsStatementVerifier {
    function verifyProofAndRegister(
        uint256[] calldata proofParams,
        uint256[] calldata proof,
        uint256[] calldata publicInputs,
        uint256 cairoVerifierId
    ) external returns (bool);
}

contract ZeroXBridge is Ownable {
    using SafeERC20 for IERC20;

    // Starknet GPS Statement Verifier interface
    IGpsStatementVerifier public gpsVerifier;

    // Track verified proofs to prevent replay attacks
    mapping(bytes32 => bool) public verifiedProofs;

    // Track claimable funds per user
    mapping(address => uint256) public claimableFunds;

    // Approved relayers that can submit proofs
    mapping(address => bool) public approvedRelayers;

    // Cairo program hash that corresponds to the burn verification program
    uint256 public cairoVerifierId;

    IERC20 public token;

    // Events
    event FundsUnlocked(address indexed user, uint256 amount, bytes32 commitmentHash);
    event RelayerStatusChanged(address indexed relayer, bool status);
    event FundsClaimed(address indexed user, uint256 amount);

    constructor(address _gpsVerifier, uint256 _cairoVerifierId, address _initialOwner, address _token)
        Ownable(_initialOwner)
    {
        gpsVerifier = IGpsStatementVerifier(_gpsVerifier);
        cairoVerifierId = _cairoVerifierId;
        token = IERC20(_token);
    }

    function setRelayerStatus(address relayer, bool status) external onlyOwner {
        approvedRelayers[relayer] = status;
        emit RelayerStatusChanged(relayer, status);
    }

    /**
     * @dev Processes a burn zkProof from L2 and unlocks equivalent funds for the user
     * @param proof The zkProof data array
     * @param user The address that will receive the unlocked funds
     * @param amount The amount to unlock
     * @param l2TxId The L2 transaction ID for uniqueness
     * @param commitmentHash The hash of the commitment data that should match proof
     */
    function unlock_funds_with_proof(
        uint256[] calldata proofParams,
        uint256[] calldata proof,
        address user,
        uint256 amount,
        uint256 l2TxId,
        bytes32 commitmentHash
    ) external {
        require(approvedRelayers[msg.sender], "ZeroXBridge: Only approved relayers can submit proofs");

        // Verify that commitmentHash matches expected format based on L2 standards
        bytes32 expectedCommitmentHash =
            keccak256(abi.encodePacked(uint256(uint160(user)), amount, l2TxId, block.chainid));

        require(commitmentHash == expectedCommitmentHash, "ZeroXBridge: Invalid commitment hash");

        // Create the public inputs array with all verification parameters
        uint256[] memory publicInputs = new uint256[](4);
        publicInputs[0] = uint256(uint160(user));
        publicInputs[1] = amount;
        publicInputs[2] = l2TxId;
        publicInputs[3] = uint256(commitmentHash);

        // Check that this proof hasn't been used before
        bytes32 proofHash = keccak256(abi.encodePacked(proof));
        require(!verifiedProofs[proofHash], "ZeroXBridge: Proof has already been used");

        // Verify the proof using Starknet's verifier
        bool isValid = gpsVerifier.verifyProofAndRegister(proofParams, proof, publicInputs, cairoVerifierId);

        require(isValid, "ZeroXBridge: Invalid proof");

        require(!verifiedProofs[commitmentHash], "ZeroXBridge: Commitment already processed");
        verifiedProofs[commitmentHash] = true;

        // Store the proof hash to prevent replay attacks
        verifiedProofs[proofHash] = true;

        claimableFunds[user] += amount;

        emit FundsUnlocked(user, amount, commitmentHash);
    }

    /**
     * @dev Allows users to claim their unlocked funds
     */
    function claimFunds() external {
        uint256 amount = claimableFunds[msg.sender];
        require(amount > 0, "ZeroXBridge: No funds to claim");

        // Reset claimable amount before transfer to prevent reentrancy
        claimableFunds[msg.sender] = 0;

        // Transfer funds to user
        token.safeTransfer(msg.sender, amount);
        emit FundsClaimed(msg.sender, amount);
    }

    // Function to update the GPS verifier address if needed
    function updateGpsVerifier(address _newVerifier) external onlyOwner {
        require(_newVerifier != address(0), "ZeroXBridge: Invalid address");
        gpsVerifier = IGpsStatementVerifier(_newVerifier);
    }

    // Function to update the Cairo verifier ID if needed
    function updateCairoVerifierId(uint256 _newVerifierId) external onlyOwner {
        cairoVerifierId = _newVerifierId;
    }
}
