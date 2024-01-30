#[starknet::contract]
mod Vendao {
    /// ========== Imports ========
    use openzeppelin::access::accesscontrol::interface::IAccessControl;
    use openzeppelin::access::accesscontrol::accesscontrol::AccessControlComponent::InternalTrait;
    use vendao::interfaces::IVendao::{IVendao, ProjectDataType, ProjectType };
    use vendao::interfaces::IERC20::{ IERC20Dispatcher, IERC20DispatcherTrait };
    use starknet::{ ContractAddress, get_caller_address, get_contract_address, contract_address_to_felt252, get_block_timestamp };
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    /// ========== Events =========
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        JoinDao: JoinDao,
        Set: Set,
        Proposed: Proposed,
        Gated: Gated,
        Stage: Stage,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct JoinDao {
        address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct Set {
        new_fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Proposed {
        creator: ContractAddress,
        funding_request: u256,
        equity_offering: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Gated {
        gated: bool
    }

    #[derive(Drop, starknet::Event)]
    struct Stage {
        status: u8,
        proposal_creator: ContractAddress,
        url: ByteArray,
    }

    /// ========== Constants ==========
    const INVESTOR: felt252 = selector!("INVESTOR");
    const NOMINATED_ADMIN: felt252 = selector!("NOMINATED_ADMIN");
    const ONE_WEEK: u64 = 604800;
    const PENDING: u8 = 0;
    const APPROVED: u8 = 1;
    const FUNDED: u8 = 2;


    /// ========== Storage ========
    #[storage]
    struct Storage {
        acceptance_fee: u256,
        gated: bool,
        proposal_time: u64,
        project_proposals: LegacyMap::<u32, ProjectType>,
        proposal_length: u32,
        approved: LegacyMap::<(ContractAddress, u32), bool>,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage
    }

    #[constructor]
    fn constructor(ref self: ContractState, _acceptance_fee: u256, vendao_admin: felt252) {
        self.acceptance_fee.write(_acceptance_fee);
        self.accesscontrol.initializer();
        self.accesscontrol._set_role_admin(NOMINATED_ADMIN, vendao_admin);
    }

    // AccessControl
    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[abi(embed_v0)]
    impl VendaoImpl of IVendao<ContractState> {
        fn join(ref self: ContractState, stable: ContractAddress) {
            let caller = get_caller_address();
            IERC20(stable).transfer_from(caller, get_contract_address(), self.acceptance_fee.read());

            self.accesscontrol._grant_role(INVESTOR, caller);

            self.emit(Event::JoinDao(JoinDao {
                address: caller
            }));
        }

        fn set(ref self: ContractState, _acceptance_fee: u256) {
            self.assert_only_vendao_admin(get_caller_address());
            self.acceptance_fee.write(_acceptance_fee);

            self.emit(Event::Set(Set {
                new_fee: _acceptance_fee,
            }))
        }

        fn pause_proposal(ref self: ContractState) {
            self.assert_only_vendao_admin(get_caller_address());
            self.gated.write(true);

            self.emit(Event::Gated(Gated {gated: true}));
        }
        // anybody can propose a project, but can be gated by the admin
        fn propose_project(ref self: ContractState, project_data: ProjectDataType, equity_address: ContractAddress) {
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            let contract_addr = get_contract_address();
            assert!(
                timestamp > self.proposal_time.read() && !self.gated.read(),
                "VENDAO: Proposal Not Opened"
            );
            let oldbalance = IERC20(equity_address).balance_of(contract_addr); // check token balance before transfer
            IERC20(equity_address).transfer_from(caller, contract_addr, project_data.equity_offering);
            let mut balance = IERC20(equity_address).balance_of(contract_addr); // balance after the transfer
            balance -= oldbalance;
            assert!(balance >= project_data.equity_offering, "VENDAO: Insufficient Equity");
            let mut len = self.proposal_length.read();
            let compute_proposals = ProjectType {
                url: project_data.url,
                validity_period: timestamp + 4 * ONE_WEEK, // 4 weeks validity before approving or funding
                proposal_creator: caller,
                approval_count: 0,
                status: 0,
                funding_request: project_data.funding_req,
                equity_offering: project_data.equity_offering,
                amount_funded: 0,
                cliff_period: project_data.cliff_period,
                vest_period: project_data.vest_period,
                allocation_count: project_data.allocation_count,
                equity_address
            };
            self.proposal_time.write(timestamp + ONE_WEEK); // 1 week per proposal
            self.project_proposals.write(len, compute_proposals);
            self.proposal_length.write(len + 1);

            self.emit(Event::Proposed(Proposed {
                creator: caller,
                funding_request: project_data.funding_req,
                equity_offering: project_data.equity_offering,
            }));
        }

        fn repropose_project(ref self: ContractState, proposal_id: u32, project_data: ProjectDataType) {
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();

            let mut _project = self.project_proposals.read(proposal_id);

            assert!(
                timestamp < _project.validity_period &&
                _project.status == PENDING &&
                _project.proposal_creator == caller,
                "VENDAO: Invalid Reproposal"
            );
            let temp_equity_diff = project_data.equity_offering - _project.equity_offering; // Users can only offer higher equity
            IERC20(_project.equity_address).transfer_from(caller, get_contract_address(), temp_equity_diff);
            // Update project proposal data
            _project.url = project_data.url;
            _project.funding_request = project_data.funding_req;
            _project.equity_offering = project_data.equity_offering;
            _project.cliff_period = project_data.cliff_period;
            _project.vest_period = project_data.vest_period;
            _project.allocation_count = project_data.allocation_count;
            _project.validity_period = timestamp + 4 * ONE_WEEK;

            self.project_proposals.write(proposal_id, _project);

            self.emit(Event::Proposed(Proposed {
                creator: caller,
                funding_request: project_data.funding_req,
                equity_offering: project_data.equity_offering,
            }));
        }

        // only accessible to nominated admins
        fn examine_project(ref self: ContractState, proposal_id: u32) {
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            let has_role = self.accesscontrol.has_role(NOMINATED_ADMIN, caller);
            assert!(has_role, "Not a nominated admin");
            assert!(!self.approved.read((caller, proposal_id)), "Already Voted");
            let mut _project = self.project_proposals.read(proposal_id);
            assert!(_project.status != APPROVED, "Project has already been approved");

            if(timestamp > _project.validity_period && _project.status == PENDING) {
                IERC20(_project.equity_address).transfer(_project.proposal_creator, _project.equity_offering);
                let len = self.proposal_length.read();
                if(proposal_id == len - 1) {
                    self.proposal_length.write(len - 1);
                } else {
                    assert!(proposal_id < len);
                    // cache item
                    let last_item = self.project_proposals.read(len - 1);
                    let proposal_item = self.project_proposals.read(proposal_id);

                    // swap items before poping
                    self.project_proposals.write(len - 1, proposal_item);
                    self.project_proposals.write(proposal_id, last_item);
                    self.proposal_length.write(len - 1);
                }
            } else {
                let count: u8 = _project.approval_count;

            }
        }
    }

    #[generate_trait]
    impl VendaoInternalImpl of VendaoInternalTrait {
        fn assert_only_vendao_admin(ref self: ContractState, caller: ContractAddress) {
            let _vendao_admin: felt252 = self.accesscontrol.get_role_admin(NOMINATED_ADMIN);
            assert!(contract_address_to_felt252(caller) == _vendao_admin, "VENDAO: Not an admin");
        }
    }

    /// Free functions
    fn IERC20(contract_address: ContractAddress) -> IERC20Dispatcher {
        IERC20Dispatcher { contract_address }
    }

    fn nominated_admins_incentive_calc(funding_request: u256) -> u256 {
        // 0.01% of the equity share goes to each nominated admin for examining a project
        // this serve as a motivation fee for nominated admins
        let incentive = (1 * funding_request) / 10000;
        incentive
    }


}