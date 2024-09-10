use anchor_lang::prelude::*;
use anchor_spl::token_interface;
use ntt_messages::{ntt::NativeTokenTransfer, ntt_manager::NttManagerMessage};

use crate::{
    bitmap::Bitmap,
    config::*,
    error::NTTError,
    messages::ValidatedTransceiverMessage,
    peer::NttManagerPeer,
    queue::{
        inbox::{InboxItem, InboxRateLimit, ReleaseStatus},
        outbox::OutboxRateLimit,
        rate_limit::RateLimitResult,
    },
    registered_transceiver::*,
};

#[derive(Accounts)]
pub struct Redeem<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    // NOTE: this works when the contract is paused
    #[account(
        constraint = config.threshold > 0 @ NTTError::ZeroThreshold,
    )]
    pub config: Account<'info, Config>,

    #[account(
        seeds = [NttManagerPeer::SEED_PREFIX, transceiver_message.from_chain.id.to_be_bytes().as_ref()],
        constraint = peer.address == transceiver_message.message.source_ntt_manager @ NTTError::InvalidNttManagerPeer,
        bump = peer.bump,
    )]
    pub peer: Account<'info, NttManagerPeer>,

    #[account(
        // check that the message is targeted to this chain
        constraint = transceiver_message.message.ntt_manager_payload.payload.to_chain == config.chain_id @ NTTError::InvalidChainId,
        // check that we're the intended recipient
        constraint = transceiver_message.message.recipient_ntt_manager == crate::ID.to_bytes() @ NTTError::InvalidRecipientNttManager,
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
        owner = transceiver.transceiver_address,
    )]
    pub transceiver_message: Account<'info, ValidatedTransceiverMessage<NativeTokenTransfer>>,

    #[account(
        constraint = config.enabled_transceivers.get(transceiver.id)? @ NTTError::DisabledTransceiver
    )]
    pub transceiver: Account<'info, RegisteredTransceiver>,

    #[account(
        constraint = mint.key() == config.mint
    )]
    pub mint: InterfaceAccount<'info, token_interface::Mint>,

    #[account(
        init_if_needed,
        payer = payer,
        space = 8 + InboxItem::INIT_SPACE,
        seeds = [
            InboxItem::SEED_PREFIX,
            transceiver_message.message.ntt_manager_payload.keccak256(
                transceiver_message.from_chain
            ).as_ref(),
        ],
        bump,
    )]
    /// NOTE: This account is content-addressed (PDA seeded by the message hash).
    /// This is because in a multi-transceiver configuration, the different
    /// transceivers "vote" on messages (by delivering them). By making the inbox
    /// items content-addressed, we can ensure that disagreeing votes don't
    /// interfere with each other.
    /// CHECK: init_if_needed is used here to allow for allocation and for voiting.
    /// On the first call to [`redeem()`], [`InboxItem`] will be allocated and initialized with
    /// default values.
    /// On subsequent calls, we want to modify the `InboxItem` by "voting" on it. Therefore the
    /// program should not fail which would occur when using the `init` constraint.
    /// The [`InboxItem::init`] field is used to guard against malicious or accidental modification
    /// InboxItem fields that should remain constant.
    pub inbox_item: Account<'info, InboxItem>,

    #[account(
        mut,
        seeds = [
            InboxRateLimit::SEED_PREFIX,
            transceiver_message.from_chain.id.to_be_bytes().as_ref(),
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

    let message: NttManagerMessage<NativeTokenTransfer> =
        accs.transceiver_message.message.ntt_manager_payload.clone();

    // Calculate the scaled amount based on the appropriate decimal encoding for the token.
    // Return an error if the resulting amount overflows.
    // Ideally this state should never be reached: the sender should avoid sending invalid
    // amounts when they would cause an error on the receiver.
    let amount = message
        .payload
        .amount
        .untrim(accs.mint.decimals)
        .map_err(NTTError::from)?;

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
    accs.inbox_item.votes.set(accs.transceiver.id, true)?;

    if accs
        .inbox_item
        .votes
        .count_enabled_votes(accs.config.enabled_transceivers)
        < accs.config.threshold
    {
        return Ok(());
    }

    let release_timestamp = match accs.inbox_rate_limit.rate_limit.consume_or_delay(amount) {
        RateLimitResult::Consumed(now) => {
            // When receiving a transfer, we refill the outbound rate limit with
            // the same amount (we call this "backflow")
            accs.outbox_rate_limit.rate_limit.refill(now, amount);
            now
        }
        RateLimitResult::Delayed(release_timestamp) => release_timestamp,
    };

    accs.inbox_item.release_after(release_timestamp)?;

    Ok(())
}
