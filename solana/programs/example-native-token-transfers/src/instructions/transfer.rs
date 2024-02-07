use anchor_lang::prelude::*;
use anchor_spl::token_interface;

use crate::{
    chain_id::ChainId,
    config::Mode,
    normalized_amount::NormalizedAmount,
    queue::outbox::{OutboxItem, OutboxRateLimit},
};

// this will burn the funds and create an account that either allows sending the
// transfer immediately, or queuing up the transfer for later
#[derive(Accounts)]
pub struct Transfer<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: Account<'info, crate::config::Config>,

    #[account(
        mut,
        address = config.mint,
    )]
    /// CHECK: the mint address matches the config
    pub mint: InterfaceAccount<'info, token_interface::Mint>,

    #[account(
        mut,
        token::mint = config.mint,
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
        // TODO: this creates a race condition
        // when two people try to send a transfer at the same time
        // only one of them can claim the sequence number.
        // Not sure if there's a way around this, the PDA has to be seeded by
        // something unique to this transfer, so I think it has to include the
        // sequence number (everything else can be the same)
        seeds = [OutboxItem::SEED_PREFIX, seq.sequence.to_be_bytes().as_ref()],
        bump,
    )]
    pub outbox_item: Account<'info, OutboxItem>,

    #[account(mut)]
    pub rate_limit: Account<'info, OutboxRateLimit>,

    pub system_program: Program<'info, System>,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct TransferArgs {
    pub amount: u64,
    pub recipient_chain: ChainId,
    pub recipient_address: Vec<u8>,
}

// TODO: fees for relaying?
pub fn transfer(ctx: Context<Transfer>, args: TransferArgs) -> Result<()> {
    let accs = ctx.accounts;
    let TransferArgs {
        amount,
        recipient_chain,
        recipient_address,
    } = args;

    let amount = NormalizedAmount::normalize(amount, accs.mint.decimals);

    match accs.config.mode {
        Mode::Burning => token_interface::burn(
            CpiContext::new(
                accs.token_program.to_account_info(),
                token_interface::Burn {
                    mint: accs.mint.to_account_info(),
                    from: accs.from.to_account_info(),
                    authority: accs.from_authority.to_account_info(),
                },
            ),
            // TODO: should we revert if we have dust?
            amount.denormalize(accs.mint.decimals),
        )?,

        // TODO: implement locking mode. it will require a custody account.
        // we could take it as optional, and just ignore it in burning mode.
        // Alternatively we could do conditional compilation (feature flags), but
        // that would complicate testing and leak more into the interface.
        // Another option is to introduce a different instruction for locking
        // and burning, and just error if the wrong one is used. Again, that leaks
        // into the client interface.
        Mode::Locking => todo!(),
    }

    // consume the rate limit, or delay the transfer if it's outside the limit
    let release_timestamp = accs.rate_limit.rate_limit.consume_or_delay(amount);

    let sequence = accs.seq.next();

    accs.outbox_item.set_inner(OutboxItem {
        bump: ctx.bumps.outbox_item,
        sequence,
        amount,
        recipient_chain,
        recipient_address,
        release_timestamp,
        released: false,
    });

    Ok(())
}
