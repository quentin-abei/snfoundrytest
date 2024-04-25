// SPDX-License-Identifier: MIT
use starknet::ContractAddress;

// In order to make contract calls within our Vault,
// we need to have the interface of the remote ERC20 contract (starkbull) defined to import the Dispatcher.
#[starknet::interface]
pub trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
pub trait ISimpleVault<TContractState> {
    fn stake(ref self: TContractState, amount: u256);
    fn unstake(ref self: TContractState, amount: u256);
    fn claim(ref self: TContractState) -> u256;
    fn update_rewards_index(ref self: TContractState, reward: u256);
    fn calculate_rewards_earned(ref self: TContractState, account: ContractAddress) -> u256;
}

#[starknet::contract]

pub mod SimpleRewards {
/// @notice Permissionless staking contract for a single rewards program.
/// From the start of the program, to the end of the program, a fixed amount of rewards tokens will be distributed among stakers.
/// The rate at which rewards are distributed is constant over time, but proportional to the amount of tokens staked by each staker.
/// The contract expects to have received enough rewards tokens by the time they are claimable. The rewards tokens can only be recovered by claiming stakers.
/// This is a rewriting in cairo of [Unipool.sol](https://github.com/k06a/Unipool/blob/master/contracts/Unipool.sol), modified for clarity and simplified.
/// Careful if using non-standard ERC20 tokens, as they might break things.

    use core::traits::Into;
use core::option::OptionTrait;
use core::traits::TryInto;
use core::starknet::event::EventEmitter;
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use core::num::traits::Zero;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Staked: Staked,
        Unstaked: Unstaked,
        Claimed: Claimed,
        RewardsPerTokenUpdated: RewardsPerTokenUpdated,
        UserRewardsUpdated: UserRewardsUpdated,
    } 

    #[derive(Drop, starknet::Event)]
    struct Staked {
        #[key]
        user: ContractAddress ,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Unstaked {
        #[key]
        user: ContractAddress ,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Claimed {
        #[key]
        user: ContractAddress ,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct RewardsPerTokenUpdated {
        #[key]
        accumulated: u256
    }

    #[derive(Drop, starknet::Event)]
    struct UserRewardsUpdated {
        #[key]
        user: ContractAddress,
        rewards: u256,
        checkpoint: u256
    }

    #[derive(Drop, Copy, starknet::Store, Serde, PartialEq)]
    struct RewardsPerToken {
        accumulated: u256,
        lastUpdated: u256
    }

    #[derive(Drop, Copy, starknet::Store, Serde, PartialEq)]
    struct UserRewards {
        accumulated: u256,
        checkpoint: u256
    }

    #[storage]
    struct Storage {
        stakingToken: IERC20Dispatcher, 
        rewardsToken: IERC20Dispatcher,
        totalStaked: u256,
        userStake: LegacyMap<ContractAddress, u256>,
        accumulatedRewards: LegacyMap<ContractAddress, UserRewards>,
        rewardsRate: u256,
        rewardsStart: u256,
        rewardsEnd: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState,
                 _staking_token: ContractAddress,
                _rewards_token: ContractAddress,
                _rewardsStart: u256,
                _rewardsEnd: u256,
                totalRewards: u256
                )
         {
        self.stakingToken.write(IERC20Dispatcher { contract_address: _staking_token });
        self.rewardsToken.write(IERC20Dispatcher { contract_address: _rewards_token });
        self.rewardsStart.write(_rewardsStart);
        self.rewardsEnd.write(_rewardsEnd);
        // The contract will fail to deploy if end <= start, as it should
        self.rewardsRate.write(totalRewards/(_rewardsEnd - _rewardsStart));
        RewardsPerToken{accumulated:0, lastUpdated: _rewardsStart};
    }

    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
       fn _calculateRewardsPerToken(ref self: ContractState, rewardsPerTokenIn: RewardsPerToken) -> RewardsPerToken {
          let mut rewardsPerTokenOut: RewardsPerToken = RewardsPerToken{accumulated: rewardsPerTokenIn.accumulated, lastUpdated: rewardsPerTokenIn.lastUpdated};
          let totalStaked_: u256 = self.totalStaked.read();

          // No changes if the program hasn't started
          let timestamp_ = get_block_timestamp();
          if(timestamp_ < (self.rewardsStart.read().try_into().unwrap())) {
            return rewardsPerTokenOut;
          }

          // Stop accumulating at the end of the rewards interval
          let mut updateTime: u256 = 0;
          if(timestamp_ < self.rewardsEnd.read().try_into().unwrap()) {
            updateTime = timestamp_.into();
          } else {
            updateTime = self.rewardsEnd.read();
          }
          let mut elapsed: u256 = updateTime - rewardsPerTokenIn.lastUpdated;
       }
    }
}

