use starknet::ContractAddress;

#[starknet::interface]
trait IVendao<TContractState> {
    /// join is the entry point to vendao
    fn join(ref self: TContractState);
    /// set is responsible for setting the requirement for vendao
    fn set(ref self: TContractState, acceptance_fee: u256);
    /// function responsible for proposing a project to investors
    ///
    /// # Arguments
    ///
    /// * `url` - url to storage location of the project proposal overview
    /// * `funding_req` - The amount requesting for funding in dollars
    /// * `equity_offering` - amount of equity offering for that funding
    /// * `contract_address` - contract address of the token (equity)
    fn propose_project(ref self: TContractState, url: ByteArray, funding_req: u256, equity_offering: u256, contract_address: ContractAddress);

    /// In a situation where the proposal is being rejected and told to change terms
    /// # Arguments
    ///
    /// * `proposal_id` - proposal id
    /// * `url` - url pointing to the storage location of the updated project proposal overview
    /// * `funding_req` - modified amount requesting for funding in dollars
    /// * `equity_offering` = amount of equity offering for that funding
    fn repropose_project(ref self: TContractState, proposal_id: u32, url: ByteArray, funding_req: u256, equity_offering: u256);
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