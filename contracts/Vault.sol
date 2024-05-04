// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title  Vault
 * @author Rekt/KurgerBing69/FrankFourier
 */

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./dependencies/Ownable.sol";

contract Vault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Constants core parameters$
    /// @notice Assumption: 1 block every 12 seconds
    uint public constant BLOCKS_PER_DAY = 7_200;
    /// @notice Lock period of 1 year worth of blocks
    //uint public constant LOCK_PERIOD = BLOCKS_PER_DAY * 365; //uncomment for mainnet
    uint public constant LOCK_PERIOD = 50; //for testing
    /// @notice Minimum tokens required for locking
    uint public constant MIN_LOCK_AMOUNT = 10_000 * 10 ** 18;
    /// @notice Max number of users who can lock tokens
    uint public constant MAX_ACTIVE_USERS = 1_000;
    /// @notice Deposit fee percentage
    uint public constant DEPOSIT_FEE_PERCENT = 1;

    /// @dev Maps and state variables
    /// @notice Fee beneficiary
    address public feeBeneficiary;
    /// @notice Number of active users
    uint public usersCounter;
    /// @notice Locked tokens
    uint public totalLockedTokens;
    /// @notice Active users array
    address[MAX_ACTIVE_USERS] public activeUsers;
    /// @notice Array to store reward token addresses
    address[] public rewardTokenAddresses;

    /// @notice Stores user token lock details
    struct UserLock {
        uint256 lockedTokens; ///< Amount of tokens locked
        uint256 lockStartBlock; ///< Start time when tokens were locked
        uint256 lockEndBlock; ///< End time when tokens will be unlocked
    }

    /// @notice Struct to store reward token details
    struct RewardToken {
        address tokenAddress;
        uint256 availableRewards;
        uint256 minRewardThreshold;
    }

    /// @notice Mapping of user addresses to their respective lock information
    mapping(address => UserLock) public userLockInfo;
    /// @notice Mapping with authorized users
    mapping(address => bool) public authorized;
    /// @notice Mapping to store reward token details
    mapping(address => RewardToken) public rewardTokens;

    /// @notice Erc20 token to lock in the Vault
    IERC20 public immutable vaultToken;

    ////////////////// EVENTS //////////////////

    /// @notice Event emitted when user deposit fund to our vault
    event TokensLocked(address indexed user, uint amount, uint lockEndBlock);

    /// @notice Event emitted when user extends lock period or add amount
    event LockExtended(
        address indexed user,
        uint256 amountAdded,
        uint256 newLockEndBlock
    );

    /// @notice Event emitted when user claim their locked tokens
    event TokensUnlocked(address indexed user, uint amount);

    /// @notice Event emitted when admin distribute rewards to user
    event RewardsDistributed(
        address indexed user,
        address indexed token,
        uint amount
    );

    /// @notice Event emitted when rewards are deposited to the vault contract
    event RewardsFunded(address indexed token, uint amount);

    /// @notice Event emitted emergency unlock is triggered
    event EmergencyUnlockTriggered(address indexed user, uint amount);

    /// @notice Event emitted when admin withdraws ERC20 sent by mistake to the contract
    event ERC20Withdrawn(address indexed token, uint amount);

    ////////////////// MODIFIER //////////////////

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "ERR_V.1");
        _;
    }

    ////////////////// CONSTRUCTOR /////////////////////

    constructor(address _owner, address _vaultToken, address _feeBeneficiary) {
        require(_owner != address(0), "Invalid owner address");
        require(_vaultToken != address(0), "Invalid ERC20 address");
        require(
            _feeBeneficiary != address(0),
            "Invalid fee beneficiary address"
        );

        transferOwnership(_owner); // Set owner
        vaultToken = IERC20(_vaultToken); // Associate ERC20 token
        authorized[_owner] = true; // Grant authorization to owner
        feeBeneficiary = _feeBeneficiary; // Set fee beneficiary
        rewardTokens[_vaultToken] = RewardToken({
            tokenAddress: _vaultToken,
            availableRewards: 0,
            minRewardThreshold: 1 * 10 ** 18
        }); // Add vault token as the first reward token
        rewardTokenAddresses.push(_vaultToken);
    }

    ////////////////// SETTER //////////////////

    /// @notice Sets new beneficiary address
    /// @param _newBeneficiary New beneficiary address
    function setFeeBeneficiary(address _newBeneficiary) external onlyOwner {
        require(_newBeneficiary != address(0), "Invalid address");
        feeBeneficiary = _newBeneficiary;
    }

    /// @notice Add authorized user
    /// @param _user Address of the user
    function setAuthorizedUser(address _user, bool _state) external onlyOwner {
        require(_user != address(0), "Invalid address");
        authorized[_user] = _state;
    }

    /// @notice Function to add a reward token
    /// @param _tokenAddress Address of the reward token
    /// @param _minRewardThreshold Distribution rate of the reward token
    function setRewardToken(
        address _tokenAddress,
        uint256 _minRewardThreshold
    ) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(
            rewardTokens[_tokenAddress].tokenAddress == address(0),
            "Token already added"
        );

        rewardTokens[_tokenAddress] = RewardToken({
            tokenAddress: _tokenAddress,
            availableRewards: 0,
            minRewardThreshold: _minRewardThreshold
        });
        rewardTokenAddresses.push(_tokenAddress);
    }

    ////////////////// READ //////////////////

    function name() external view virtual returns (string memory) {
        return "VeGMBase";
    }

    function decimals() external view virtual returns (uint8) {
        return 18;
    }

    function symbol() external view virtual returns (string memory) {
        return "VEGMB";
    }

    /**
     * @notice Get adjusted total Supply
     */
    function totalSupply() public view virtual returns (uint256) {
        return _getTotalAdjustedLockedTokens();
    }

    /**
     * @notice Get the current adjusted balance of locked tokens for a user
     * @param user The address of the user
     * @return The adjusted amount of locked tokens
     */
    function balanceOf(address user) public view returns (uint256) {
        return _getAdjustedLockedTokens(user, block.number);
    }

    /**
     * @notice Get the adjusted balance of locked tokens for a user at a specific block
     * @param user The address of the user
     * @param blockNumber The block number at which to evaluate the balance
     * @return The adjusted amount of locked tokens at the given block
     */
    function balanceOfAt(
        address user,
        uint256 blockNumber
    ) public view returns (uint256) {
        require(
            blockNumber <= block.number,
            "Query block number is in the future"
        );
        return _getAdjustedLockedTokens(user, blockNumber);
    }

    ////////////////// AUXILIARY //////////////////

    /**
     * @notice Internal function to calculate adjusted locked tokens based on a specific block number
     * @param user The address of the user
     * @param blockNumber The block number for which to calculate the balance
     * @return The adjusted locked tokens based on elapsed time
     */
    function _getAdjustedLockedTokens(
        address user,
        uint256 blockNumber
    ) internal view returns (uint256) {
        UserLock memory lock = userLockInfo[user];
        if (
            blockNumber > lock.lockEndBlock ||
            lock.lockedTokens == 0 ||
            blockNumber <= lock.lockStartBlock
        ) {
            return 0;
        } else {
            uint256 elapsed = blockNumber - lock.lockStartBlock;
            uint256 totalDuration = lock.lockEndBlock - lock.lockStartBlock;
            return (lock.lockedTokens * elapsed) / totalDuration;
        }
    }

    /**
     * @notice Calculate and return the total adjusted locked tokens for all users based on elapsed time
     * @return totalAdjustedLockedTokens The total number of adjusted locked tokens across all users
     */
    function _getTotalAdjustedLockedTokens()
        internal
        view
        returns (uint256 totalAdjustedLockedTokens)
    {
        uint256 currentBlock = block.number;
        totalAdjustedLockedTokens = 0;

        for (uint i = 0; i < usersCounter; i++) {
            totalAdjustedLockedTokens += _getAdjustedLockedTokens(
                activeUsers[i],
                currentBlock
            );
        }

        return totalAdjustedLockedTokens;
    }

    /**
     * @notice Internal function to remove an active user
     * @param user The address of the user to remove
     */
    function _removeActiveUser(address user) internal {
        for (uint i = 0; i < usersCounter; i++) {
            if (activeUsers[i] == user) {
                activeUsers[i] = activeUsers[usersCounter - 1];
                delete activeUsers[usersCounter - 1];
                usersCounter--;
                break;
            }
        }
    }

    ////////////////// MAIN //////////////////

    /// @notice Users Deposit tokens to our vault
    /**
     * @dev Anyone can call this function up to total number of users.
     *      Users must approve deposit token before calling this function.
     *      We mint represent token to users so that we can calculate each users weighted deposit amount.
     */
    /// @param _amount Token Amount to deposit
    function lockTokens(uint256 _amount) external nonReentrant {
        require(_amount >= MIN_LOCK_AMOUNT, "Amount below minimum requirement");
        require(usersCounter < MAX_ACTIVE_USERS, "Max users limit reached");
        require(
            vaultToken.balanceOf(msg.sender) >= _amount,
            "Insufficient ERC20 balance"
        );
        require(
            userLockInfo[msg.sender].lockedTokens == 0,
            "Tokens already locked"
        );
        require(
            vaultToken.allowance(msg.sender, address(this)) >= _amount,
            "Insufficient allowance"
        );

        uint256 feeAmount = (_amount * DEPOSIT_FEE_PERCENT) / 100; // Calculate the fee
        uint256 netAmount = _amount - feeAmount; // Calculate net amount after fee deduction

        // Transfer the fee and the net amount
        vaultToken.safeTransferFrom(msg.sender, feeBeneficiary, feeAmount);
        vaultToken.safeTransferFrom(msg.sender, address(this), netAmount);

        // Manage active users
        activeUsers[usersCounter] = msg.sender;
        usersCounter++;

        userLockInfo[msg.sender] = UserLock(
            netAmount,
            block.number,
            block.number + LOCK_PERIOD
        );
        totalLockedTokens += netAmount;

        emit TokensLocked(
            msg.sender,
            netAmount,
            userLockInfo[msg.sender].lockEndBlock
        );
    }

    /// @notice Allows users to extend their lock period and add more tokens to the lock
    /// @param _additionalAmount The additional amount of tokens to lock
    function extendLock(uint256 _additionalAmount) external nonReentrant {
        UserLock storage lock = userLockInfo[msg.sender];

        require(block.number < lock.lockEndBlock, "Lock has already ended");
        require(lock.lockedTokens > 0, "No active lock found");

        if (_additionalAmount > 0) {
            require(
                vaultToken.balanceOf(msg.sender) >= _additionalAmount,
                "Insufficient ERC20 balance"
            );
            require(
                vaultToken.allowance(msg.sender, address(this)) >=
                    _additionalAmount,
                "Insufficient allowance"
            );

            uint256 feeAmount = (_additionalAmount * DEPOSIT_FEE_PERCENT) / 100;
            uint256 netAmount = _additionalAmount - feeAmount;

            vaultToken.safeTransferFrom(msg.sender, feeBeneficiary, feeAmount);
            vaultToken.safeTransferFrom(msg.sender, address(this), netAmount);

            // Increase locked tokens amount
            lock.lockedTokens += netAmount;
            totalLockedTokens += netAmount;
        }

        lock.lockEndBlock += LOCK_PERIOD;

        emit LockExtended(msg.sender, _additionalAmount, lock.lockEndBlock);
    }

    /// @notice Function to distribute rewards to users
    /// @param token Address of the token to distribute
    function distributeRewards(
        address token
    ) external nonReentrant onlyAuthorized {
        RewardToken storage rewardToken = rewardTokens[token];
        require(
            rewardToken.availableRewards > 0,
            "No rewards available to distribute"
        );

        uint256 totalVeTokens = totalSupply();

        require(totalVeTokens > 0, "No veTokens to distribute rewards to");
        require(
            rewardToken.availableRewards > 0,
            "No rewards available to distribute"
        );
        require(
            IERC20(token).balanceOf(address(this)) >=
                rewardToken.availableRewards,
            "Insufficient rewards available"
        );

        uint256 rewardsBalance = rewardToken.availableRewards;
        rewardToken.availableRewards = 0;

        // Distribute proportionally
        for (uint256 i = 0; i < usersCounter; i++) {
            address user = activeUsers[i];
            uint256 balance = balanceOf(user);
            if (balance > 0) {
                uint256 userShare = (balance * rewardsBalance) / totalVeTokens;
                if (userShare >= rewardToken.minRewardThreshold) {
                    IERC20(token).safeTransfer(user, userShare);
                    emit RewardsDistributed(user, token, userShare);
                }
            }
        }
    }

    /// @notice Function to fund rewards
    /// @param token Address of the token
    /// @param amount Amount of tokens to fund
    function fundRewards(
        address token,
        uint256 amount
    ) external nonReentrant onlyOwner {
        require(
            rewardTokens[token].tokenAddress != address(0),
            "Token not added as a reward token"
        );
        require(
            IERC20(token).allowance(msg.sender, address(this)) >= amount,
            "Check the token allowance. Approval required."
        );

        // Transfer the funds from the owner to the contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Update total available rewards for the specified token
        rewardTokens[token].availableRewards += amount;

        emit RewardsFunded(token, amount);
    }

    /// @notice Emergency unlock function to unlock tokens
    /// @param user Address of the user
    function emergencyUnlock(address user) external nonReentrant onlyOwner {
        require(
            block.number >
                userLockInfo[user].lockEndBlock + 30 * BLOCKS_PER_DAY,
            "Emergency unlock time restriction not met"
        );

        uint256 amount = userLockInfo[user].lockedTokens;
        delete userLockInfo[user];
        totalLockedTokens -= amount;
        _removeActiveUser(user);

        vaultToken.safeTransfer(user, amount);
        emit EmergencyUnlockTriggered(user, amount);
    }

    /// @notice Claim unlocked tokens
    function claimTokens() external nonReentrant {
        require(
            block.number > userLockInfo[msg.sender].lockEndBlock,
            "Tokens are still locked"
        );
        require(
            userLockInfo[msg.sender].lockedTokens > 0,
            "No locked tokens to claim"
        );

        uint256 amount = userLockInfo[msg.sender].lockedTokens;
        delete userLockInfo[msg.sender];
        totalLockedTokens -= amount;
        _removeActiveUser(msg.sender);

        vaultToken.safeTransfer(msg.sender, amount);
        emit TokensUnlocked(msg.sender, amount);
    }

    /// @notice Withdraw ERC-20 Token to the owner
    /// @param _tokenContract ERC-20 Token address
    function withdrawERC20(
        address _tokenContract
    ) external nonReentrant onlyOwner {
        require(
            _tokenContract != address(vaultToken),
            "Cannot withdraw the vaultToken"
        );

        uint256 balance = IERC20(_tokenContract).balanceOf(address(this));
        uint256 rewardBalance = rewardTokens[_tokenContract].availableRewards;

        if (rewardBalance > 0) {
            // Ensure the requested amount to withdraw is the remaining excess
            require(balance > rewardBalance, "Cannot withdraw rewards");

            // Withdraw only the excess amount
            IERC20(_tokenContract).safeTransfer(
                msg.sender,
                balance - rewardBalance
            );
        } else {
            // Withdraw the entire balance if it's not a reward token
            IERC20(_tokenContract).safeTransfer(msg.sender, balance);
        }

        emit ERC20Withdrawn(_tokenContract, balance);
    }
}
