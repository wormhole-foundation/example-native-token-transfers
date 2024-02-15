use anchor_lang::prelude::*;

use crate::{
    bitmap::Bitmap,
    clock::current_timestamp,
    config::*,
    error::NTTError,
    messages::{ManagerMessage, NativeTokenTransfer, ValidatedEndpointMessage},
    queue::{
        inbox::{InboxItem, InboxRateLimit, ReleaseStatus},
        outbox::OutboxRateLimit,
        rate_limit::RateLimitResult,
    },
    registered_endpoint::*,
    sibling::ManagerSibling,
};

#[derive(Accounts)]
pub struct Redeem<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    // NOTE: this works when the contract is paused
    pub config: Account<'info, Config>,

    #[account(
        seeds = [ManagerSibling::SEED_PREFIX, endpoint_message.from_chain.id.to_be_bytes().as_ref()],
        constraint = sibling.address == endpoint_message.message.source_manager @ NTTError::InvalidManagerSibling,
        bump = sibling.bump,
    )]
    pub sibling: Account<'info, ManagerSibling>,

    #[account(
        // check that the messages is targeted to this chain
        constraint = endpoint_message.message.manager_payload.payload.to_chain == config.chain_id @ NTTError::InvalidChainId,
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
        owner = endpoint.endpoint_address,
    )]
    pub endpoint_message: Account<'info, ValidatedEndpointMessage<NativeTokenTransfer>>,

    pub endpoint: EnabledEndpoint<'info>,

    #[account(
        init_if_needed,
        payer = payer,
        space = 8 + InboxItem::INIT_SPACE,
        seeds = [
            InboxItem::SEED_PREFIX,
            endpoint_message.from_chain.id.to_be_bytes().as_ref(),
            // TODO: use hash instead of just sequence
            endpoint_message.message.manager_payload.sequence.to_be_bytes().as_ref(),
        ],
        bump,
    )]
    // NOTE: in order to handle multiple endpoints, we can just augment the
    // inbox item transfer struct with a bitmap storing which endpoints have
    // attested to the transfer. Then we only release it if there's quorum.
    // We would need to maybe_init this account in that case.
    pub inbox_item: Account<'info, InboxItem>,

    #[account(
        mut,
        seeds = [
            InboxRateLimit::SEED_PREFIX,
            endpoint_message.from_chain.id.to_be_bytes().as_ref(),
        ],
        bump,
    )]
    pub inbox_rate_limit: Account<'info, InboxRateLimit>,

    #[account(mut)]
    pub outbox_rate_limit: Account<'info, OutboxRateLimit>,

    pub system_program: Program<'info, System>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct RedeemArgs {}

pub fn redeem(ctx: Context<Redeem>, _args: RedeemArgs) -> Result<()> {
    let accs = ctx.accounts;

    // TODO: seed PDA by content instead of sequence

    let message: ManagerMessage<NativeTokenTransfer> =
        accs.endpoint_message.message.manager_payload.clone();

    let amount = message.payload.amount;
    let amount = amount.change_decimals(accs.outbox_rate_limit.rate_limit.limit.decimals);

    if !accs.inbox_item.init {
        let recipient_address =
            Pubkey::try_from(message.payload.to).map_err(|_| NTTError::InvalidRecipientAddress)?;

        accs.inbox_item.set_inner(InboxItem {
            init: true,
            bump: ctx.bumps.inbox_item,
            amount,
            recipient_address,
            release_status: ReleaseStatus::NotApproved,
            votes: Bitmap::new(),
        });
    }

    // idempotent
    accs.inbox_item.votes.set(accs.endpoint.id, true);

    // TODO: if endpoints can be disabled, this should only cound enabled endpoints
    if accs.inbox_item.votes.count_ones() < accs.config.threshold {
        return Ok(());
    }

    let release_timestamp = match accs.inbox_rate_limit.rate_limit.consume_or_delay(amount) {
        RateLimitResult::Consumed => {
            // When receiving a transfer, we refill the outbound rate limit with
            // the same amount (we call this "backflow")
            accs.outbox_rate_limit.rate_limit.refill(amount);
            current_timestamp()
        }
        RateLimitResult::Delayed(release_timestamp) => release_timestamp,
    };

    accs.inbox_item.release_status = ReleaseStatus::ReleaseAfter(release_timestamp);

    Ok(())
}
