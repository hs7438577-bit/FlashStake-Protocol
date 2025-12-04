// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title FlashStake Protocol
 * @notice A yield-upfront staking protocol. Users deposit tokens and instantly receive a reward
 *         based on staking duration. Liquidity providers supply reward funds and gain returns
 *         as users' stakes unlock over time.
 */

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from,address to,uint256 value) external returns (bool);
}

contract FlashStakeProtocol {

    IERC20 public stakingToken;
    IERC20 public rewardToken;
    address public owner;

    struct Stake {
        uint256 amount;
        uint256 start;
        uint256 duration;
        uint256 reward;
        bool withdrawn;
    }

    mapping(address => Stake[]) public stakes;
    uint256 public rewardRatePerSecond; // reward generated per token per second
    uint256 public liquidityPool;

    event Staked(address indexed user, uint256 amount, uint256 reward, uint256 duration);
    event Unstaked(address indexed user, uint256 stakeIndex, uint256 stakedAmount, uint256 penalty);
    event LiquidityAdded(address provider, uint256 amount);
    event LiquidityRemoved(address provider, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Restricted to owner");
        _;
    }

    constructor(IERC20 _stakeToken, IERC20 _rewardToken, uint256 _rewardRatePerSecond) {
        stakingToken = _stakeToken;
        rewardToken = _rewardToken;
        rewardRatePerSecond = _rewardRatePerSecond;
        owner = msg.sender;
    }

    /**
     * @notice Users stake tokens and instantly get reward upfront based on duration.
     */
    function flashStake(uint256 amount, uint256 duration) external {
        require(amount > 0, "Amount required");
        require(duration > 0, "Duration required");

        // Transfer staked tokens to protocol
        stakingToken.transferFrom(msg.sender, address(this), amount);

        // Calculate upfront reward
        uint256 reward = amount * rewardRatePerSecond * duration / 1e18;
        require(liquidityPool >= reward, "Insufficient reward reserve");

        // Payout reward instantly
        liquidityPool -= reward;
        rewardToken.transfer(msg.sender, reward);

        stakes[msg.sender].push(
            Stake({
                amount: amount,
                start: block.timestamp,
                duration: duration,
                reward: reward,
                withdrawn: false
            })
        );

        emit Staked(msg.sender, amount, reward, duration);
    }

    /**
     * @notice Users withdraw staked tokens after lock period, or early with penalty.
     */
    function unstake(uint256 index) external {
        require(index < stakes[msg.sender].length, "Invalid index");
        Stake storage userStake = stakes[msg.sender][index];
        require(!userStake.withdrawn, "Already withdrawn");

        uint256 stakedAmount = userStake.amount;
        uint256 penalty = 0;

        if (block.timestamp < userStake.start + userStake.duration) {
            // Early unstake penalty = 30% of principal
            penalty = (stakedAmount * 30) / 100;
            stakedAmount -= penalty;
            liquidityPool += penalty; // penalty goes to liquidity pool
        }

        userStake.withdrawn = true;
        stakingToken.transfer(msg.sender, stakedAmount);

        emit Unstaked(msg.sender, index, stakedAmount, penalty);
    }

    /**
     * @notice Liquidity providers add reward liquidity
     */
    function addLiquidity(uint256 amount) external {
        rewardToken.transferFrom(msg.sender, address(this), amount);
        liquidityPool += amount;
        emit LiquidityAdded(msg.sender, amount);
    }

    /**
     * @notice Owner removes reward liquidity if required
     */
    function removeLiquidity(uint256 amount) external onlyOwner {
        require(liquidityPool >= amount, "Not enough liquidity");
        liquidityPool -= amount;
        rewardToken.transfer(msg.sender, amount);
        emit LiquidityRemoved(msg.sender, amount);
    }

    /**
     * @notice Get all stakes of a user
     */
    function getUserStakes(address user) external view returns (Stake[] memory) {
        return stakes[user];
    }
}
