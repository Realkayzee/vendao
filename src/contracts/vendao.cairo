#[starknet::contract]
mod Vendao {
    /// ========== Imports ========
    use core::array::ArrayTrait;
    use openzeppelin::access::accesscontrol::interface::IAccessControl;
    use openzeppelin::access::accesscontrol::accesscontrol::AccessControlComponent::InternalTrait;
    use vendao::interfaces::IVendao::{IVendao, ProjectDataType, ProjectType, InvestorDetails, Contestant };
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
        Stage: Stage,
        Rejected: Rejected,
        Approved: Approved,
        Funded: Funded,
        Invested: Invested,
        Claimed: Claimed,
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
    struct Stage {
        status: u8,
        creator: ContractAddress,
        url: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    struct Rejected {
        url: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    struct Approved {
        url: ByteArray,
    }
    #[derive(Drop, starknet::Event)]
    struct Funded {
        url: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    struct Invested {
        investor: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Claimed {
        claimer: ContractAddress,
    }

    /// ========== Constants ==========
    const INVESTOR: felt252 = selector!("INVESTOR");
    const NOMINATED_ADMIN: felt252 = selector!("NOMINATED_ADMIN");
    const ONE_WEEK: u64 = 604_800;
    const ONE_YEAR: u64 = 31_536_000;
    const PENDING: u8 = 0;
    const APPROVED: u8 = 1;
    const FUNDED: u8 = 2;
    const FUNDING_UNSUCCESFUL: u8 = 3;


    /// ========== Storage ===========
    #[storage]
    struct Storage {
        acceptance_fee: u256,
        gated: bool,
        proposal_time: u64,
        project_proposals: LegacyMap::<u32, ProjectType>,
        proposal_length: u32,
        approved: LegacyMap::<(ContractAddress, u32), bool>,
        fund: LegacyMap::<(ContractAddress, u32), u256>,// fund
        investor_details: LegacyMap::<ContractAddress, InvestorDetails>,
        currency: ContractAddress,
        claimed: LegacyMap::<(ContractAddress, u32), bool>,
        contestant: LegacyMap::<u32, Contestant>,
        contestant_length: u32,
        vote_time: u64,
        election_id: u32,
        voted: LegacyMap::<(ContractAddress, u32),bool>,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage
    }



    #[constructor]
    fn constructor(ref self: ContractState, _acceptance_fee: u256, vendao_admin: felt252, currency: ContractAddress) {
        self.acceptance_fee.write(_acceptance_fee);
        self.currency.write(currency);
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
        fn join(ref self: ContractState) {
            let caller = get_caller_address();
            let currency = self.currency.read();
            IERC20(currency).transfer_from(caller, get_contract_address(), self.acceptance_fee.read());

            self.accesscontrol._grant_role(INVESTOR, caller);

            self.emit(Event::JoinDao(JoinDao {
                address: caller
            }));
        }

        fn set(ref self: ContractState, _acceptance_fee: u256) {
            self.assert_only_vendao_admin(get_caller_address());
            self.acceptance_fee.write(_acceptance_fee);
        }

        fn pause_proposal(ref self: ContractState) {
            self.assert_only_vendao_admin(get_caller_address());
            self.gated.write(true);
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
                creator: caller,
                approval_count: 0,
                status: 0,
                funding_request: project_data.funding_req,
                equity_offering: project_data.equity_offering,
                amount_funded: 0,
                equity_address
            };
            self.proposal_time.write(timestamp + ONE_WEEK); // 1 week per proposal
            self.project_proposals.write(len, compute_proposals);
            self.proposal_length.write(len + 1);
        }

        fn repropose_project(ref self: ContractState, proposal_id: u32, project_data: ProjectDataType) {
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();

            let mut _project = self.project_proposals.read(proposal_id);
            assert!(
                timestamp < _project.validity_period &&
                _project.status == PENDING &&
                _project.creator == caller,
                "VENDAO: Invalid Reproposal"
            );
            let temp_equity_diff = project_data.equity_offering - _project.equity_offering; // Users can only offer higher equity
            IERC20(_project.equity_address).transfer_from(caller, get_contract_address(), temp_equity_diff);
            // Update project proposal data
            _project.url = project_data.url;
            _project.funding_request = project_data.funding_req;
            _project.equity_offering = project_data.equity_offering;
            _project.validity_period = timestamp + 4 * ONE_WEEK;

            self.project_proposals.write(proposal_id, _project);
        }

        // only accessible to nominated admins
        fn examine_project(ref self: ContractState, proposal_id: u32) {
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            self.accesscontrol.assert_only_role(NOMINATED_ADMIN);
            assert!(!self.approved.read((caller, proposal_id)), "Already Voted"); // One vote per nominated admin

            let _project = self.project_proposals.read(proposal_id);
            assert!(_project.status != APPROVED, "Project has already been approved");

            if(timestamp > _project.validity_period && _project.status == PENDING) {
                IERC20(_project.equity_address).transfer(_project.creator, _project.equity_offering);
                let len = self.proposal_length.read();
                self.pop(len, proposal_id); // remove from virtual array and emit event

                self.emit(Event::Rejected(Rejected {
                    url: _project.url,
                }))
            } else {
                let mut proposal = self.project_proposals.read(proposal_id);
                proposal.approval_count += 1;
                self.project_proposals.write(proposal_id, proposal);
                let _calc: u256 = nominated_admins_incentive_calc(_project.funding_request);
                let count = self.project_proposals.read(proposal_id).approval_count;
                self.fund.write((caller, proposal_id), _calc);
                if(count > 3) {
                    let mut _proposal = self.project_proposals.read(proposal_id);
                    _proposal.status = APPROVED;
                    _proposal.validity_period = timestamp + 4 * ONE_WEEK;
                    let vendao_invested_amount = self.vendao_funding_calculation(_project.funding_request);
                    _proposal.amount_funded = vendao_invested_amount;
                    self.project_proposals.write(proposal_id, _proposal);
                    self.fund.write((get_contract_address(), proposal_id), vendao_invested_amount);

                    self.emit(Event::Approved(Approved {
                        url: self.project_proposals.read(proposal_id).url,
                    }));
                }
            }
        }

        // Accessible to only Investors
        fn invest(ref self: ContractState, amount: u256, proposal_id: u32) {
            // variable caching
            let caller = get_caller_address();
            let address_this = get_contract_address();
            let timestamp = get_block_timestamp();
            let _project = self.project_proposals.read(proposal_id);

            assert!(caller == _project.creator, "Creator Can't Invest");

            self.accesscontrol.assert_only_role(INVESTOR);
            if(timestamp > _project.validity_period) {
                if(_project.amount_funded >= _project.funding_request) {
                    let mut proposal = self.project_proposals.read(proposal_id);
                    proposal.status = FUNDED;
                    self.project_proposals.write(proposal_id, proposal);
                } else {
                    let mut proposal = self.project_proposals.read(proposal_id);
                    proposal.status = FUNDING_UNSUCCESFUL;
                    self.project_proposals.write(proposal_id, proposal);
                }
            } else {
                let admin = self.accesscontrol.has_role(NOMINATED_ADMIN, caller);
                let mut investor = self.investor_details.read(caller);
                let investor_fund = self.fund.read((caller, proposal_id));
                let admin_fee = nominated_admins_incentive_calc(_project.funding_request);

                if((investor_fund == 0 && !admin) || (investor_fund == admin_fee && admin)) {
                    investor.investment_count += 1
                }
                IERC20(self.currency.read()).transfer_from(caller, address_this, amount);
                // update project proposal
                let mut proposal = self.project_proposals.read(proposal_id);
                proposal.amount_funded += amount;
                self.project_proposals.write(proposal_id, proposal);
                // update investor details
                investor.total_amount_spent += amount;
                self.investor_details.write(caller, investor);
                let _value = self.fund.read((caller, proposal_id));
                self.fund.write((caller, proposal_id), _value + amount);

                self.emit(Event::Funded(Funded {
                    url: _project.url,
                }));
            }
        }

        // claim is for investors to claim their share of the token based on vesting
        // also for proposal creator to claim their raised funds
        fn claim(ref self: ContractState, proposal_id: u32) {
            let caller = get_caller_address();
            let project = self.project_proposals.read(proposal_id);
            let currency = self.currency.read();

            if(project.status == FUNDED) {
                if(caller == project.creator) {
                    assert!(!self.claimed.read((caller, proposal_id)));
                    IERC20(currency).transfer(project.creator, project.funding_request);
                    self.claimed.write((caller, proposal_id), true);
                } else {
                    let amount_invested = self.fund.read((caller, proposal_id));
                    let (share, unused_funds) = investor_claim_calc(
                        project.funding_request,
                        project.amount_funded,
                        project.equity_offering,
                        amount_invested,
                    );
                    self.fund.write((caller,proposal_id), 0);
                    IERC20(project.equity_address).transfer(caller, share);
                    IERC20(currency).transfer(caller, unused_funds);
                }
            } else if(project.status == FUNDING_UNSUCCESFUL) {
                if(caller == project.creator) {
                    assert!(!self.claimed.read((caller, proposal_id)));
                    IERC20(project.equity_address).transfer(project.creator, project.funding_request);
                    self.claimed.write((caller, proposal_id), true);
                } else {
                    let amount_invested = self.fund.read((caller, proposal_id));
                    self.fund.write((caller, proposal_id), 0);
                    IERC20(currency).transfer(caller, amount_invested);
                }
            }

            self.emit(Event::Claimed(Claimed {
                claimer: caller,
            }))
        }

        fn withdraw(ref self: ContractState, proposal_id: u32) {
            let caller = get_caller_address();
            self.assert_only_vendao_admin(caller);
            let address_this = get_contract_address();
            let project = self.project_proposals.read(proposal_id);
            let vendao_equity = self.fund.read((address_this, proposal_id));

            self.assert_only_vendao_admin(caller);
            assert!(project.status == FUNDED, "Status Not Funded");
            self.fund.write((address_this, proposal_id), 0);
            IERC20(project.equity_address).transfer(caller, vendao_equity);
        }

        fn deposit(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let address_this = get_contract_address();
            IERC20(self.currency.read()).transfer_from(caller, address_this, amount);
        }

        /// =============== View Funstions =================
        fn project_status(self: @ContractState, proposal_id: u32) -> u8 {
            self.project_proposals.read(proposal_id).status
        }

        fn balance(self: @ContractState) -> u256 {
            IERC20(self.currency.read()).balance_of(get_contract_address())
        }

        fn get_length(self: @ContractState) -> u32 {
            self.proposal_length.read()
        }

        fn proposed_projects(self: @ContractState) -> Array<ProjectType> {
            let len = self.get_length();
            let mut i: u32 = 0;
            let mut projects = ArrayTrait::<ProjectType>::new();

            while(i < len) {
                let item = self.project_proposals.read(i);
                projects.append(item);

                i += 1;
            };

            projects
        }

        fn investor_details(self: @ContractState, investor: ContractAddress) -> InvestorDetails {
            self.investor_details.read(investor)
        }

        fn vendao_admin(self: @ContractState) -> felt252 {
            let vendao_admin = self.accesscontrol.get_role_admin(NOMINATED_ADMIN);
            vendao_admin
        }

        // ============== Vendao Governance =============
        fn set_contestant(ref self: ContractState, contestant: Array<Contestant>, vote_time: u64) {
            self.assert_only_vendao_admin(get_caller_address());
            let contestant_len = contestant.len();
            let mut i: u32 = 0;
            while(i < contestant_len) {
                self.contestant.write(i, *contestant.at(i));

                i = i + 1;
            };
            self.vote_time.write(vote_time);
            let election_id = self.election_id.read();
            self.election_id.write(election_id + 1);
        }

        fn vote_admin(ref self: ContractState, contestant_id: u32) {
            let caller = get_caller_address();
            let election_id = self.election_id.read();
            self.accesscontrol.assert_only_role(INVESTOR);
            assert!(!self.voted.read((caller, election_id)), "Already Voted");
            let mut contestant = self.contestant.read(contestant_id);
            contestant.vote_count += 1;
            self.contestant.write(contestant_id, contestant);
            self.voted.write((caller, election_id), true);
        }

        fn contestant_len(self: @ContractState) -> u32 {
            self.contestant_length.read()
        }

        fn nominees(self: @ContractState) -> Array<Contestant> {
            let len = self.contestant_len();
            let mut nominees = ArrayTrait::<Contestant>::new();
            let mut i = 0;

            while(i < len) {
                let item = self.contestant.read(i);
                nominees.append(item);

                i += 1;
            };

            nominees
        }
    }

    #[generate_trait]
    impl VendaoInternalImpl of VendaoInternalTrait {
        fn assert_only_vendao_admin(self: @ContractState, caller: ContractAddress) {
            let _vendao_admin: felt252 = self.accesscontrol.get_role_admin(NOMINATED_ADMIN);
            assert!(contract_address_to_felt252(caller) == _vendao_admin, "VENDAO: Not an admin");
        }

        fn vendao_funding_calculation(self: @ContractState, funding_request: u256) -> u256 {
            let amount: u256 = (10 * funding_request) / 100;
            let address_this = get_contract_address();
            let vendao_balance = IERC20(self.currency.read()).balance_of(address_this);

            if(vendao_balance >= amount) {
                amount
            } else {
                0
            }

        }

        fn pop(ref self: ContractState, len: u32, proposal_id: u32) {
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

    // return share, amountused from the money you invest, and amount left
    // Since the investment technique is an overflow method,
    // the total amount invested may not be used for the equity purchase
    // every body that invested will get their share of investment
    // Not based on firt come first serve
    fn investor_claim_calc(
        funding_req: u256,
        amount_raised: u256,
        equity_offering: u256,
        amount_invested: u256
    ) -> (u256, u256) {
        let share: u256 = (equity_offering * amount_invested) / amount_raised;
        let amount_left: u256 = amount_invested - ((funding_req * amount_invested) / amount_raised);

        (share, amount_left)
    }
}