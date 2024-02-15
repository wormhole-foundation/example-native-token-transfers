use anchor_lang::prelude::*;

use wormhole_anchor_sdk::wormhole::PostedVaa;

use crate::{
    chain_id::ChainId,
    config::*,
    endpoints::{accounts::sibling::EndpointSibling, wormhole::messages::WormholeEndpoint},
    error::NTTError,
    messages::{
        EndpointMessage, EndpointMessageData, NativeTokenTransfer, ValidatedEndpointMessage,
    },
};

#[derive(Accounts)]
pub struct ReceiveMessage<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    // NOTE: this works when the contract is paused
    pub config: Account<'info, Config>,

    #[account(
        seeds = [EndpointSibling::SEED_PREFIX, vaa.emitter_chain().to_be_bytes().as_ref()],
        constraint = sibling.address == *vaa.emitter_address() @ NTTError::InvalidEndpointSibling,
        bump = sibling.bump,
    )]
    pub sibling: Account<'info, EndpointSibling>,

    #[account(
        // check that the messages is targeted to this chain
        constraint = vaa.message().manager_payload.payload.to_chain == config.chain_id @ NTTError::InvalidChainId,
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
    )]
    pub vaa: Account<'info, PostedVaa<EndpointMessage<WormholeEndpoint, NativeTokenTransfer>>>,

    #[account(
        init,
        payer = payer,
        space = 8 + ValidatedEndpointMessage::<EndpointMessageData<NativeTokenTransfer>>::INIT_SPACE,
        seeds = [
            ValidatedEndpointMessage::<EndpointMessageData<NativeTokenTransfer>>::SEED_PREFIX,
            vaa.emitter_chain().to_be_bytes().as_ref(),
            vaa.message().manager_payload.sequence.to_be_bytes().as_ref(),
        ],
        bump,
    )]
    // NOTE: in order to handle multiple endpoints, we can just augment the
    // inbox item transfer struct with a bitmap storing which endpoints have
    // attested to the transfer. Then we only release it if there's quorum.
    // We would need to maybe_init this account in that case.
    pub endpoint_message: Account<'info, ValidatedEndpointMessage<NativeTokenTransfer>>,

    pub system_program: Program<'info, System>,
}

pub fn receive_message(ctx: Context<ReceiveMessage>) -> Result<()> {
    let message = ctx.accounts.vaa.message().message_data.clone();
    let chain_id = ctx.accounts.vaa.emitter_chain();
    ctx.accounts
        .endpoint_message
        .set_inner(ValidatedEndpointMessage {
            from_chain: ChainId { id: chain_id },
            message,
        });

    Ok(())
}
