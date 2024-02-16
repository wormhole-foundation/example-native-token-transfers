use anchor_lang::prelude::*;
use anchor_spl::token_interface;

use crate::{
    bitmap::Bitmap,
    chain_id::ChainId,
    clock::current_timestamp,
    config::*,
    error::NTTError,
    normalized_amount::NormalizedAmount,
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
    pub from: InterfaceAccount<'info, token_interface::TokenAccount>,

    /// authority to burn the tokens (owner)
    /// CHECK: this is checked by the token program
    pub from_authority: Signer<'info>,

    pub token_program: Interface<'info, token_interface::TokenInterface>,

    #[account(
        mut,
        seeds = [crate::sequence::Sequence::SEED_PREFIX],
        bump = seq.bump,
    )]
    pub seq: Account<'info, crate::sequence::Sequence>,

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
    // NOTE: it would be nice to put this into `common`, but that way we don't
    // have access to the instruction args
    pub inbox_rate_limit: Account<'info, InboxRateLimit>,
}

// TODO: fees for relaying?
pub fn transfer_burn(ctx: Context<TransferBurn>, args: TransferArgs) -> Result<()> {
    let accs = ctx.accounts;
    let TransferArgs {
        amount,
        recipient_chain,
        recipient_address,
        should_queue,
    } = args;

    let amount = NormalizedAmount::normalize(amount, accs.common.mint.decimals);

    match accs.common.config.mode {
        Mode::Burning => token_interface::burn(
            CpiContext::new(
                accs.common.token_program.to_account_info(),
                token_interface::Burn {
                    mint: accs.common.mint.to_account_info(),
                    from: accs.common.from.to_account_info(),
                    authority: accs.common.from_authority.to_account_info(),
                },
            ),
            // TODO: should we revert if we have dust?
            amount.denormalize(accs.common.mint.decimals),
        )?,
        Mode::Locking => return Err(NTTError::InvalidMode.into()),
    }

    insert_into_outbox(
        &mut accs.common,
        &mut accs.inbox_rate_limit,
        amount,
        recipient_chain,
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
    // NOTE: it would be nice to put this into `common`, but that way we don't
    // have access to the instruction args
    pub inbox_rate_limit: Account<'info, InboxRateLimit>,

    #[account(
        seeds = [b"token_authority"],
        bump,
    )]
    pub token_authority: AccountInfo<'info>,

    #[account(
        mut,
        token::mint = common.mint,
        token::authority = token_authority,
    )]
    pub custody: InterfaceAccount<'info, token_interface::TokenAccount>,
}

// TODO: fees for relaying?
// TODO: factor out common bits
pub fn transfer_lock(ctx: Context<TransferLock>, args: TransferArgs) -> Result<()> {
    let accs = ctx.accounts;
    let TransferArgs {
        amount,
        recipient_chain,
        recipient_address,
        should_queue,
    } = args;

    let amount = NormalizedAmount::normalize(amount, accs.common.mint.decimals);

    match accs.common.config.mode {
        Mode::Burning => return Err(NTTError::InvalidMode.into()),
        Mode::Locking => token_interface::transfer_checked(
            CpiContext::new(
                accs.common.token_program.to_account_info(),
                token_interface::TransferChecked {
                    from: accs.common.from.to_account_info(),
                    to: accs.custody.to_account_info(),
                    authority: accs.common.from_authority.to_account_info(),
                    mint: accs.common.mint.to_account_info(),
                },
            ),
            // TODO: should we revert if we have dust?
            amount.denormalize(accs.common.mint.decimals),
            accs.common.mint.decimals,
        )?,
    }

    insert_into_outbox(
        &mut accs.common,
        &mut accs.inbox_rate_limit,
        amount,
        recipient_chain,
        recipient_address,
        should_queue,
    )
}

fn insert_into_outbox(
    common: &mut Transfer<'_>,
    inbox_rate_limit: &mut InboxRateLimit,
    amount: NormalizedAmount,
    recipient_chain: ChainId,
    recipient_address: [u8; 32],
    should_queue: bool,
) -> Result<()> {
    // consume the rate limit, or delay the transfer if it's outside the limit
    let release_timestamp = match common.outbox_rate_limit.rate_limit.consume_or_delay(amount) {
        RateLimitResult::Consumed => {
            // When sending a transfer, we refill the inbound rate limit for
            // that chain the same amount (we call this "backflow")
            inbox_rate_limit.rate_limit.refill(amount);
            current_timestamp()
        }
        RateLimitResult::Delayed(release_timestamp) => {
            if !should_queue {
                return Err(NTTError::TransferExceedsRateLimit.into());
            }
            release_timestamp
        }
    };

    let sequence = common.seq.next();

    common.outbox_item.set_inner(OutboxItem {
        sequence,
        amount,
        sender: common.from_authority.key(),
        recipient_chain,
        recipient_address,
        release_timestamp,
        released: Bitmap::new(),
    });

    Ok(())
}
