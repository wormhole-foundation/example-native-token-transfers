use anchor_lang::prelude::*;

use ntt_messages::{
    chain_id::ChainId,
    ntt::NativeTokenTransfer,
    transceiver::{TransceiverMessage, TransceiverMessageData},
    transceivers::wormhole::WormholeTransceiver,
};
use wormhole_anchor_sdk::wormhole::PostedVaa;
use wormhole_io::TypePrefixedPayload;

use crate::{
    config::*, error::NTTError, messages::ValidatedTransceiverMessage,
    transceivers::accounts::peer::TransceiverPeer,
};

pub trait TargetedMessage {
    fn to_chain(&self) -> ChainId;
}

impl TargetedMessage for NativeTokenTransfer {
    fn to_chain(&self) -> ChainId {
        self.to_chain
    }
}

#[cfg(not(feature = "idl-build"))]
#[derive(Accounts)]
#[repr(transparent)]
pub struct ReceiveMessageNativeTokenTransfer<'info> {
    pub inner: ReceiveMessage<'info, NativeTokenTransfer>,
}

#[cfg(feature = "idl-build")]
pub type ReceiveMessageNativeTokenTransfer<'info> = ReceiveMessage<'info, NativeTokenTransfer>;

#[cfg(feature = "idl-build")]
pub mod __client_accounts_receive_message_native_token_transfer {}

#[derive(Accounts)]
pub struct ReceiveMessage<
    'info,
    A: Clone + AnchorDeserialize + AnchorSerialize + Space + TypePrefixedPayload + TargetedMessage,
> {
    #[account(mut)]
    pub payer: Signer<'info>,

    // NOTE: this works when the contract is paused
    pub config: Account<'info, Config>,

    #[account(
        seeds = [TransceiverPeer::SEED_PREFIX, vaa.emitter_chain().to_be_bytes().as_ref()],
        constraint = peer.address == *vaa.emitter_address() @ NTTError::InvalidTransceiverPeer,
        bump = peer.bump,
    )]
    pub peer: Account<'info, TransceiverPeer>,

    #[account(
        // check that the messages is targeted to this chain
        constraint = vaa.message().ntt_manager_payload.payload.to_chain() == config.chain_id @ NTTError::InvalidChainId,
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
    )]
    pub vaa: Account<'info, PostedVaa<TransceiverMessage<WormholeTransceiver, A>>>,

    #[account(
        init,
        payer = payer,
        space = 8 + ValidatedTransceiverMessage::<TransceiverMessageData<A>>::INIT_SPACE,
        seeds = [
            ValidatedTransceiverMessage::<TransceiverMessageData<A>>::SEED_PREFIX,
            vaa.emitter_chain().to_be_bytes().as_ref(),
            vaa.message().ntt_manager_payload.id.as_ref(),
        ],
        bump,
    )]
    // NOTE: in order to handle multiple transceivers, we can just augment the
    // inbox item transfer struct with a bitmap storing which transceivers have
    // attested to the transfer. Then we only release it if there's quorum.
    // We would need to maybe_init this account in that case.
    pub transceiver_message: Account<'info, ValidatedTransceiverMessage<A>>,

    pub system_program: Program<'info, System>,
}

pub fn receive_message<A>(ctx: Context<ReceiveMessage<A>>) -> Result<()>
where
    A: Clone + AnchorDeserialize + AnchorSerialize + Space + TypePrefixedPayload + TargetedMessage,
{
    let message = ctx.accounts.vaa.message().message_data.clone();
    let chain_id = ctx.accounts.vaa.emitter_chain();
    ctx.accounts
        .transceiver_message
        .set_inner(ValidatedTransceiverMessage {
            from_chain: ChainId { id: chain_id },
            message,
        });

    Ok(())
}
