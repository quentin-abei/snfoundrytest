use core::result::ResultTrait;
use starknet::ContractAddress;
use core::traits::TryInto;
use core::serde::Serde;
use test1::staking::IStakingRewardsDispatcher;
use test1::staking::IStakingRewardsDispatcherTrait;

use openzeppelin::token::erc20::interface::{ ERC20ABIDispatcher, ERC20ABIDispatcherTrait};


use snforge_std::{
    ContractClass, ContractClassTrait, CheatTarget, declare, start_prank, stop_prank, TxInfoMock,
    start_warp, stop_warp, get_class_hash
};


fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name);
    let STAKING_TOKEN : ContractAddress = deploy_token("ERC20Token");
    let mut calldata = array![];
    (OWNER() , STAKING_TOKEN,).serialize(ref calldata);
    let contract_address = contract.deploy(@calldata).unwrap();
    return (contract_address);
}


fn DEFAULT_INITIAL_SUPPLY() -> u256 {
    return (21_000_000 * 1000000000000000000);
}

fn OWNER() -> ContractAddress {
    'owner'.try_into().unwrap()
}

fn USER() -> ContractAddress {
    'user'.try_into().unwrap()
}

fn deploy_token(name: ByteArray) -> ContractAddress {
    let contract = declare(name);
    let mut calldata = array![];
    (DEFAULT_INITIAL_SUPPLY(), OWNER()).serialize(ref calldata);
    let contract_address = contract.deploy(@calldata).unwrap();
    return(contract_address);
}

#[test]
fn test_staking_token_1() {
    let owner = OWNER();
    let user = USER();
    let addr : ContractAddress = deploy_contract("SimpleRewards");

    let mut dispatcher = IStakingRewardsDispatcher {contract_address: addr };

    let staking_token_address = dispatcher.staking_Token();
    //let rewards_token_address = dispatcher.rewards_Token();

    let token_contract = ERC20ABIDispatcher{ contract_address: staking_token_address };

    let balance_before = token_contract.balance_of(dispatcher.contract_address);
    assert(balance_before == 0, 'Invalid balance');

    start_prank(CheatTarget::One(staking_token_address), owner);
    let result: bool = token_contract.approve(dispatcher.contract_address, 21_000_000 * 1000000000000000000);
    assert(result == true, 'did not approve');

    let allow: u256 = token_contract.allowance(owner, dispatcher.contract_address);
    assert(allow == 21_000_000 * 1000000000000000000, 'did not allow');

    let owner_bal = token_contract.balance_of(owner);
    assert(owner_bal == 21_000_000 * 1000000000000000000, 'owner does not own tokens');
    println!("owner bal {:?}", owner_bal);

    // before staking token, owner need to send some rewards token to the contract
    // we will send token to another address to stake also
    token_contract.transfer(dispatcher.contract_address , 21 * 1000000000000000000 );
    println!("1");
    token_contract.transfer(user , 21 * 1000000000000000000 );
    println!("2");

    let balance_user = token_contract.balance_of(user);
    println!("3");
    let balance_contr = token_contract.balance_of(dispatcher.contract_address);
    println!("4");
    assert(balance_user == 21 * 1000000000000000000, 'error with user bal' );
    println!("5");
    assert(balance_contr == 21 * 1000000000000000000, 'error with user bal' );
    println!("6");

    println!("preparing contract for staking done");

    stop_prank(CheatTarget::One(staking_token_address));
    println!("7");

    start_prank(CheatTarget::One(staking_token_address), user);
    let result: bool = token_contract.approve(dispatcher.contract_address, balance_user);
    assert(result == true, 'did not approve');
    let balance_user = token_contract.balance_of(user);
    assert(balance_user == 21 * 1000000000000000000, 'error with user bal' );
    println!("8");
    stop_prank(CheatTarget::One(staking_token_address));
    
    start_prank(CheatTarget::One(dispatcher.contract_address), owner);
    dispatcher.update_rewards_index(21 * 1000000000000000000);
    stop_prank(CheatTarget::One(dispatcher.contract_address));

    start_prank(CheatTarget::One(dispatcher.contract_address), user);    
    dispatcher.stake(1000000000000000000);
    println!("staking done");
    stop_prank(CheatTarget::One(dispatcher.contract_address));

    let balance_after = token_contract.balance_of(dispatcher.contract_address);
    assert(balance_after == 22 * 1000000000000000000, 'Invalid balance');

    start_prank(CheatTarget::One(staking_token_address), user);
    let balance_user = token_contract.balance_of(user);
    println!("user bal after stake {:?}", balance_user);
    assert(balance_user == 20 * 1000000000000000000, 'error with user bal' );
    stop_prank(CheatTarget::One(staking_token_address));

    // now we need to skip some time and then call claim
    start_warp(CheatTarget::One(dispatcher.contract_address), 1200);
    start_prank(CheatTarget::One(dispatcher.contract_address), user);
    let claimed = dispatcher.claim();
    println!("claimed {:?}", claimed);
    
}

// #[test]
// #[feature("safe_dispatcher")]
// fn test_cannot_increase_balance_with_zero_value() {
//     let contract_address = deploy_contract("HelloStarknet");

//     let safe_dispatcher = IHelloStarknetSafeDispatcher { contract_address };

//     let balance_before = safe_dispatcher.get_balance().unwrap();
//     assert(balance_before == 0, 'Invalid balance');

//     match safe_dispatcher.increase_balance(0) {
//         Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
//         Result::Err(panic_data) => {
//             assert(*panic_data.at(0) == 'Amount cannot be 0', *panic_data.at(0));
//         }
//     };
// }
