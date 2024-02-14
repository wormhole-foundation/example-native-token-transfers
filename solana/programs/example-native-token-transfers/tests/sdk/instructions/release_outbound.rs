use anchor_lang::{prelude::*, InstructionData};
use example_native_token_transfers::{
    accounts::NotPausedConfig, instructions::ReleaseOutboundArgs,
};
use solana_sdk::{instruction::Instruction, sysvar::SysvarId};

use crate::sdk::accounts::NTT;

pub struct ReleaseOutbound {
    pub payer: Pubkey,
    pub outbox_item: Pubkey,
}

pub fn release_outbound(
    ntt: &NTT,
    release_outbound: ReleaseOutbound,
    args: ReleaseOutboundArgs,
) -> Instruction {
    let data = example_native_token_transfers::instruction::ReleaseOutbound { args };
    let accounts = example_native_token_transfers::accounts::ReleaseOutbound {
        payer: release_outbound.payer,
        config: NotPausedConfig {
            config: ntt.config(),
        },
        outbox_item: release_outbound.outbox_item,
        wormhole_message: ntt.wormhole_message(&release_outbound.outbox_item),
        emitter: ntt.emitter(),
        wormhole_bridge: ntt.wormhole.bridge(),
        wormhole_fee_collector: ntt.wormhole.fee_collector(),
        wormhole_sequence: ntt.wormhole_sequence(),
        wormhole_program: ntt.wormhole.program,
        system_program: System::id(),
        clock: Clock::id(),
        rent: Rent::id(),
    };
    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}
