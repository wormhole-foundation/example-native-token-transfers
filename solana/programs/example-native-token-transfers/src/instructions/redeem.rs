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
    transfer::Payload,
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

    #[account()]
    /// NOTE: seeds constraint is verified manually in the `impl`
    /// as it depends on `transceiver_message` being deserialized
    pub peer: Account<'info, NttManagerPeer>,

    #[account(
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
        owner = transceiver.transceiver_address
    )]
    /// CHECK: remaining constraints are verified manually in the `impl`
    /// as it depends on `transceiver_message` being deserialized
    pub transceiver_message: UncheckedAccount<'info>,

    #[account(
        constraint = config.enabled_transceivers.get(transceiver.id)? @ NTTError::DisabledTransceiver
    )]
    pub transceiver: Account<'info, RegisteredTransceiver>,

    #[account(
        constraint = mint.key() == config.mint
    )]
    pub mint: InterfaceAccount<'info, token_interface::Mint>,

    #[account(mut)]
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
    pub inbox_item: UncheckedAccount<'info>,

    #[account(mut)]
    /// NOTE: seeds constraint is verified manually in the `impl`
    /// as it depends on `transceiver_message` being deserialized
    pub inbox_rate_limit: Account<'info, InboxRateLimit>,

    #[account(mut)]
    pub outbox_rate_limit: Account<'info, OutboxRateLimit>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct RedeemChecked<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    // NOTE: this works when the contract is paused
    #[account(
        constraint = config.threshold > 0 @ NTTError::ZeroThreshold,
    )]
    pub config: Account<'info, Config>,

    #[account()]
    pub peer: Account<'info, NttManagerPeer>,

    #[account(
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
        owner = transceiver.transceiver_address
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

    #[account(mut)]
    pub inbox_rate_limit: Account<'info, InboxRateLimit>,

    #[account(mut)]
    pub outbox_rate_limit: Account<'info, OutboxRateLimit>,

    pub system_program: Program<'info, System>,
}

impl<'info> TryFrom<Redeem<'info>> for RedeemChecked<'info> {
    type Error = error::Error;

    fn try_from(accs: Redeem<'info>) -> Result<Self> {
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
        let transceiver_message: ValidatedTransceiverMessage<NativeTokenTransfer<Payload>> =
            ValidatedTransceiverMessage::try_from(
                accs.transceiver_message.clone(),
                accs.transceiver.transceiver_address,
            )?;
        // check that the message is targeted to this chain
        if transceiver_message
            .message
            .ntt_manager_payload
            .payload
            .to_chain
            != accs.config.chain_id
        {
            return Err(NTTError::InvalidChainId.into());
        }
        // check that we're the intended recipient
        if transceiver_message.message.recipient_ntt_manager != crate::ID.to_bytes() {
            return Err(NTTError::InvalidRecipientNttManager.into());
        }

        // peer checks
        let pda_address = Pubkey::create_program_address(
            &[
                NttManagerPeer::SEED_PREFIX,
                transceiver_message.from_chain.id.to_be_bytes().as_ref(),
                &[self.peer.bump][..],
            ],
            &crate::ID,
        )
        .map_err(|_| Error::from(ErrorCode::ConstraintSeeds).with_account_name("peer"))?;
        if self.peer.key() != pda_address {
            return Err(Error::from(ErrorCode::ConstraintSeeds)
                .with_account_name("peer")
                .with_pubkeys((self.peer.key(), pda_address)));
        }
        if self.peer.address != transceiver_message.message.source_ntt_manager {
            return Err(NTTError::InvalidNttManagerPeer.into());
        }

        // check that the message is targeted to this chain
        if transceiver_message
            .message
            .ntt_manager_payload
            .payload
            .to_chain
            != self.config.chain_id
        {
            return Err(NTTError::InvalidChainId.into());
        }
        // check that we're the intended recipient
        if transceiver_message.message.recipient_ntt_manager != crate::ID.to_bytes() {
            return Err(NTTError::InvalidRecipientNttManager.into());
        }

        // inbox item checks done in init_if_needed

        // inbox rate limit checks
        let (pda_address, _bump) = Pubkey::find_program_address(
            &[
                InboxRateLimit::SEED_PREFIX,
                transceiver_message.from_chain.id.to_be_bytes().as_ref(),
            ],
            &crate::ID,
        );
        if self.inbox_rate_limit.key() != pda_address {
            return Err(Error::from(ErrorCode::ConstraintSeeds)
                .with_account_name("inbox_rate_limit")
                .with_pubkeys((self.inbox_rate_limit.key(), pda_address)));
        }

        Ok(())
    }
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct RedeemArgs {}

pub fn redeem(ctx: Context<Redeem>, _args: RedeemArgs) -> Result<()> {
    let accs = ctx.accounts;
    let transceiver_message: ValidatedTransceiverMessage<NativeTokenTransfer> =
        ValidatedTransceiverMessage::try_from(
            &accs.transceiver_message,
            &accs.transceiver.transceiver_address,
        )?;
    accs.verify_redeem_accs(&transceiver_message)?;
    let (mut inbox_item, inbox_item_bump) = InboxItem::init_if_needed(
        &accs.inbox_item,
        &transceiver_message,
        &accs.payer,
        &accs.system_program,
    )?;

    let message: NttManagerMessage<NativeTokenTransfer<Payload>> =
        transceiver_message.message.ntt_manager_payload.clone();

    // Calculate the scaled amount based on the appropriate decimal encoding for the token.
    // Return an error if the resulting amount overflows.
    // Ideally this state should never be reached: the sender should avoid sending invalid
    // amounts when they would cause an error on the receiver.
    let amount = message
        .payload
        .amount
        .untrim(accs.mint.decimals)
        .map_err(NTTError::from)?;

    if !inbox_item.init {
        let recipient_address =
            Pubkey::try_from(message.payload.to).map_err(|_| NTTError::InvalidRecipientAddress)?;

        inbox_item = InboxItem {
            init: true,
            bump: inbox_item_bump,
            amount,
            recipient_address,
            release_status: ReleaseStatus::NotApproved,
            votes: Bitmap::new(),
        };
    }

    // idempotent
    inbox_item.votes.set(accs.transceiver.id, true)?;

    if inbox_item
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

    inbox_item.release_after(release_timestamp)?;

    inbox_item.try_serialize(&mut &mut accs.inbox_item.try_borrow_mut_data()?[..])?;

    Ok(())
}
