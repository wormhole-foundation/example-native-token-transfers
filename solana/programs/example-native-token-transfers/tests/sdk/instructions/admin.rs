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
        mint: accounts.mint,
        system_program: System::id(),
    };

    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}
