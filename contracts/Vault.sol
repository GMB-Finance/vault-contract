// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title  Vault
 * @author Rekt/xciteddelirium/FrankFourier
 *    ____ ____________ ____ 
 *    / ____||  \\/  ||  _ \
 *   | |  __ | \\  / || |_) |\
 *   | | |_ || |\\/| ||  _ < \
 *   | |__| || |  | || |_) | |
 *    \\_____||_|  |_||____/
 */

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./dependencies/Ownable.sol";

contract Vault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Constants core parameters$
    /// @notice Assumption: 1 block every 2 seconds adjusted to Base
    uint public constant BLOCKS_PER_DAY = 43_200;
    /// @notice Lock period of 3 months worth of blocks
    uint public constant LOCK_PERIOD = 3_888_000; // for 3 months
    /// @notice Minimum tokens required for locking
    uint public constant MIN_LOCK_AMOUNT = 1_000 * 10 ** 18;
    /// @notice Max number of users who can lock tokens
    uint public constant MAX_ACTIVE_USERS = 1_000;
    /// @notice Deposit fee percentage
    uint public constant DEPOSIT_FEE_PERCENT = 1;
    /// @dev Maps and state variables
    /// @notice Fee beneficiary
    address public feeBeneficiary;
    /// @notice Number of active users
    uint public usersCounter;
    /// @notice Number of reward distributions
    uint public distributionRounds;
    /// @notice Locked tokens
    uint public totalLockedTokens;
    /// @notice Total users per distribution round
    uint public totalUsersPerRound;
    /// @notice Active users array
    address[MAX_ACTIVE_USERS] public activeUsers;
    /// @notice Array to store reward token addresses
    address[] public rewardTokenAddresses;

    /// @notice Stores user token lock details
    struct UserLock {
        uint256 lockedTokens; ///< Amount of tokens locked
        uint256 virtualLockedTokens; ///< Virtual principal amount
        uint256 lockStartBlock; ///< Start time when tokens were locked
        uint256 lockEndBlock; ///< End time when tokens will be unlocked
    }

    /// @notice Struct to store reward token details
    struct RewardToken {
        address tokenAddress;
        uint availableRewards;
        uint minRewardThreshold;
    }

    /// @notice Struct to store reward token distributions
    struct RewardDistribution {
        address rewardToken;
        uint availableRewards;
        uint lastUserIndex;
        uint blockNumber;
        uint usersCountAtBlock;
        uint totalSupplyAtBlock;
    }

    /// @notice Mapping of user addresses to their respective lock information
    mapping(address => UserLock) public userLockInfo;
    /// @notice Mapping with authorized users
    mapping(address => bool) public authorized;
    /// @notice Mapping to store reward token details
    mapping(address => RewardToken) public rewardTokens;
    /// @notice Mapping to store reward token distributions
    mapping(uint => RewardDistribution) public rewardDistributions;

    /// @notice Erc20 token to lock in the Vault
    IERC20 public immutable vaultToken;

    ////////////////// EVENTS //////////////////

    /// @notice Event emitted when tokens are sent from an account to another
    event Transfer(address indexed from, address indexed to, uint256 value);
    /// @notice Event emitted when user deposit fund to our vault
    event TokensLocked(address indexed user, uint amount, uint lockEndBlock);

    /// @notice Event emitted when user extends lock period or add amount
    event LockExtended(
        address indexed user,
        uint amountAdded,
        uint newLockEndBlock
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
        require(
            _newBeneficiary != address(0) && _newBeneficiary != feeBeneficiary,
            "Invalid address"
        );
        feeBeneficiary = _newBeneficiary;
    }

    /// @notice Add authorized user
    /// @param _user Address of the user
    function setAuthorizedUser(address _user, bool _state) external onlyOwner {
        require(_user != address(0), "Invalid address");
        require(authorized[_user] != _state, "Invalid state");
        authorized[_user] = _state;
    }

    /// @notice Set the total number of users per distribution round
    /// @param _totalUsersPerRound Total number of users per distribution round
    function setTotalUsersPerRound(
        uint _totalUsersPerRound
    ) external onlyOwner {
        require(
            _totalUsersPerRound > 0 &&
                _totalUsersPerRound != totalUsersPerRound,
            "Invalid number of users"
        );
        totalUsersPerRound = _totalUsersPerRound;
    }

    /// @notice Function to add a reward token
    /// @param _tokenAddress Address of the reward token
    /// @param _minRewardThreshold Distribution rate of the reward token
    function setRewardToken(
        address _tokenAddress,
        uint _minRewardThreshold
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
        return "veGMBee";
    }

    function decimals() external view virtual returns (uint8) {
        return 18;
    }

    function symbol() external view virtual returns (string memory) {
        return "GMBee";
    }

    /**
     * @notice Get adjusted total Supply
     */
    function totalSupply() public view virtual returns (uint) {
        return _getTotalAdjustedLockedTokens();
    }

    /**
     * @notice Get the current adjusted balance of locked tokens for a user
     * @param user The address of the user
     * @return The adjusted amount of locked tokens
     */
    function balanceOf(address user) public view returns (uint) {
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
        uint blockNumber
    ) public view returns (uint) {
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
            return (lock.virtualLockedTokens * elapsed) / totalDuration;
        }
    }

    /**
     * @notice Calculate and return the total adjusted locked tokens for all users based on elapsed time
     * @return totalAdjustedLockedTokens The total number of adjusted locked tokens across all users
     */
    function _getTotalAdjustedLockedTokens()
        internal
        view
        returns (uint totalAdjustedLockedTokens)
    {
        uint currentBlock = block.number;
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
    function lockTokens(uint _amount) external nonReentrant {
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

        uint feeAmount = (_amount * DEPOSIT_FEE_PERCENT) / 100; // Calculate the fee
        uint netAmount = _amount - feeAmount; // Calculate net amount after fee deduction

        // Transfer the fee and the net amount
        vaultToken.safeTransferFrom(msg.sender, feeBeneficiary, feeAmount);
        vaultToken.safeTransferFrom(msg.sender, address(this), netAmount);

        // Manage active users
        activeUsers[usersCounter] = msg.sender;
        usersCounter++;

        userLockInfo[msg.sender] = UserLock(
            netAmount,
            netAmount,
            block.number,
            block.number + LOCK_PERIOD
        );
        totalLockedTokens += netAmount;

        emit Transfer(address(0), msg.sender, 0);
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
            // If additional amount is greater than 0 it is intended as a new lock, history will be lost.
            require(
                _additionalAmount >= MIN_LOCK_AMOUNT,
                "Amount below minimum requirement"
            );
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
            totalLockedTokens += netAmount;
            lock.lockedTokens += netAmount;
            lock.virtualLockedTokens = lock.lockedTokens;
            lock.lockStartBlock = block.number;
            lock.lockEndBlock = block.number + LOCK_PERIOD;

            emit TokensLocked(
                msg.sender,
                netAmount,
                userLockInfo[msg.sender].lockEndBlock
            );
        } else {
            // calculate the new virtual principal
            uint elapsedTime = block.number - lock.lockStartBlock;
            uint totalDuration = lock.lockEndBlock - lock.lockStartBlock;
            uint virtualPrincipal = lock.lockedTokens + (lock.lockedTokens * elapsedTime) / totalDuration;

            lock.virtualLockedTokens = virtualPrincipal;
            lock.lockEndBlock = block.number + LOCK_PERIOD;

            emit LockExtended(msg.sender, _additionalAmount, lock.lockEndBlock);
        }
    }

    /// @notice Function to distribute rewards to users
    /// @param token Address of the token to distribute
    function distributeRewards(
        address token
    ) external nonReentrant onlyAuthorized {
        RewardToken storage rewardToken = rewardTokens[token];
        uint256 rewardsBalance = rewardToken.availableRewards;
        require(rewardsBalance > 0, "No rewards available to distribute");

        uint256 totalVeTokens = totalSupply();

        require(totalVeTokens > 0, "No veTokens to distribute rewards to");
        require(
            IERC20(token).balanceOf(address(this)) >= rewardsBalance,
            "Insufficient rewards available"
        );

        rewardToken.availableRewards = 0;

        uint loopLimit = totalUsersPerRound > 0 && totalUsersPerRound < usersCounter
            ? totalUsersPerRound
            : usersCounter;

        // Distribute proportionally
        for (uint i = 0; i < loopLimit; i++) {
            address user = activeUsers[i];
            uint balance = balanceOf(user);
            if (balance > 0) {
                uint userShare = (balance * rewardsBalance) / totalVeTokens;
                if (userShare >= rewardToken.minRewardThreshold) {
                    IERC20(token).safeTransfer(user, userShare);
                    emit RewardsDistributed(user, token, userShare);
                }
            }
        }

        rewardDistributions[distributionRounds] = RewardDistribution({
            rewardToken: rewardToken.tokenAddress,
            availableRewards: rewardsBalance,
            lastUserIndex: loopLimit,
            blockNumber: block.number,
            usersCountAtBlock: usersCounter,
            totalSupplyAtBlock: totalVeTokens
        });

        distributionRounds++;
    }

    /// @notice Function to continue reward distribution
    /// @param distributionRound Index of the round to complete
    function continueDistributingRewards(
        uint distributionRound
    ) external nonReentrant onlyOwner {
        RewardDistribution storage distributionInfo = rewardDistributions[
            distributionRound
        ];
        RewardToken memory rewardToken = rewardTokens[
            distributionInfo.rewardToken
        ];

        require(
            distributionInfo.lastUserIndex < distributionInfo.usersCountAtBlock,
            "Tokens for this round have already been distributed!"
        );

        uint loopLimit = totalUsersPerRound > 0 && totalUsersPerRound < distributionInfo.usersCountAtBlock - distributionInfo.lastUserIndex
            ? totalUsersPerRound
            : distributionInfo.usersCountAtBlock -
                distributionInfo.lastUserIndex;

        // Distribute proportionally
        for (uint i = distributionInfo.lastUserIndex; i < loopLimit; i++) {
            address user = activeUsers[i];
            uint balance = balanceOfAt(user, distributionInfo.blockNumber);
            if (balance > 0) {
                uint userShare = (balance * distributionInfo.availableRewards) /
                    distributionInfo.totalSupplyAtBlock;
                if (userShare >= rewardToken.minRewardThreshold) {
                    IERC20(rewardToken.tokenAddress).safeTransfer(
                        user,
                        userShare
                    );
                    emit RewardsDistributed(
                        user,
                        rewardToken.tokenAddress,
                        userShare
                    );
                }
            }
        }

        // update just what was changed
        distributionInfo.lastUserIndex = loopLimit;
    }

    /// @notice Function to fund rewards
    /// @param token Address of the token
    /// @param amount Amount of tokens to fund
    function fundRewards(
        address token,
        uint amount
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

        uint amount = userLockInfo[user].lockedTokens;
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

        uint amount = userLockInfo[msg.sender].lockedTokens;
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

        uint balance = IERC20(_tokenContract).balanceOf(address(this));
        uint rewardBalance = rewardTokens[_tokenContract].availableRewards;

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
