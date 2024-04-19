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
use std::io;

use anchor_lang::prelude::*;
use solana_program::instruction::Instruction;
use wormhole_anchor_sdk::wormhole::PostedVaa;
use wormhole_io::{Readable, Writeable};
use wormhole_sdk::{Chain, GOVERNANCE_EMITTER};

use crate::error::GovernanceError;

pub const OWNER: Pubkey = sentinel_pubkey(b"owner");
pub const PAYER: Pubkey = sentinel_pubkey(b"payer");

#[account]
#[derive(InitSpace)]
pub struct ReplayProtection {
    pub bump: u8,
}

impl ReplayProtection {
    pub const SEED_PREFIX: &'static [u8] = b"replay";
}

#[derive(Accounts)]
pub struct Governance<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        mut,
        seeds = [b"governance"],
        bump,
    )]
    /// CHECK: governance PDA. This PDA has to be the owner assigned to the
    /// governed program.
    pub governance: AccountInfo<'info>,

    #[account(
        constraint = vaa.emitter_chain() == Into::<u16>::into(Chain::Solana) @ GovernanceError::InvalidGovernanceChain,
        constraint = *vaa.emitter_address() == GOVERNANCE_EMITTER.0 @ GovernanceError::InvalidGovernanceEmitter,
    )]
    pub vaa: Account<'info, PostedVaa<GovernanceMessage>>,

    #[account(executable)]
    pub program: AccountInfo<'info>,

    #[account(
        init,
        space = 8 + ReplayProtection::INIT_SPACE,
        payer = payer,
        seeds = [
            ReplayProtection::SEED_PREFIX,
            vaa.emitter_chain().to_be_bytes().as_ref(),
            vaa.emitter_address().as_ref(),
            vaa.sequence().to_be_bytes().as_ref()
        ],
        bump
    )]
    pub replay: Account<'info, ReplayProtection>,

    pub system_program: Program<'info, System>,
}

/// General purpose governance message to call arbitrary instructions on a governed program.
///
/// This message adheres to the Wormhole governance packet standard:
/// https://github.com/wormhole-foundation/wormhole/blob/main/whitepapers/0002_governance_messaging.md
///
/// The wire format for this message is:
/// | field           |                     size (bytes) | description                             |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | MODULE          |                               32 | Governance module identifier            |
/// | ACTION          |                                1 | Governance action identifier            |
/// | CHAIN           |                                2 | Chain identifier                        |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | program_id      |                               32 | Program ID of the program to be invoked |
/// | accounts_length |                                2 | Number of accounts                      |
/// | accounts        | `accounts_length` * (32 + 1 + 1) | Accounts to be passed to the program    |
/// | data_length     |                                2 | Length of the data                      |
/// | data            |                    `data_length` | Data to be passed to the program        |
///
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GovernanceMessage {
    pub program_id: Pubkey,
    pub accounts: Vec<Acc>,
    pub data: Vec<u8>,
}

impl GovernanceMessage {
    // "GeneralPurposeGovernance" (left padded)
    const MODULE: [u8; 32] = [
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x47, 0x65, 0x6E, 0x65, 0x72, 0x61, 0x6C,
        0x50, 0x75, 0x72, 0x70, 0x6F, 0x73, 0x65, 0x47, 0x6F, 0x76, 0x65, 0x72, 0x6E, 0x61, 0x6E,
        0x63, 0x65,
    ];
}

#[test]
fn test_governance_module() {
    let s = "GeneralPurposeGovernance";
    let mut module = [0; 32];
    module[32 - s.len()..].copy_from_slice(s.as_bytes());
    assert_eq!(module, GovernanceMessage::MODULE);
}

impl AnchorDeserialize for GovernanceMessage {
    fn deserialize_reader<R: io::Read>(reader: &mut R) -> io::Result<Self> {
        Readable::read(reader)
    }
}

impl AnchorSerialize for GovernanceMessage {
    fn serialize<W: io::Write>(&self, writer: &mut W) -> io::Result<()> {
        Writeable::write(self, writer)
    }
}

