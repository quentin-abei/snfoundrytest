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
    fn currentRewardsPerToken(ref self: TContractState)-> u256;
    fn currentUserRewards(ref self: TContractState)-> u256;
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
        rewardsPerTokenMap: LegacyMap<u8, RewardsPerToken>,
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
          // No changes if no time has passed
          if(elapsed == 0) {
            return rewardsPerTokenOut;
          }
          rewardsPerTokenOut.lastUpdated = updateTime;

          // If there are no stakers we just change the last update time, the rewards for intervals without stakers are not accumulated
          if(totalStaked_ == 0) {
            return rewardsPerTokenOut;
          }
          // Calculate and update the new value of the accumulator.
          // The rewards per token are scaled up for precision
          rewardsPerTokenOut.accumulated = (rewardsPerTokenIn.accumulated + 1000000000000000000* elapsed * self.rewardsRate.read()/ totalStaked_);
          self.rewardsPerTokenMap.write(1, rewardsPerTokenOut);
          return rewardsPerTokenOut;
       }

       /// @notice Calculate the rewards accumulated by a stake between two checkpoints.
       fn _calculateUserRewards(ref self: ContractState, stake: u256, earlierCheckpoint: u256, laterCheckpoint: u256) -> u256 {
          // We must scale down the rewards by the precision factor
          return stake * (laterCheckpoint - earlierCheckpoint) / 1000000000000000000;
       }

       /// @notice Update and return the rewards per token accumulator according to the rate, the time elapsed since the last update, and the current total staked amount.
       fn _updateRewardsPerToken(ref self: ContractState) -> RewardsPerToken {
          let mut rewardsPerTokenIn_ : RewardsPerToken = self.rewardsPerTokenMap.read(1);
          let mut rewardsPerTokenOut_: RewardsPerToken = PrivateFunctions::_calculateRewardsPerToken(ref self, rewardsPerTokenIn_);
          // We skip the storage changes if already updated in the same block, or if the program has ended and was updated at the end
          if (rewardsPerTokenIn_.lastUpdated == rewardsPerTokenOut_.lastUpdated) {return rewardsPerTokenOut_;}

          RewardsPerToken{accumulated: rewardsPerTokenOut_.accumulated, lastUpdated: rewardsPerTokenOut_.lastUpdated};
          self.emit(RewardsPerTokenUpdated{accumulated: rewardsPerTokenOut_.accumulated});
          return rewardsPerTokenOut_;
       }

       /// @notice Calculate and store current rewards for an user. Checkpoint the rewardsPerToken value with the user.
       fn _updateUserRewards(ref self: ContractState, user: ContractAddress) -> UserRewards {
          let mut rewardsPerToken_: RewardsPerToken = PrivateFunctions::_updateRewardsPerToken(ref self);
          let mut userRewards_: UserRewards = self.accumulatedRewards.read(user);

          // We skip the storage changes if already updated in the same block
          if (userRewards_.checkpoint == rewardsPerToken_.lastUpdated) {return userRewards_;}
          // Calculate and update the new value user reserves.
          userRewards_.accumulated = userRewards_.accumulated + PrivateFunctions::_calculateUserRewards(ref self, self.userStake.read(user),userRewards_.checkpoint, rewardsPerToken_.accumulated );
          userRewards_.checkpoint = rewardsPerToken_.accumulated;
          self.accumulatedRewards.write(user, userRewards_);
          self.emit(UserRewardsUpdated{user: user, rewards: userRewards_.accumulated, checkpoint: userRewards_.checkpoint});
          return userRewards_;
       }

       /// @notice Stake tokens.
       fn _stake(ref self: ContractState, user: ContractAddress, amount: u256) {
          let caller = get_caller_address();
          let this = get_contract_address();
          PrivateFunctions::_updateUserRewards(ref self, user);
          self.stakingToken.read().transfer_from(caller, this, amount);
          self.totalStaked.write(self.totalStaked.read() + amount);
          self.userStake.write(user, self.userStake.read(user) + amount);
          self.emit(Staked{user: user, amount: amount});
       }

       /// @notice Unstake tokens.
       fn _unstake(ref self: ContractState, user: ContractAddress, amount: u256) {
          let caller = get_caller_address();
          PrivateFunctions::_updateUserRewards(ref self, user);
          self.totalStaked.write(self.totalStaked.read() - amount);
          self.userStake.write(user, self.userStake.read(user) - amount);
          self.stakingToken.read().transfer(caller, amount);
          self.emit(Unstaked{user: user, amount: amount});
       }

       /// @notice Claim rewards.
       fn _claim(ref self: ContractState, user: ContractAddress, amount: u256) {
          let caller = get_caller_address();
          let rewardsAvailable: u256 = PrivateFunctions::_updateUserRewards(ref self, caller).accumulated;

          let mut userRewards_: UserRewards = self.accumulatedRewards.read(user);
          // This line would panic if the user doesn't have enough rewards accumulated
          userRewards_.accumulated = rewardsAvailable - amount;
          self.accumulatedRewards.write(user, userRewards_);
          // This line would panic if the contract doesn't have enough rewards tokens
          self.rewardsToken.read().transfer(caller, amount);
          self.emit(Claimed{user: user, amount: amount});
       }
    }

    #[abi(embed_v0)]
    impl SimpleVault of super::ISimpleVault<ContractState> {
        /// @notice Stake tokens.
        fn stake(ref self: ContractState, amount: u256)
         {
            let caller = get_caller_address();
            PrivateFunctions::_stake(ref self, caller, amount);
         }
         
         
         fn unstake(ref self: ContractState, amount: u256)
         {
            let caller = get_caller_address();
            PrivateFunctions::_unstake(ref self, caller, amount);
         }

         fn claim(ref self: ContractState) -> u256
         {
            let caller = get_caller_address();
            let claimed: u256 = PrivateFunctions::_updateUserRewards(ref self, caller).accumulated; 
            PrivateFunctions::_claim(ref self, caller, claimed);
            return claimed;
         }

         /// @notice Calculate and return current rewards per token.
        fn currentRewardsPerToken(ref self: ContractState)-> u256 {
           let mut rewardsPerTokenIn_ : RewardsPerToken = self.rewardsPerTokenMap.read(1);
           return PrivateFunctions::_calculateRewardsPerToken(ref self, rewardsPerTokenIn_).accumulated;
        }

        /// @notice Calculate and return current rewards for a user.
        /// @dev This repeats the logic used on transactions, but doesn't update the storage.
        fn currentUserRewards(ref self: ContractState)-> u256 {
            let caller = get_caller_address();
            let mut accumulatedRewards_: UserRewards = self.accumulatedRewards.read(caller);
            let mut rewardsPerTokenIn_ : RewardsPerToken = self.rewardsPerTokenMap.read(1);
            let mut rewardsPerToken_: RewardsPerToken = PrivateFunctions::_calculateRewardsPerToken(ref self, rewardsPerTokenIn_);
            return accumulatedRewards_.accumulated + PrivateFunctions::_calculateUserRewards(ref self, self.userStake.read(caller), accumulatedRewards_.checkpoint, rewardsPerToken_.accumulated);
        }
    }
}

