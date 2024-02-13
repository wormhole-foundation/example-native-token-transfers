use anchor_lang::{prelude::Pubkey, system_program::System, Id, InstructionData, ToAccountMetas};
use anchor_spl::token::Token;
use example_native_token_transfers::{accounts::NotPausedConfig, instructions::TransferArgs};
use solana_sdk::instruction::Instruction;

use crate::sdk::accounts::NTT;

pub struct Transfer {
    pub payer: Pubkey,
    pub mint: Pubkey,
    pub from: Pubkey,
    pub from_authority: Pubkey,
    pub outbox_item: Pubkey,
}

pub fn transfer_burn(ntt: &NTT, transfer: Transfer, args: TransferArgs) -> Instruction {
    let chain_id = args.recipient_chain.id;
    let data = example_native_token_transfers::instruction::TransferBurn { args };

    let accounts = example_native_token_transfers::accounts::TransferBurn {
        common: common(ntt, &transfer),
        inbox_rate_limit: ntt.inbox_rate_limit(chain_id),
    };

    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}

pub fn transfer_lock(ntt: &NTT, transfer: Transfer, args: TransferArgs) -> Instruction {
    let chain_id = args.recipient_chain.id;
    let data = example_native_token_transfers::instruction::TransferLock { args };

    let accounts = example_native_token_transfers::accounts::TransferLock {
        common: common(ntt, &transfer),
        inbox_rate_limit: ntt.inbox_rate_limit(chain_id),
        token_authority: ntt.token_authority(),
        custody: ntt.custody(&transfer.mint),
    };
    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}

fn common(ntt: &NTT, transfer: &Transfer) -> example_native_token_transfers::accounts::Transfer {
    example_native_token_transfers::accounts::Transfer {
        payer: transfer.payer,
        config: NotPausedConfig {
            config: ntt.config(),
        },
        mint: transfer.mint,
        from: transfer.from,
        from_authority: transfer.from_authority,
        token_program: Token::id(),
        seq: ntt.sequence(),
        outbox_item: transfer.outbox_item,
        outbox_rate_limit: ntt.outbox_rate_limit(),
        system_program: System::id(),
    }
}
