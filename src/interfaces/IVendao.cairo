use starknet::ContractAddress;

#[starknet::interface]
trait IVendao<TContractState> {
    /// join is the entry point to vendao
    fn join(ref self: TContractState, stable: ContractAddress);
    /// set is use for setting the requirement for vendao
    fn set(ref self: TContractState, _acceptance_fee: u256);
    /// function responsible for proposing a project to investors
    fn propose_project(ref self: TContractState, project_data: ProjectDataType, equity_address: ContractAddress);

    /// In a situation where the proposal is being rejected and told to change terms
    fn repropose_project(ref self: TContractState, proposal_id: u32, project_data: ProjectDataType);
    /// This can only be called by the admin
    /// pause proposal is used to prevent excessive project proposal
    fn pause_proposal(ref self: TContractState);
    /// examine proposal is only accessible by the nominated admins
    /// the examine project is can be used to either accept or reject
    /// a project proposal by the nominated admins
    fn examine_project(ref self: TContractState, proposal_id: u32);
    /// invest is used by investors to invest in project of their choice
    fn invest(ref self: TContractState, amount: u256);
    /// project owner can claim successful funding
    /// or take back their offered equity for unsuccesful funding
    fn claim(ref self: TContractState, proposal_id: u32);
    /// swap equity can only be handled by the admin
    /// where admin swap some equity to stable tokens and native currency
    fn swap_equity(ref self: TContractState, equity: ContractAddress, token: ContractAddress, amount: u256);

    // ============= View Functions ============
    fn project_status(self: @TContractState) -> bool;
    fn token_balance(self: @TContractState) -> u256;
    fn get_length(self: @TContractState) -> u256;
    fn proposed_projects(self: @TContractState) -> Array<felt252>;
    fn proposals_to_invest(self: @TContractState) -> Array<felt252>;
    fn funded_project(self: @TContractState) -> Array<felt252>;
    fn investor_details(self: @TContractState) -> felt252;
    fn proposal_time(self: @TContractState) -> u64;
    fn admin(self: @TContractState) -> ContractAddress;
}

/// ======== Custom Types =========
#[derive(Drop, Serde)]
struct ProjectDataType {
    url: ByteArray, // url to storage location of the project proposal overview
    funding_req: u256, // The amount requesting for funding in dollars
    equity_offering: u256, // amount of equity offering for that funding
    cliff_period: u64, // max of 1 year
    vest_period: u64, // max of 8 years
    allocation_count: u8,
}

#[derive(Drop, Serde, starknet::Store)]
struct ProjectType {
    url: ByteArray,
    validity_period: u64,
    proposal_creator: ContractAddress,
    approval_count: u8,
    status: u8, // 0 - Pending, 1 - Approved, 2 - Funded
    funding_request: u256,
    equity_offering: u256,
    amount_funded: u256,
    cliff_period: u64,
    vest_period: u64,
    allocation_count: u8,
    equity_address: ContractAddress,
}