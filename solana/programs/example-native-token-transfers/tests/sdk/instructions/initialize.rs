use anchor_lang::{prelude::Pubkey, system_program::System, Id, InstructionData, ToAccountMetas};
use anchor_spl::{associated_token::AssociatedToken, token::Token};
use example_native_token_transfers::instructions::InitializeArgs;
use solana_sdk::instruction::Instruction;
use wormhole_solana_utils::cpi::bpf_loader_upgradeable::BpfLoaderUpgradeable;

use crate::sdk::accounts::NTT;

pub struct Initialize {
    pub payer: Pubkey,
    pub deployer: Pubkey,
    pub mint: Pubkey,
}

pub fn initialize(ntt: &NTT, accounts: Initialize, args: InitializeArgs) -> Instruction {
    let data = example_native_token_transfers::instruction::Initialize { args };

    let bpf_loader_upgradeable_program = BpfLoaderUpgradeable::id();
    let accounts = example_native_token_transfers::accounts::Initialize {
        payer: accounts.payer,
        deployer: accounts.deployer,
        program_data: ntt.program_data(),
        config: ntt.config(),
        mint: accounts.mint,
        seq: ntt.sequence(),
        rate_limit: ntt.outbox_rate_limit(),
        token_authority: ntt.token_authority(),
        custody: ntt.custody(&accounts.mint),
        token_program: Token::id(),
        associated_token_program: AssociatedToken::id(),
        bpf_loader_upgradeable_program,
        system_program: System::id(),
    };

    // fetch account
    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}
