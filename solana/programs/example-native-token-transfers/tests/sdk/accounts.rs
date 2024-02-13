use anchor_lang::prelude::Pubkey;
use example_native_token_transfers::{
    config::Config,
    queue::{
        inbox::{InboxItem, InboxRateLimit},
        outbox::OutboxRateLimit,
    }, sequence::Sequence,
};

pub struct NTT {
    pub program: Pubkey,
}

impl NTT {
    pub fn config(&self) -> Pubkey {
        let (config, _) = Pubkey::find_program_address(&[Config::SEED_PREFIX], &self.program);
        config
    }

    pub fn sequence(&self) -> Pubkey {
        let (sequence, _) =
            Pubkey::find_program_address(&[Sequence::SEED_PREFIX], &self.program);
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

    pub fn inbox_item(&self, chain: u16, sequence: u64) -> Pubkey {
        let (inbox_item, _) = Pubkey::find_program_address(
            &[
                InboxItem::SEED_PREFIX,
                &chain.to_be_bytes(),
                &sequence.to_be_bytes(),
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

    pub fn custody(&self, mint: &Pubkey) -> Pubkey {
        anchor_spl::associated_token::get_associated_token_address_with_program_id(
            &self.token_authority(),
            &mint,
            &spl_token::ID,
        )
    }
}
