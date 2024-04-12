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
    fn deposit(ref self: TContractState, amount: u256);
    fn deposit_rewards(ref self: TContractState, amount: u256);
    fn withdraw(ref self: TContractState, shares: u256);
}

#[starknet::contract]
pub mod SimpleVault {
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    #[storage]
    struct Storage {
        token: IERC20Dispatcher, 
        total_supply: u256,
        total_deposit: u256,
        total_rewards: u256,
        user_rewards: LegacyMap<ContractAddress, u256>,
        rewards_depositoor: ContractAddress,
        user_deposit_balance: LegacyMap<ContractAddress, u256>,
        balance_of: LegacyMap<ContractAddress, u256>
    }

    #[constructor]
    fn constructor(ref self: ContractState, token: ContractAddress, depositoor: ContractAddress) {
        self.token.write(IERC20Dispatcher { contract_address: token });
        self.rewards_depositoor.write(depositoor);
    }

    #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
        fn _mint(ref self: ContractState, to: ContractAddress, shares: u256) {
            self.total_supply.write(self.total_supply.read() + shares);
            self.balance_of.write(to, self.balance_of.read(to) + shares);
        }

        fn _burn(ref self: ContractState, from: ContractAddress, shares: u256) {
            self.total_supply.write(self.total_supply.read() - shares);
            self.balance_of.write(from, self.balance_of.read(from) - shares);
        }
    }

    #[abi(embed_v0)]
    impl SimpleVault of super::ISimpleVault<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) {
            
            let caller = get_caller_address();
            let this = get_contract_address();

            self.token.read().transfer_from(caller, this, amount);

            self.user_deposit_balance.write(caller, self.user_deposit_balance.read(caller) + amount);
            self.total_deposit.write(self.total_deposit.read() + amount);

            let user_share = (amount * self.total_rewards.read())/self.total_deposit.read();
            self.user_rewards.write(caller, self.user_rewards.read(caller) + user_share);
        }

        fn deposit_rewards(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let this = get_contract_address();
            assert(caller == self.rewards_depositoor.read(), 'Not authorized');
            self.token.read().transfer_from(caller, this, amount);
            self.total_rewards.write(self.total_rewards.read() + amount);
        }

        fn withdraw(ref self: ContractState, shares: u256) {
            // a = amount
            // B = balance of token before withdraw
            // T = total supply
            // s = shares to burn
            //
            // (T - s) / T = (B - a) / B 
            //
            // a = sB / T
            let caller = get_caller_address();
            let this = get_contract_address();

            let balance = self.token.read().balance_of(this);
            let amount = (shares * balance) / self.total_supply.read();
            PrivateFunctions::_burn(ref self, caller, shares);
            self.token.read().transfer(caller, amount);
        }
    }
}
