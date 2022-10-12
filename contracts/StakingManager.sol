//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SushiToken.sol";

// 'Ownable' so that, if in case you'd want to transfer ownership to DAO later on
contract StakingManager is Ownable{
    using SafeERC20 for IERC20; // Wrappers around ERC20 operations (inheriting f() from IERC20) that throw on failure

    SushiToken public sushiToken; // Token to be payed as reward

    uint256 private sushiTokensPerBlock; // Number of reward tokens minted per block
    uint256 private constant STAKER_SHARE_PRECISION = 1e12; // A big number to perform mul and div operations
    // as floating point numbers are not supported + here, we may end up getting figures in float while calc. stakerShare

    // Staking user for a pool = Staker of a Pool = UserInfo
    struct PoolStaker {
        uint256 amount; // The tokens quantity the user has staked.
        uint256 rewards; // The reward tokens quantity the user can harvest (not yet harvested, NOT unstaked)
        uint256 lastRewardedBlock; // Last block number the user had their rewards CALCULATED (not harvested, not unstaked tokens)
    }

    // Staking pool = PoolInfo
    struct Pool {
        IERC20 stakeToken; // Token to be staked
        uint256 tokensStaked; // Total tokens staked by all the Stakers in this pool...to calculate share per Staker
        address[] stakers; // Stakers in this pool
    }

    Pool[] public pools; // Staking pools

    // Mapping poolId => staker address => PoolStaker
    mapping(uint256 => mapping(address => PoolStaker)) public poolStakers;

    // Events
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount);
    event HarvestRewards(address indexed user, uint256 indexed poolId, uint256 amount);
    event PoolCreated(uint256 poolId);

    // Constructor
    constructor(address _sushiTokenAddress, uint256 _sushiTokensPerBlock) {
        sushiToken = SushiToken(_sushiTokenAddress);    // Sushi's created instance returned here
        sushiTokensPerBlock = _sushiTokensPerBlock;
    }

    /**
     * @dev Create a new staking pool
     */
    function createPool(IERC20 _stakeToken) external onlyOwner {
        Pool memory pool;               // 'storage' will be used if a mapping / array (above) is used to create a struct's instance
        // created a new Pool and popultaed members below
        pool.stakeToken =  _stakeToken; // at least: 'token to be staked' has to be listed and amount staked / staker can be zero for now
        pools.push(pool);
        uint256 poolId = pools.length - 1;
        emit PoolCreated(poolId);
    }

    /**
     * @dev Add staker address to the pool stakers if it's not there already
     * We don't have to remove it because if it has amount 0 it won't affect rewards.
     * (but it might save gas in the long run as removing everytime will change state, costing Gas)
     */
    function addStakerToPoolIfInexistent(uint256 _poolId, address depositingStaker) private {
        Pool storage pool = pools[_poolId];     // pools is Pool[] .. 'memory' will be used if no mapping / array (above) is used to create a struct's instance
        // retrieved Pool's members
        for (uint256 i; i < pool.stakers.length; i++) {         // stakers is address[]
            address existingStaker = pool.stakers[i];
            if (existingStaker == depositingStaker) return;     // empty 'return' to break off a loop
        }
        pool.stakers.push(msg.sender);
    }

    /**
     * @dev Deposit tokens to an existing pool
     */
     // actual transfer is effected, via safeTransferFrom()
     // Can also make 'payable' and transfer ether to stake
     
     // Increase size (tokensStaked)
    function deposit(uint256 _poolId, uint256 _amount) external {
        require(_amount > 0, "Deposit amount can't be zero");
        Pool storage pool = pools[_poolId];
        PoolStaker storage staker = poolStakers[_poolId][msg.sender];

        // Update pool stakers
        updateStakersRewards(_poolId);      // lastRewardBlock and rewards of all the Stakers get updated now w.r.t present block when deposit() happened by any Staker
        addStakerToPoolIfInexistent(_poolId, msg.sender);   //maybe he's a new staker

        // Update current staker
        staker.amount = staker.amount + _amount;    // if (new), 'staker.amount' will be zero for the first time else updtaed
        staker.lastRewardedBlock = block.number;    
        // needed for 'new' staker, redundant for older ones bcz already got updated above: updateStakersRewards(_poolId);

        // Update pool
        pool.tokensStaked = pool.tokensStaked + _amount;

        // Deposit tokens
        emit Deposit(msg.sender, _poolId, _amount);
        pool.stakeToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
    }

    /**
     * @dev Withdraw all tokens from an existing pool
     */
     // Decrease size (tokensStaked)
    function withdraw(uint256 _poolId) external {
        Pool storage pool = pools[_poolId];
        PoolStaker storage staker = poolStakers[_poolId][msg.sender];
        uint256 amount = staker.amount;
        require(amount > 0, "Withdraw amount can't be zero");

        // Update pool stakers
        updateStakersRewards(_poolId);      // 'lastRewardBlock' and 'rewards' of all the Stakers get updated now w.r.t present block when withdraw() happened by any Staker

        // Pay rewards
        harvestRewards(_poolId);

        // Update staker
        staker.amount = 0;

        // Update pool
        pool.tokensStaked = pool.tokensStaked - amount;

        // Withdraw tokens
        emit Withdraw(msg.sender, _poolId, amount);
        pool.stakeToken.safeTransfer(
            address(msg.sender),
            amount
        );
    }

    /**
     * @dev Harvest user rewards from a given pool id
     */
     // Same size (tokensStaked)
    function harvestRewards(uint256 _poolId) public {
        updateStakersRewards(_poolId);          // 'lastRewardBlock' and 'rewards' of all the Stakers get updated now w.r.t present block when harvestRewards() happened by any Staker
        PoolStaker storage staker = poolStakers[_poolId][msg.sender];
        uint256 rewardsToHarvest = staker.rewards;
        staker.rewards = 0;
        emit HarvestRewards(msg.sender, _poolId, rewardsToHarvest);
        sushiToken.mint(msg.sender, rewardsToHarvest);
    }

    /**
     * @dev Loops over all stakers from a pool, updating their accumulated rewards according
     * to their participation in the pool.
     */
     // loop all stakers => CheckedAmountInvestedInThePool of all => UpdateAccRewards of all
    function updateStakersRewards(uint256 _poolId) private {
        Pool storage pool = pools[_poolId];                 // retrieve the specific pool
        for (uint256 i; i < pool.stakers.length; i++) {
            address stakerAddress = pool.stakers[i];
            PoolStaker storage staker = poolStakers[_poolId][stakerAddress];            // retrieve 1-by-1 all stakers in this pool
            //if (staker.amount == 0) return;               // no reward acc... maybe he participated earlier and now has left, harvesting all rewards + UNstaked
            uint256 stakedAmount = staker.amount;
            uint256 stakerShare = (stakedAmount * STAKER_SHARE_PRECISION / pool.tokensStaked);  // FractionalShare*10^12
            uint256 blocksSinceLastReward = block.number - staker.lastRewardedBlock;            
            // whenever last either of the Deposit / Withdraw / HarvestReward happened by any staker..
            // then, updateStakewrRewards runs and lastRewardedBlock calculated.
            uint256 rewards = (blocksSinceLastReward * sushiTokensPerBlock * stakerShare) / STAKER_SHARE_PRECISION; //FractionalShare/10^12
            // rewards has to be updated when, say, some staker harvested its reward
            staker.lastRewardedBlock = block.number;        // re-calc. rewards in the present block and hence updated lastRewardedBlock
            staker.rewards = staker.rewards + rewards;      // rewards getting accumulated till harvested by this user
        }

    }
}