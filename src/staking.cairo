// SPDX-License-Identifier: MIT
use starknet::ContractAddress;

// In order to make contract calls within our Vault,
// we need to have the interface of the remote ERC20 contract (starkbull) defined to import the Dispatcher.

#[starknet::interface]
pub trait IStakingRewards<TContractState> {
    fn stake(ref self: TContractState, amount: u256);
    fn unstake(ref self: TContractState, amount: u256);
    fn claim(ref self: TContractState) -> u256;
    fn update_rewards_index(ref self: TContractState, reward: u256);
    fn calculate_rewards_earned(ref self: TContractState, account: ContractAddress) -> u256;
    fn staking_Token(self: @TContractState) -> ContractAddress;
    fn rewards_Token(self: @TContractState) -> ContractAddress;
    fn total_Staked(self: @TContractState) -> u256;
}

#[starknet::contract]
// this contract does not have any guarantee to work, this is a solidityByExample implementation in ClaimedDrop
// I did not audit nor write tests for this contract.
// Use at your own risks
pub mod StakingRewards {
    use core::starknet::event::EventEmitter;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use core::num::traits::Zero;
    use openzeppelin::token::erc20::interface::{ ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    const MULTIPLIER: u256 = 1000000000000000000;
    
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
      Staked: Staked,
      Unstaked: Unstaked,
      Claim: Claimed,
    }

    #[derive(Drop, starknet::Event)]
    struct Staked {
      amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Unstaked {
      amount: u256
    }
    
    #[derive(Drop, starknet::Event)]
    struct Claimed {
      reward: u256
    }

    #[storage]
    struct Storage {
        stakingToken: ERC20ABIDispatcher, 
        rewardsToken: ERC20ABIDispatcher,
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
    fn constructor(ref self: ContractState, _owner: ContractAddress, _staking_token: ContractAddress) {
        self.owner.write(_owner);
        self.stakingToken.write(ERC20ABIDispatcher { contract_address: _staking_token });
        self.rewardsToken.write(ERC20ABIDispatcher { contract_address: _staking_token });
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
    impl SimpleRewardsImpl of super::IStakingRewards<ContractState> {
       fn stake(ref self: ContractState, amount: u256) {
         let caller = get_caller_address();
         let this = get_contract_address();
         PrivateFunctions::_update_rewards(ref self, caller);
         assert(amount > 0, 'cannot stake 0 token');
         self.stakingToken.read().transfer_from(caller, this, amount);
         self.balanceOf.write(caller, self.balanceOf.read(caller) + amount);
         self.totalSupply.write(self.totalSupply.read() + amount);
         self.emit(Staked{amount});
       }

       fn unstake(ref self: ContractState, amount: u256) {
         let caller = get_caller_address();
         PrivateFunctions::_update_rewards(ref self, caller);
         assert(amount > 0, 'amount is 0');
         assert(self.balanceOf.read(caller) - amount >=0, 'not enough funds');
         self.balanceOf.write(caller, self.balanceOf.read(caller) - amount);
         self.totalSupply.write(self.totalSupply.read() - amount);
         self.stakingToken.read().transfer(caller, amount);
         self.emit(Unstaked{amount});
       }

       fn claim(ref self: ContractState) -> u256 {
         let caller = get_caller_address();
         PrivateFunctions::_update_rewards(ref self, caller);
         let reward: u256 = self.earned.read(caller);
         if(reward >0) {
            self.earned.write(caller, 0);
            self.rewardsToken.read().transfer(caller, reward);
         }
         self.emit(Claimed{reward});
         return reward;
       }

       fn staking_Token(self: @ContractState) -> ContractAddress {
        return (self.stakingToken.read().contract_address);
       }

       fn rewards_Token(self: @ContractState) -> ContractAddress {
        return (self.rewardsToken.read().contract_address);
       }

       fn total_Staked(self: @ContractState) -> u256 {
        return (self.totalSupply.read());
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