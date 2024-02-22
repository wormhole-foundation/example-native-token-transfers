//! General purpose governance program.
//!
//! This program is designed to be a generic governance program that can be used to
//! execute arbitrary instructions on behalf of a guardian set.
//! The program being governed simply needs to expose admin instructions that can be
//! invoked by a signer account (that's checked by the program's access control logic).
//!
//! If the signer is set to be the "governance" PDA of this program, then the governance
//! instruction is able to invoke the program's admin instructions.
//!
//! The instruction needs to be encoded in the VAA payload, with all the
//! accounts. These accounts may be in any order, with two placeholder accounts:
//! - [`OWNER`]: the program will replace this account with the governance PDA
//! - [`PAYER`]: the program will replace this account with the payer account
use anchor_lang::prelude::*;
use solana_program::instruction::Instruction;
use wormhole_anchor_sdk::wormhole::PostedVaa;
use wormhole_sdk::{Chain, GOVERNANCE_EMITTER};

use crate::error::GovernanceError;

pub const OWNER: Pubkey = sentinel_pubkey(b"owner");
pub const PAYER: Pubkey = sentinel_pubkey(b"payer");

#[derive(Accounts)]
pub struct Governance<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        mut,
        seeds = [b"governance"],
        bump,
    )]
    /// CHECK: TODO
    pub governance: AccountInfo<'info>,

    #[account(
        constraint = vaa.emitter_chain() == Into::<u16>::into(Chain::Solana) @ GovernanceError::InvalidGovernanceChain,
        constraint = *vaa.emitter_address() == GOVERNANCE_EMITTER.0 @ GovernanceError::InvalidGovernanceEmitter,
    )]
    pub vaa: Account<'info, PostedVaa<GovernanceMessage>>,

    #[account(executable)]
    pub program: AccountInfo<'info>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
// TODO: adjust wire format to match the wh governance spec
pub struct GovernanceMessage {
    pub program_id: Pubkey,
    pub accounts: Vec<Acc>,
    pub data: Vec<u8>,
}

impl From<GovernanceMessage> for Instruction {
    fn from(val: GovernanceMessage) -> Self {
        let GovernanceMessage {
            program_id,
            accounts,
            data,
        } = val;
        let accounts: Vec<AccountMeta> = accounts.into_iter().map(|a| a.into()).collect();
        Instruction {
            program_id,
            accounts,
            data,
        }
    }
}

impl From<Instruction> for GovernanceMessage {
    fn from(instruction: Instruction) -> GovernanceMessage {
        let Instruction {
            program_id,
            accounts,
            data,
        } = instruction;
        let accounts: Vec<Acc> = accounts.into_iter().map(|a| a.into()).collect();
        GovernanceMessage {
            program_id,
            accounts,
            data,
        }
    }
}

/// A copy of [`solana_program::instruction::AccountMeta`] with
/// `AccountSerialize`/`AccountDeserialize` impl.
/// Would be nice to just use the original, but it lacks these traits.
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct Acc {
    pub pubkey: Pubkey,
    pub is_signer: bool,
    pub is_writable: bool,
}

impl From<Acc> for AccountMeta {
    fn from(val: Acc) -> Self {
        let Acc {
            pubkey,
            is_signer,
            is_writable,
        } = val;
        AccountMeta {
            pubkey,
            is_signer,
            is_writable,
        }
    }
}

impl From<AccountMeta> for Acc {
    fn from(account_meta: AccountMeta) -> Acc {
        let AccountMeta {
            pubkey,
            is_signer,
            is_writable,
        } = account_meta;
        Acc {
            pubkey,
            is_signer,
            is_writable,
        }
    }
}

pub fn governance<'info>(ctx: Context<'_, '_, '_, 'info, Governance<'info>>) -> Result<()> {
    let vaa_data = ctx.accounts.vaa.data();

    let mut instruction: Instruction = vaa_data.clone().into();

    instruction.accounts.iter_mut().for_each(|acc| {
        if acc.pubkey == OWNER {
            acc.pubkey = ctx.accounts.governance.key();
        } else if acc.pubkey == PAYER {
            acc.pubkey = ctx.accounts.payer.key();
        }
    });

    let mut all_account_infos = ctx.accounts.to_account_infos();
    all_account_infos.extend_from_slice(ctx.remaining_accounts);

    solana_program::program::invoke_signed(
        &instruction,
        &all_account_infos,
        &[&[b"governance", &[ctx.bumps.governance]]],
    )?;

    Ok(())
}

const fn sentinel_pubkey(input: &[u8]) -> Pubkey {
    let mut output: [u8; 32] = [0; 32];

    let mut i = 0;
    while i < input.len() {
        output[i] = input[i];
        i += 1;
    }

    Pubkey::new_from_array(output)
}
