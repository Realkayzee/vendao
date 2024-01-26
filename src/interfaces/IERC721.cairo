use starknet::ContractAddress;

#[starknet::interface]
trait IERC721<TContractState> {
    fn safe_transfer_from(ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256);
}