use anchor_lang::prelude::Pubkey;
use example_native_token_transfers::{
    config::Config,
    messages::{ManagerMessage, NativeTokenTransfer},
    queue::{
        inbox::{InboxItem, InboxRateLimit},
        outbox::OutboxRateLimit,
    },
    registered_endpoint::RegisteredEndpoint,
    sequence::Sequence,
};
use sha3::{Digest, Keccak256};
use wormhole_anchor_sdk::wormhole;
use wormhole_io::TypePrefixedPayload;

pub struct Wormhole {
    pub program: Pubkey,
}

impl Wormhole {
    pub fn bridge(&self) -> Pubkey {
        let (bridge, _) =
            Pubkey::find_program_address(&[wormhole::BridgeData::SEED_PREFIX], &self.program);
        bridge
    }

    pub fn fee_collector(&self) -> Pubkey {
        let (fee_collector, _) =
            Pubkey::find_program_address(&[wormhole::FeeCollector::SEED_PREFIX], &self.program);
        fee_collector
    }

    pub fn sequence(&self, emitter: &Pubkey) -> Pubkey {
        let (sequence, _) = Pubkey::find_program_address(
            &[wormhole::SequenceTracker::SEED_PREFIX, emitter.as_ref()],
            &self.program,
        );
        sequence
    }
}

pub struct NTT {
    pub program: Pubkey,
    pub wormhole: Wormhole,
}

impl NTT {
    pub fn config(&self) -> Pubkey {
        let (config, _) = Pubkey::find_program_address(&[Config::SEED_PREFIX], &self.program);
        config
    }

    pub fn sequence(&self) -> Pubkey {
        let (sequence, _) = Pubkey::find_program_address(&[Sequence::SEED_PREFIX], &self.program);
        sequence
    }

    pub fn outbox_rate_limit(&self) -> Pubkey {
        let (outbox_rate_limit, _) =
            Pubkey::find_program_address(&[OutboxRateLimit::SEED_PREFIX], &self.program);
        outbox_rate_limit
    }

    pub fn inbox_rate_limit(&self, chain: u16) -> Pubkey {
        let (inbox_rate_limit, _) = Pubkey::find_program_address(
            &[InboxRateLimit::SEED_PREFIX, &chain.to_be_bytes()],
            &self.program,
        );
        inbox_rate_limit
    }

    pub fn inbox_item(
        &self,
        chain: u16,
        manager_message: ManagerMessage<NativeTokenTransfer>,
    ) -> Pubkey {
        let mut hasher = Keccak256::new();
        hasher.update(&TypePrefixedPayload::to_vec_payload(&manager_message));

        let (inbox_item, _) = Pubkey::find_program_address(
            &[
                InboxItem::SEED_PREFIX,
                &chain.to_be_bytes(),
                &hasher.finalize(),
            ],
            &self.program,
        );
        inbox_item
    }

    pub fn token_authority(&self) -> Pubkey {
        let (token_authority, _) =
            Pubkey::find_program_address(&[b"token_authority".as_ref()], &self.program);
        token_authority
    }

    pub fn registered_endpoint(&self, endpoint: &Pubkey) -> Pubkey {
        let (registered_endpoint, _) = Pubkey::find_program_address(
            &[RegisteredEndpoint::SEED_PREFIX, endpoint.as_ref()],
            &self.program,
        );
        registered_endpoint
    }

    pub fn emitter(&self) -> Pubkey {
        let (emitter, _) = Pubkey::find_program_address(&[b"emitter".as_ref()], &self.program);
        emitter
    }

    pub fn wormhole_message(&self, outbox_item: &Pubkey) -> Pubkey {
        let (wormhole_message, _) = Pubkey::find_program_address(
            &[b"message".as_ref(), outbox_item.as_ref()],
            &self.program,
        );
        wormhole_message
    }

    pub fn sibling(&self, chain: u16) -> Pubkey {
        let (sibling, _) = Pubkey::find_program_address(
            &[b"sibling".as_ref(), &chain.to_be_bytes()],
            &self.program,
        );
        sibling
    }

    pub fn endpoint_sibling(&self, chain: u16) -> Pubkey {
        let (sibling, _) = Pubkey::find_program_address(
            &[b"endpoint_sibling".as_ref(), &chain.to_be_bytes()],
            &self.program,
        );
        sibling
    }

    pub fn endpoint_message(&self, chain: u16, sequence: u64) -> Pubkey {
        let (endpoint_message, _) = Pubkey::find_program_address(
            &[
                b"endpoint_message".as_ref(),
                &chain.to_be_bytes(),
                &sequence.to_be_bytes(),
            ],
            &self.program,
        );
        endpoint_message
    }

    pub fn custody(&self, mint: &Pubkey) -> Pubkey {
        anchor_spl::associated_token::get_associated_token_address_with_program_id(
            &self.token_authority(),
            &mint,
            &spl_token::ID,
        )
    }

    pub fn wormhole_sequence(&self) -> Pubkey {
        self.wormhole.sequence(&self.emitter())
    }
}
