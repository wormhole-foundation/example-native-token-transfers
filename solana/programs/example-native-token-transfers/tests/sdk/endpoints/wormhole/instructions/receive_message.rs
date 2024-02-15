use anchor_lang::{prelude::Pubkey, system_program::System, Id, InstructionData, ToAccountMetas};
use solana_sdk::instruction::Instruction;

use crate::sdk::accounts::NTT;

#[derive(Debug, Clone)]
pub struct ReceiveMessage {
    pub payer: Pubkey,
    pub sibling: Pubkey,
    pub vaa: Pubkey,
    pub chain_id: u16,
    pub sequence: u64,
}

pub fn receive_message(ntt: &NTT, accs: ReceiveMessage) -> Instruction {
    let data = example_native_token_transfers::instruction::ReceiveWormholeMessage {};

    let accounts = example_native_token_transfers::accounts::ReceiveMessage {
        payer: accs.payer,
        config: ntt.config(),
        sibling: accs.sibling,
        vaa: accs.vaa,
        endpoint_message: ntt.endpoint_message(accs.chain_id, accs.sequence),
        system_program: System::id(),
    };

    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}
