#![allow(clippy::too_many_arguments)]
use anchor_lang::prelude::*;
use anchor_spl::token_interface;
use ntt_messages::{chain_id::ChainId, mode::Mode, trimmed_amount::TrimmedAmount};
use spl_token_2022::onchain;

use crate::{
    bitmap::Bitmap,
    config::*,
    error::NTTError,
    peer::NttManagerPeer,
    queue::{
        inbox::InboxRateLimit,
        outbox::{OutboxItem, OutboxRateLimit},
        rate_limit::RateLimitResult,
    },
};

// this will burn the funds and create an account that either allows sending the
// transfer immediately, or queuing up the transfer for later
#[derive(Accounts)]
pub struct Transfer<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: NotPausedConfig<'info>,

    #[account(
        mut,
        address = config.mint,
    )]
    /// CHECK: the mint address matches the config
    pub mint: InterfaceAccount<'info, token_interface::Mint>,

    #[account(
        mut,
        token::mint = mint,
    )]
    /// CHECK: the spl token program will check that the session_authority
    ///        account can spend these tokens.
    pub from: InterfaceAccount<'info, token_interface::TokenAccount>,

    pub token_program: Interface<'info, token_interface::TokenInterface>,

    #[account(
        init,
        payer = payer,
        space = 8 + OutboxItem::INIT_SPACE,
    )]
    pub outbox_item: Account<'info, OutboxItem>,

    #[account(mut)]
    pub outbox_rate_limit: Account<'info, OutboxRateLimit>,

    pub system_program: Program<'info, System>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct TransferArgs {
    pub amount: u64,
    pub recipient_chain: ChainId,
    pub recipient_address: [u8; 32],
    pub should_queue: bool,
}

impl TransferArgs {
    pub fn keccak256(&self) -> solana_program::keccak::Hash {
        let TransferArgs {
            amount,
            recipient_chain,
            recipient_address,
            should_queue,
        } = self;
        solana_program::keccak::hashv(&[
            amount.to_be_bytes().as_ref(),
            recipient_chain.id.to_be_bytes().as_ref(),
            recipient_address,
            &[u8::from(*should_queue)],
        ])
    }
}

// Burn/mint

#[derive(Accounts)]
#[instruction(args: TransferArgs)]
pub struct TransferBurn<'info> {
    pub common: Transfer<'info>,

    #[account(
        mut,
        seeds = [InboxRateLimit::SEED_PREFIX, args.recipient_chain.id.to_be_bytes().as_ref()],
        bump = inbox_rate_limit.bump,
    )]
    // NOTE: it would be nice to put these into `common`, but that way we don't
    // have access to the instruction args
    pub inbox_rate_limit: Account<'info, InboxRateLimit>,

    #[account(
        seeds = [NttManagerPeer::SEED_PREFIX, args.recipient_chain.id.to_be_bytes().as_ref()],
        bump = peer.bump,
    )]
    pub peer: Account<'info, NttManagerPeer>,

    #[account(
        seeds = [
            crate::SESSION_AUTHORITY_SEED,
            common.from.owner.as_ref(),
            args.keccak256().as_ref()
        ],
        bump,
    )]
    pub session_authority: AccountInfo<'info>,
}

pub fn transfer_burn(ctx: Context<TransferBurn>, args: TransferArgs) -> Result<()> {
    require_eq!(
        ctx.accounts.common.config.mode,
        Mode::Burning,
        NTTError::InvalidMode
    );

    let accs = ctx.accounts;
    let TransferArgs {
        mut amount,
        recipient_chain,
        recipient_address,
        should_queue,
    } = args;

    // TODO: should we revert if we have dust?
    let trimmed_amount = TrimmedAmount::remove_dust(
        &mut amount,
        accs.common.mint.decimals,
        accs.peer.token_decimals,
    )
    .map_err(NTTError::from)?;

    let before = accs.common.from.amount;

    token_interface::burn(
        CpiContext::new_with_signer(
            accs.common.token_program.to_account_info(),
            token_interface::Burn {
                mint: accs.common.mint.to_account_info(),
                from: accs.common.from.to_account_info(),
                authority: accs.session_authority.to_account_info(),
            },
            &[&[
                crate::SESSION_AUTHORITY_SEED,
                accs.common.from.owner.as_ref(),
                args.keccak256().as_ref(),
                &[ctx.bumps.session_authority],
            ]],
        ),
        amount,
    )?;

    accs.common.from.reload()?;
    let after = accs.common.from.amount;

    if after != before - amount {
        return Err(NTTError::BadAmountAfterBurn.into());
    }

    let recipient_ntt_manager = accs.peer.address;

    insert_into_outbox(
        &mut accs.common,
        &mut accs.inbox_rate_limit,
        amount,
        trimmed_amount,
        recipient_chain,
        recipient_ntt_manager,
        recipient_address,
        should_queue,
    )
}

