use anchor_lang::{prelude::Pubkey, system_program::System, Id, InstructionData, ToAccountMetas};
use example_native_token_transfers::instructions::SetSiblingArgs;
use solana_sdk::instruction::Instruction;

use crate::sdk::accounts::NTT;

pub struct SetSibling {
    pub payer: Pubkey,
    pub owner: Pubkey,
    pub mint: Pubkey,
}

pub fn set_sibling(ntt: &NTT, accounts: SetSibling, args: SetSiblingArgs) -> Instruction {
    let chain_id = args.chain_id.id;
    let data = example_native_token_transfers::instruction::SetSibling { args };

    let accounts = example_native_token_transfers::accounts::SetSibling {
        config: ntt.config(),
        owner: accounts.owner,
        payer: accounts.payer,
        sibling: ntt.sibling(chain_id),
        inbox_rate_limit: ntt.inbox_rate_limit(chain_id),
        system_program: System::id(),
    };

    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}

pub struct SetPaused {
    pub owner: Pubkey,
}

pub fn set_paused(ntt: &NTT, accounts: SetPaused, pause: bool) -> Instruction {
    let data = example_native_token_transfers::instruction::SetPaused { pause };

    let accounts = example_native_token_transfers::accounts::SetPaused {
        owner: accounts.owner,
        config: ntt.config(),
    };

    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}

pub struct RegisterTransceiver {
    pub payer: Pubkey,
    pub owner: Pubkey,
    pub transceiver: Pubkey,
}

pub fn register_transceiver(ntt: &NTT, accounts: RegisterTransceiver) -> Instruction {
    let data = example_native_token_transfers::instruction::RegisterTransceiver {};

    let accounts = example_native_token_transfers::accounts::RegisterTransceiver {
        config: ntt.config(),
        owner: accounts.owner,
        payer: accounts.payer,
        transceiver: accounts.transceiver,
        registered_transceiver: ntt.registered_transceiver(&accounts.transceiver),
        system_program: System::id(),
    };

    Instruction {
        program_id: ntt.program,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}
