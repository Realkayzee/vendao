use starknet::ContractAddress;

#[starknet::interface]
trait IVendao<TContractState> {
    fn join(ref self: TContractState);
    /// function responsible for proposing a project to investors
    ///
    /// # Arguments
    ///
    /// * `url` - url to storage location of the project proposal overview
    /// * `funding_req` - The amount requesting for funding in dollars
    /// * `equity_offering` - amount of equity offering for that funding
    /// * `contract_address` - contract address of the token (equity)
    fn propose_project(ref self: TContractState, url: ByteArray, funding_req: u256, equity_offering: u256, contract_address: ContractAddress);
}