// Lock/unlock

#[derive(Accounts)]
#[instruction(args: TransferArgs)]
pub struct TransferLock<'info> {
    pub common: Transfer<'info>,

    #[account(
        mut,
        seeds = [InboxRateLimit::SEED_PREFIX, args.recipient_chain.id.to_be_bytes().as_ref()],
        bump = inbox_rate_limit.bump,
    )]
    // NOTE: it would be nice to put these into `common`, but that way we don't
    // have access to the instruction args
    pub inbox_rate_limit: Account<'info, InboxRateLimit>,

    #[account(
        seeds = [NttManagerPeer::SEED_PREFIX, args.recipient_chain.id.to_be_bytes().as_ref()],
        bump = peer.bump,
    )]
    pub peer: Account<'info, NttManagerPeer>,

    #[account(
        seeds = [
            crate::SESSION_AUTHORITY_SEED,
            common.from.owner.as_ref(),
            args.keccak256().as_ref()
        ],
        bump,
    )]
    pub session_authority: AccountInfo<'info>,

    #[account(
        mut,
        address = common.config.custody
    )]
    pub custody: InterfaceAccount<'info, token_interface::TokenAccount>,
}

pub fn transfer_lock<'info>(
    ctx: Context<'_, '_, '_, 'info, TransferLock<'info>>,
    args: TransferArgs,
) -> Result<()> {
    require_eq!(
        ctx.accounts.common.config.mode,
        Mode::Locking,
        NTTError::InvalidMode
    );

    let accs = ctx.accounts;
    let TransferArgs {
        mut amount,
        recipient_chain,
        recipient_address,
        should_queue,
    } = args;

    // TODO: should we revert if we have dust?
    let trimmed_amount = TrimmedAmount::remove_dust(
        &mut amount,
        accs.common.mint.decimals,
        accs.peer.token_decimals,
    )
    .map_err(NTTError::from)?;

    let before = accs.custody.amount;

    onchain::invoke_transfer_checked(
        &accs.common.token_program.key(),
        accs.common.from.to_account_info(),
        accs.common.mint.to_account_info(),
        accs.custody.to_account_info(),
        accs.session_authority.to_account_info(),
        ctx.remaining_accounts,
        amount,
        accs.common.mint.decimals,
        &[&[
            crate::SESSION_AUTHORITY_SEED,
            accs.common.from.owner.as_ref(),
            args.keccak256().as_ref(),
            &[ctx.bumps.session_authority],
        ]],
    )?;

    accs.custody.reload()?;
    let after = accs.custody.amount;

    // NOTE: we currently do not support tokens with fees. Support could be
    // added, but it would require the client to calculate the amount _before_
    // paying fees that results in an amount that can safely be trimmed.
    // Otherwise, if the amount after paying fees has dust, then that amount
    // would be lost.
    // To support fee tokens, we would first transfer the amount, _then_ assert
    // that the resulting amount has no dust (instead of removing dust before
    // the transfer like we do now).
    if after != before + amount {
        return Err(NTTError::BadAmountAfterTransfer.into());
    }

    let recipient_ntt_manager = accs.peer.address;

    insert_into_outbox(
        &mut accs.common,
        &mut accs.inbox_rate_limit,
        amount,
        trimmed_amount,
        recipient_chain,
        recipient_ntt_manager,
        recipient_address,
        should_queue,
    )
}

fn insert_into_outbox(
    common: &mut Transfer<'_>,
    inbox_rate_limit: &mut InboxRateLimit,
    amount: u64,
    trimmed_amount: TrimmedAmount,
    recipient_chain: ChainId,
    recipient_ntt_manager: [u8; 32],
    recipient_address: [u8; 32],
    should_queue: bool,
) -> Result<()> {
    // consume the rate limit, or delay the transfer if it's outside the limit
    let release_timestamp = match common.outbox_rate_limit.rate_limit.consume_or_delay(amount) {
        RateLimitResult::Consumed(now) => {
            // When sending a transfer, we refill the inbound rate limit for
            // that chain the same amount (we call this "backflow")
            inbox_rate_limit.rate_limit.refill(now, amount);
            now
        }
        RateLimitResult::Delayed(release_timestamp) => {
            if !should_queue {
                return Err(NTTError::TransferExceedsRateLimit.into());
            }
            release_timestamp
        }
    };

    common.outbox_item.set_inner(OutboxItem {
        amount: trimmed_amount,
        sender: common.from.owner,
        recipient_chain,
        recipient_ntt_manager,
        recipient_address,
        release_timestamp,
        released: Bitmap::new(),
    });

    Ok(())
}
