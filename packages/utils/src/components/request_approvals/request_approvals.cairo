#[starknet::component]
pub(crate) mod RequestApprovalsComponent {
    use core::panic_with_felt252;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::request_approvals::errors;
    use starkware_utils::components::request_approvals::interface::{
        IRequestApprovals, RequestStatus,
    };
    use starkware_utils::hash::message_hash::OffchainMessageHash;
    use starkware_utils::signature::stark::{
        HashType, PublicKey, Signature, validate_stark_signature,
    };
    use starkware_utils::time::time::{Time, Timestamp};

    #[storage]
    pub struct Storage {
        approved_requests: Map<HashType, RequestStatus>,
        /// Stores forced action requests as (timestamp, status) by request_hash.
        forced_action_requests: Map<HashType, (Timestamp, RequestStatus)>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(RequestApprovalsImpl)]
    impl RequestApprovals<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of IRequestApprovals<ComponentState<TContractState>> {
        fn get_request_status(
            self: @ComponentState<TContractState>, request_hash: HashType,
        ) -> RequestStatus {
            self._get_request_status(:request_hash)
        }
    }


    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Registers an approval for a request.
        /// If the owner_account is non-zero, the caller must be the owner_account.
        /// The approval is signed with the public key.
        /// The signature is verified with the hash of the request.
        /// The request is stored with a status of PENDING.
        fn register_approval<T, +OffchainMessageHash<T>, +Drop<T>>(
            ref self: ComponentState<TContractState>,
            owner_account: Option<ContractAddress>,
            public_key: PublicKey,
            signature: Signature,
            args: T,
        ) -> HashType {
            let request_hash = self.store_approval(:public_key, :args);
            if let Option::Some(owner_account) = owner_account {
                assert(owner_account == get_caller_address(), errors::CALLER_IS_NOT_OWNER_ACCOUNT);
            }
            validate_stark_signature(:public_key, msg_hash: request_hash, :signature);
            request_hash
        }
        /// Registers an approval for a request without signature or caller validation.
        ///
        /// This is intended for use with forced requests, where we track the same logical
        /// request in two maps:
        /// - `approved_requests` (generic approval status)
        /// - `forced_action_requests` (forced metadata: timestamp + status)
        /// This function is used to register the original request hash in the approvals map.

        fn store_approval<T, +OffchainMessageHash<T>, +Drop<T>>(
            ref self: ComponentState<TContractState>, public_key: PublicKey, args: T,
        ) -> HashType {
            let request_hash = args.get_message_hash(:public_key);
            assert(
                self._get_request_status(:request_hash) == RequestStatus::NOT_REGISTERED,
                errors::REQUEST_ALREADY_REGISTERED,
            );
            self.approved_requests.write(key: request_hash, value: RequestStatus::PENDING);
            request_hash
        }
        /// Registers a forced approval action.
        /// If the owner_account is non-zero, the caller must be the owner_account.
        /// The request is signed with the public key.
        /// The request is stored with a status of PENDING, and the current time.
        fn register_forced_approval<T, +OffchainMessageHash<T>, +Drop<T>>(
            ref self: ComponentState<TContractState>,
            owner_account: Option<ContractAddress>,
            public_key: PublicKey,
            signature: Signature,
            args: T,
        ) -> HashType {
            let request_hash = args.get_message_hash(:public_key);

            assert(
                self
                    ._get_forced_action_request_status(
                        request_hash,
                    ) == RequestStatus::NOT_REGISTERED,
                errors::REQUEST_ALREADY_REGISTERED,
            );
            if let Option::Some(owner_account) = owner_account {
                assert(owner_account == get_caller_address(), errors::CALLER_IS_NOT_OWNER_ACCOUNT);
            }
            validate_stark_signature(:public_key, msg_hash: request_hash, :signature);
            self
                .forced_action_requests
                .write(key: request_hash, value: (Time::now(), RequestStatus::PENDING));
            request_hash
        }

        /// Consumes an approved request.
        /// Marks the request with status DONE.
        ///
        /// Validations:
        ///     The request must be registered with PENDING state.
        fn consume_approved_request<T, +OffchainMessageHash<T>, +Drop<T>>(
            ref self: ComponentState<TContractState>, args: T, public_key: PublicKey,
        ) -> HashType {
            let request_hash = args.get_message_hash(:public_key);
            let request_status = self._get_request_status(:request_hash);
            match request_status {
                RequestStatus::NOT_REGISTERED => panic_with_felt252(errors::REQUEST_NOT_REGISTERED),
                RequestStatus::PROCESSED => panic_with_felt252(errors::REQUEST_ALREADY_PROCESSED),
                RequestStatus::PENDING => {},
            }
            self.approved_requests.write(request_hash, RequestStatus::PROCESSED);
            request_hash
        }

        /// Consumes a forced-approved request and updates its status to DONE.
        ///
        /// Validations:
        ///     - The request must be in a PENDING state.
        ///
        /// Returns:
        ///     - The timestamp of when the forced request was approved.
        ///     - The hash of the forced request.
        fn consume_forced_approved_request<T, +OffchainMessageHash<T>, +Drop<T>>(
            ref self: ComponentState<TContractState>, args: T, public_key: PublicKey,
        ) -> (Timestamp, HashType) {
            let request_hash = args.get_message_hash(:public_key);
            let (request_time, request_status) = self.forced_action_requests.read(request_hash);
            match request_status {
                RequestStatus::NOT_REGISTERED => panic_with_felt252(errors::REQUEST_NOT_REGISTERED),
                RequestStatus::PROCESSED => panic_with_felt252(errors::REQUEST_ALREADY_PROCESSED),
                RequestStatus::PENDING => {},
            }
            self
                .forced_action_requests
                .write(request_hash, (request_time, RequestStatus::PROCESSED));
            (request_time, request_hash)
        }
    }

    #[generate_trait]
    impl PrivateImpl<
        TContractState, +HasComponent<TContractState>,
    > of PrivateTrait<TContractState> {
        fn _get_request_status(
            self: @ComponentState<TContractState>, request_hash: HashType,
        ) -> RequestStatus {
            self.approved_requests.read(request_hash)
        }
        fn _get_forced_action_request_status(
            self: @ComponentState<TContractState>, request_hash: HashType,
        ) -> RequestStatus {
            let (_, status) = self.forced_action_requests.read(request_hash);
            status
        }
    }
}
