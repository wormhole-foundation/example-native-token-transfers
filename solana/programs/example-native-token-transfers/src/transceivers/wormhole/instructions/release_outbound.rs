use anchor_lang::prelude::*;

use ntt_messages::{
    ntt::NativeTokenTransfer, ntt_manager::NttManagerMessage, transceiver::TransceiverMessage,
    transceivers::wormhole::WormholeTransceiver,
};
use wormhole_io::TypePrefixedPayload;

use crate::{
    config::*,
    error::NTTError,
    queue::outbox::{OutboxItem, TokenTransferOutbox},
    registered_transceiver::*,
    transceivers::wormhole::accounts::*,
};

#[cfg(not(feature = "idl-build"))]
#[derive(Accounts)]
#[repr(transparent)]
pub struct ReleaseOutboundNativeTokenTransfer<'info> {
    pub inner: ReleaseOutbound<'info, NativeTokenTransfer>,
}

pub trait IntoMessage: Clone + AnchorDeserialize + AnchorSerialize + Space {
    type OutboxItemType: Clone + AnchorSerialize + AnchorDeserialize + Space;
    fn into_message(accs: &ReleaseOutbound<Self>) -> Self;
}

impl IntoMessage for NativeTokenTransfer {
    type OutboxItemType = TokenTransferOutbox;
    fn into_message(accs: &ReleaseOutbound<Self>) -> Self {
        NativeTokenTransfer {
            amount: accs.outbox_item.payload.amount,
            source_token: accs.config.mint.to_bytes(),
            to: accs.outbox_item.payload.recipient_address,
            to_chain: accs.outbox_item.recipient_chain,
        }
    }
}

#[cfg(feature = "idl-build")]
pub type ReleaseOutboundNativeTokenTransfer<'info> = ReleaseOutbound<'info, NativeTokenTransfer>;

#[cfg(feature = "idl-build")]
pub mod __client_accounts_release_outbound_native_token_transfer {}

#[derive(Accounts)]
pub struct ReleaseOutbound<'info, A: IntoMessage> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: NotPausedConfig<'info>,

    #[account(
        mut,
        constraint = !outbox_item.released.get(transceiver.id) @ NTTError::MessageAlreadySent,
    )]
    pub outbox_item: Account<'info, OutboxItem<A::OutboxItemType>>,

    #[account(
        constraint = transceiver.transceiver_address == crate::ID,
        constraint = config.enabled_transceivers.get(transceiver.id) @ NTTError::DisabledTransceiver
    )]
    pub transceiver: Account<'info, RegisteredTransceiver>,

    #[account(
        mut,
        seeds = [b"message", outbox_item.key().as_ref()],
        bump,
    )]
    /// CHECK: initialized and written to by wormhole core bridge
    pub wormhole_message: UncheckedAccount<'info>,

    #[account(
        seeds = [b"emitter"],
        bump
    )]
    // TODO: do we want to put anything in here?
    /// CHECK: wormhole uses this as the emitter address
    pub emitter: UncheckedAccount<'info>,

    pub wormhole: WormholeAccounts<'info>,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct ReleaseOutboundArgs {
    pub revert_on_delay: bool,
}

pub fn release_outbound<A>(
    ctx: Context<ReleaseOutbound<A>>,
    args: ReleaseOutboundArgs,
) -> Result<()>
where
    A: IntoMessage + TypePrefixedPayload,
{
    let accs = ctx.accounts;
    let released = accs.outbox_item.try_release(accs.transceiver.id)?;

    if !released {
        if args.revert_on_delay {
            return Err(NTTError::CantReleaseYet.into());
        } else {
            return Ok(());
        }
    }

    assert!(accs.outbox_item.released.get(accs.transceiver.id));
    let message: TransceiverMessage<WormholeTransceiver, A> = TransceiverMessage::new(
        // TODO: should we just put the ntt id here statically?
        accs.outbox_item.to_account_info().owner.to_bytes(),
        accs.outbox_item.recipient_ntt_manager,
        NttManagerMessage {
            id: accs.outbox_item.key().to_bytes(),
            sender: accs.outbox_item.sender.to_bytes(),
            payload: A::into_message(accs),
        },
        vec![],
    );

    post_message(
        &accs.wormhole,
        accs.payer.to_account_info(),
        accs.wormhole_message.to_account_info(),
        accs.emitter.to_account_info(),
        ctx.bumps.emitter,
        &message,
        &[&[
            b"message",
            accs.outbox_item.key().as_ref(),
            &[ctx.bumps.wormhole_message],
        ]],
    )?;

    Ok(())
}
