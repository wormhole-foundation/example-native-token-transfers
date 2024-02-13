use anchor_lang::{prelude::Pubkey, system_program::System, Id, InstructionData, ToAccountMetas};
use anchor_spl::{associated_token::AssociatedToken, token::Token};
use example_native_token_transfers::instructions::InitializeArgs;
use solana_sdk::instruction::Instruction;

use crate::sdk::accounts::NTT;

pub struct Initialize {
    pub payer: Pubkey,
    pub owner: Pubkey,
    pub mint: Pubkey,
}

pub fn initialize(ntt: &NTT, accounts: Initialize, args: InitializeArgs) -> Instruction {
    let data = example_native_token_transfers::instruction::Initialize { args };

    let accounts = example_native_token_transfers::accounts::Initialize {
        payer: accounts.payer,
        owner: accounts.owner,
        config: ntt.config(),
        mint: accounts.mint,
        seq: ntt.sequence(),
        rate_limit: ntt.outbox_rate_limit(),
        token_authority: ntt.token_authority(),
        custody: ntt.custody(&accounts.mint),
        token_program: Token::id(),
        associated_token_program: AssociatedToken::id(),
        system_program: System::id(),
    };

    // fetch account
    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}
