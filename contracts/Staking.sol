// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


abstract contract Staking is ERC20 {

	using SafeERC20 for IERC20;

	struct Pool {
		bool exists;
		uint16 reward_share10000;
		uint last_total_reward; // global reward
	//	uint total_pool_reward;
		uint total_pool_reward_per_token;
		uint total_staked_in_pool;
	}
	mapping(address => Pool) public pools; // pool address => share of interest income

	struct PoolInfo {
		Pool pool;
		address pool_address;
	}

	address[] public pool_addresses; // list of all pools that had ever received rewards

	struct Stake {
		uint amount;
	//	uint last_total_pool_reward;
		uint last_total_pool_reward_per_token;
		uint reward;
	}
	mapping(address => mapping(address => Stake)) public stakes; // keyed by pool address and user address

	struct UserPool {
		address pool_address;
		uint16 reward_share10000;
		uint stake;
		uint reward;
	}

	event Staked(address indexed pool_address, address indexed user_address, uint amount, uint total_staked_in_pool);
	event Unstaked(address indexed pool_address, address indexed user_address, uint amount, uint total_staked_in_pool);
	event Claimed(address indexed pool_address, address indexed user_address, uint amount);
	

	// must only grow
	function updateAndGetTotalReward() public virtual returns (uint);
	function getTotalReward() public view virtual returns (uint);

	function setPoolShare(address pool_address, uint16 reward_share10000) internal {
		Pool storage pool = pools[pool_address];
		if (pool.last_total_reward == 0){ // new one
			require(IERC20(pool_address).totalSupply() > 0, "bad pool"); // check that it is ERC20 (or looks so)
			if (!pool.exists){
				require(reward_share10000 > 0, "0 reward");
				pool_addresses.push(pool_address);
			}
			pool.last_total_reward = updateAndGetTotalReward();
			pool.exists = true;
		}
		else
			updatePoolReward(pool_address);
		pool.reward_share10000 = reward_share10000; // can be 0
	}

	function updatePoolReward(address pool_address) public {
		Pool storage pool = pools[pool_address];
		require(pool.exists, "no such pool");
		uint total_reward = updateAndGetTotalReward();
	//	pool.total_pool_reward += (total_reward - pool.last_total_reward) * pool.reward_share10000/10000;
		if (pool.total_staked_in_pool > 0)
			pool.total_pool_reward_per_token += 1e18 * (total_reward - pool.last_total_reward) * pool.reward_share10000/10000 / pool.total_staked_in_pool;
		pool.last_total_reward = total_reward;
	}

	function updateUserReward(address pool_address, address user_address) public {
		Pool storage pool = pools[pool_address];
		Stake storage s = stakes[pool_address][user_address];
	//	s.reward += (pool.total_pool_reward - s.last_total_pool_reward) * s.amount/pool.total_staked_in_pool;
	//	s.last_total_pool_reward = pool.total_pool_reward;
		s.reward += (pool.total_pool_reward_per_token - s.last_total_pool_reward_per_token) * s.amount / 1e18;
		s.last_total_pool_reward_per_token = pool.total_pool_reward_per_token;
	}

	function updatePoolAndUserRewards(address pool_address, address user_address) public {
		updatePoolReward(pool_address);
		updateUserReward(pool_address, user_address);
	}

	// bulk update
	function updatePoolAndMultipleUsersRewards(address pool_address, address[] calldata user_addresses) external {
		updatePoolReward(pool_address);
		for (uint i = 0; i < user_addresses.length; i++)
			updateUserReward(pool_address, user_addresses[i]);
	}

	function getAllPools() external view returns (PoolInfo[] memory all_pools){
		all_pools = new PoolInfo[](pool_addresses.length);
		uint total_reward = getTotalReward();
		for (uint i=0; i<pool_addresses.length; i++){
			address pool_address = pool_addresses[i];
			Pool memory pool = pools[pool_address];
			if (pool.total_staked_in_pool > 0)
				pool.total_pool_reward_per_token += 1e18 * (total_reward - pool.last_total_reward) * pool.reward_share10000/10000 / pool.total_staked_in_pool;
			all_pools[i] = PoolInfo({pool: pool, pool_address: pool_address});
		}
	}

	function getUserPools(address user_address) external view returns (UserPool[] memory user_pools){
		user_pools = new UserPool[](pool_addresses.length);
		uint total_reward = getTotalReward();
		for (uint i=0; i<pool_addresses.length; i++){
			address pool_address = pool_addresses[i];
			Pool memory pool = pools[pool_address];
			if (pool.total_staked_in_pool > 0)
				pool.total_pool_reward_per_token += 1e18 * (total_reward - pool.last_total_reward) * pool.reward_share10000/10000 / pool.total_staked_in_pool;
			Stake memory s = stakes[pool_address][user_address];
			s.reward += (pool.total_pool_reward_per_token - s.last_total_pool_reward_per_token) * s.amount / 1e18;
			user_pools[i] = UserPool({
				pool_address: pool_address,
				reward_share10000: pool.reward_share10000,
				stake: s.amount,
				reward: s.reward
			});
		}
	}

	function stake(address pool_address, uint amount) external {
		Pool storage pool = pools[pool_address];
		require(pool.reward_share10000 > 0, "this pool is not receiving rewards");
		IERC20(pool_address).safeTransferFrom(msg.sender, address(this), amount);
		updatePoolAndUserRewards(pool_address, msg.sender);
		Stake storage s = stakes[pool_address][msg.sender];
		s.amount += amount;
		pool.total_staked_in_pool += amount;
		emit Staked(pool_address, msg.sender, amount, pool.total_staked_in_pool);
	}

	function unstake(address pool_address, uint amount) public {
		Pool storage pool = pools[pool_address];
		updatePoolAndUserRewards(pool_address, msg.sender);
		Stake storage s = stakes[pool_address][msg.sender];
		if (amount == 0)
			amount = s.amount;
		require(amount <= s.amount, "exceeds balance");
		s.amount -= amount;
		pool.total_staked_in_pool -= amount;
		IERC20(pool_address).safeTransfer(msg.sender, amount);
		emit Unstaked(pool_address, msg.sender, amount, pool.total_staked_in_pool);
	}

	function _claim(address pool_address) internal {
		Stake storage s = stakes[pool_address][msg.sender];
		require(s.reward > 0, "no reward here");
		_mint(msg.sender, s.reward);
		emit Claimed(pool_address, msg.sender, s.reward);
		s.reward = 0;
	}

	function claim(address pool_address) external {
		updatePoolAndUserRewards(pool_address, msg.sender);
		_claim(pool_address);
	}

	function unstakeAndClaim(address pool_address, uint amount) external {
		unstake(pool_address, amount);
		_claim(pool_address);
	}

}