impl Readable for GovernanceMessage {
    const SIZE: Option<usize> = None;

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        let module: [u8; 32] = Readable::read(reader)?;
        if module != Self::MODULE {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid GovernanceMessage module",
            ));
        }
        let action: GovernanceAction = Readable::read(reader)?;
        if action != GovernanceAction::SolanaInstruction {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid GovernanceAction",
            ));
        }
        let chain: u16 = Readable::read(reader)?;
        if Chain::from(chain) != Chain::Solana {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid GovernanceMessage chain",
            ));
        }

        let program_id: Pubkey = Pubkey::new_from_array(Readable::read(reader)?);
        let accounts_len: u16 = Readable::read(reader)?;
        let mut accounts = Vec::with_capacity(accounts_len as usize);
        for _ in 0..accounts_len {
            let pubkey: [u8; 32] = Readable::read(reader)?;
            let is_signer: bool = Readable::read(reader)?;
            let is_writable: bool = Readable::read(reader)?;
            accounts.push(Acc {
                pubkey: Pubkey::new_from_array(pubkey),
                is_signer,
                is_writable,
            });
        }
        let data_len: u16 = Readable::read(reader)?;
        let mut data = vec![0; data_len as usize];
        reader.read_exact(&mut data)?;

        Ok(GovernanceMessage {
            program_id,
            accounts,
            data,
        })
    }
}

impl Writeable for GovernanceMessage {
    fn written_size(&self) -> usize {
        Self::MODULE.len()
        + GovernanceAction::SIZE.unwrap() // action
        + u16::SIZE.unwrap() // chain
        + <[u8; 32]>::SIZE.unwrap() // program_id
        + u16::SIZE.unwrap() // accounts_len
        + self.accounts.iter()  // accounts
          .map(|_| 32 + 1 + 1).sum::<usize>()
        + u16::SIZE.unwrap() // data_len
        + self.data.len() // data
    }

    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        let GovernanceMessage {
            program_id,
            accounts,
            data,
        } = self;

        Self::MODULE.write(writer)?;
        GovernanceAction::SolanaInstruction.write(writer)?;
        u16::from(Chain::Solana).write(writer)?;
        program_id.to_bytes().write(writer)?;
        (accounts.len() as u16).write(writer)?;
        for acc in accounts {
            acc.pubkey.to_bytes().write(writer)?;
            acc.is_signer.write(writer)?;
            acc.is_writable.write(writer)?;
        }
        (data.len() as u16).write(writer)?;
        writer.write_all(data)
    }
}

#[test]
fn test_governance_message_serde() {
    let program_id = Pubkey::new_unique();
    let accounts = vec![
        Acc {
            pubkey: Pubkey::new_unique(),
            is_signer: true,
            is_writable: true,
        },
        Acc {
            pubkey: Pubkey::new_unique(),
            is_signer: false,
            is_writable: true,
        },
    ];
    let data = vec![1, 2, 3, 4, 5];
    let msg = GovernanceMessage {
        program_id,
        accounts,
        data,
    };

    let mut buf = Vec::new();
    msg.serialize(&mut buf).unwrap();

    let msg2 = GovernanceMessage::deserialize(&mut buf.as_slice()).unwrap();
    assert_eq!(msg, msg2);
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GovernanceAction {
    Undefined,
    EvmInstruction,
    SolanaInstruction,
}

impl Readable for GovernanceAction {
    const SIZE: Option<usize> = Some(1);

    fn read<R>(reader: &mut R) -> io::Result<Self>
    where
        Self: Sized,
        R: io::Read,
    {
        match Readable::read(reader)? {
            0 => Ok(GovernanceAction::Undefined),
            1 => Ok(GovernanceAction::EvmInstruction),
            2 => Ok(GovernanceAction::SolanaInstruction),
            _ => Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid GovernanceAction",
            )),
        }
    }
}

impl Writeable for GovernanceAction {
    fn written_size(&self) -> usize {
        Self::SIZE.unwrap()
    }

    fn write<W>(&self, writer: &mut W) -> io::Result<()>
    where
        W: io::Write,
    {
        match self {
            GovernanceAction::Undefined => Ok(()),
            GovernanceAction::EvmInstruction => 1.write(writer),
            GovernanceAction::SolanaInstruction => 2.write(writer),
        }
    }
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
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug, PartialEq, Eq)]
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

    ctx.accounts.replay.set_inner(ReplayProtection {
        bump: ctx.bumps.replay,
    });

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
