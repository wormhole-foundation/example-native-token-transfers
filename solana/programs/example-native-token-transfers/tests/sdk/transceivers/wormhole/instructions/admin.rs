use anchor_lang::{prelude::Pubkey, system_program::System, Id, InstructionData, ToAccountMetas};
use example_native_token_transfers::transceivers::wormhole::SetTransceiverSiblingArgs;
use solana_sdk::instruction::Instruction;

use crate::sdk::accounts::NTT;

pub struct SetTransceiverSibling {
    pub payer: Pubkey,
    pub owner: Pubkey,
}

pub fn set_transceiver_sibling(
    ntt: &NTT,
    accounts: SetTransceiverSibling,
    args: SetTransceiverSiblingArgs,
) -> Instruction {
    let chain_id = args.chain_id.id;
    let data = example_native_token_transfers::instruction::SetWormholeSibling { args };

    let accounts = example_native_token_transfers::accounts::SetTransceiverSibling {
        config: ntt.config(),
        owner: accounts.owner,
        payer: accounts.payer,
        sibling: ntt.transceiver_sibling(chain_id),
        system_program: System::id(),
    };

    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}
