use anchor_lang::{prelude::*, InstructionData};
use example_native_token_transfers::{
    accounts::{NotPausedConfig, WormholeAccounts},
    transceivers::wormhole::ReleaseOutboundArgs,
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
    let data = example_native_token_transfers::instruction::ReleaseWormholeOutbound { args };
    let accounts = example_native_token_transfers::accounts::ReleaseOutbound {
        payer: release_outbound.payer,
        config: NotPausedConfig {
            config: ntt.config(),
        },
        outbox_item: release_outbound.outbox_item,
        wormhole_message: ntt.wormhole_message(&release_outbound.outbox_item),
        emitter: ntt.emitter(),
        transceiver: ntt.registered_transceiver(&ntt.program),
        wormhole: WormholeAccounts {
            bridge: ntt.wormhole.bridge(),
            fee_collector: ntt.wormhole.fee_collector(),
            sequence: ntt.wormhole_sequence(),
            program: ntt.wormhole.program,
            system_program: System::id(),
            clock: Clock::id(),
            rent: Rent::id(),
        },
    };
    Instruction {
        program_id: example_native_token_transfers::ID,
        accounts: accounts.to_account_metas(None),
        data: data.data(),
    }
}
