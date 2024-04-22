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
pub mod StakingRewards {
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use core::num::traits::Zero;
    const MULTIPLIER: u256 = 1000000000000000000;

    #[storage]
    struct Storage {
        stakingToken: IERC20Dispatcher, 
        rewardsToken: IERC20Dispatcher,
        // Total staked
        totalSupply: u256,
        // User address => staked amount
        balanceOf: LegacyMap<ContractAddress, u256>,
        rewardsIndex: u256,
        owner: ContractAddress,
        rewardsIndexOf: LegacyMap<ContractAddress, u256>,
        earned: LegacyMap<ContractAddress, u256>
    }

    #[constructor]
    fn constructor(ref self: ContractState, _owner: ContractAddress, _staking_token: ContractAddress, _rewards_token: ContractAddress) {
        self.owner.write(_owner);
        self.stakingToken.write(IERC20Dispatcher { contract_address: _staking_token });
        self.rewardsToken.write(IERC20Dispatcher { contract_address: _rewards_token });
    }

     #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
       fn _calculate_rewards(ref self: ContractState, account: ContractAddress) -> u256 {
          let shares: u256 = self.balanceOf.read(account);
          return (shares * (self.rewardsIndex.read() - self.rewardsIndexOf.read(account)))/ MULTIPLIER;
       }

       fn _update_rewards(ref self: ContractState, account: ContractAddress) {
          self.earned.write(account, self.earned.read(account) + PrivateFunctions::_calculate_rewards(ref self, account));
          self.rewardsIndexOf.write(account, self.rewardsIndex.read());
       }
    }

    #[abi(embed_v0)]
    impl SimpleVault of super::ISimpleVault<ContractState> {
       fn stake(ref self: ContractState, amount: u256) {
         let caller = get_caller_address();
         let this = get_contract_address();
         PrivateFunctions::_update_rewards(ref self, caller);
         assert(amount > 0, 'cannot stake 0 token');
         self.stakingToken.read().transfer_from(caller, this, amount);
         self.balanceOf.write(caller, self.balanceOf.read(caller) + amount);
         self.totalSupply.write(self.totalSupply.read() + amount);
       }

       fn unstake(ref self: ContractState, amount: u256) {
         let caller = get_caller_address();
         PrivateFunctions::_update_rewards(ref self, caller);
         assert(amount > 0, 'amount is 0');
         assert(self.balanceOf.read(caller) - amount >=0, 'not enough funds');
         self.balanceOf.write(caller, self.balanceOf.read(caller) - amount);
         self.totalSupply.write(self.totalSupply.read() - amount);
         self.stakingToken.read().transfer(caller, amount);
       }

       fn claim(ref self: ContractState) -> u256 {
         let caller = get_caller_address();
         PrivateFunctions::_update_rewards(ref self, caller);
         let reward: u256 = self.earned.read(caller);
         if(reward >0) {
            self.earned.write(caller, 0);
            self.rewardsToken.read().transfer(caller, reward);
         }
         return reward;
       }

       fn update_rewards_index(ref self: ContractState, reward: u256) {
         let caller = get_caller_address();
         let this = get_contract_address();
         self.rewardsToken.read().transfer_from(caller, this, reward);
         self.rewardsIndex.write(self.rewardsIndex.read() + ((reward * MULTIPLIER) / self.totalSupply.read()));
       }

       fn calculate_rewards_earned(ref self: ContractState, account: ContractAddress) -> u256 {
         return self.earned.read(account) + PrivateFunctions::_calculate_rewards(ref self, account);
       }
    }
}