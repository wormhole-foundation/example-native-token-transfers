use anchor_lang::prelude::*;

use wormhole_anchor_sdk::wormhole::PostedVaa;

use crate::{
    config::*,
    error::NTTError,
    messages::{EndpointMessage, ManagerMessage, NativeTokenTransfer, WormholeEndpoint},
    queue::inbox::{InboundRateLimit, InboxItem},
    sibling::Sibling,
};

#[derive(Accounts)]
pub struct Redeem<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    pub config: NotPausedConfig<'info>,

    #[account(
        seeds = [Sibling::SEED_PREFIX, vaa.emitter_chain().to_be_bytes().as_ref()],
        constraint = sibling.address == *vaa.emitter_address() @ NTTError::InvalidSibling,
        bump = sibling.bump,
    )]
    pub sibling: Account<'info, Sibling>,

    #[account(
        // check that the VAA's emitter agrees with what's in the message
        constraint = vaa.emitter_chain() == vaa.message().manager_payload.chain_id.id @ NTTError::InvalidChainId,
        // check that the messages is targeted to this chain
        constraint = vaa.message().manager_payload.payload.to_chain == config.chain_id @ NTTError::InvalidChainId,
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
    )]
    pub vaa: Account<'info, PostedVaa<EndpointMessage<WormholeEndpoint, NativeTokenTransfer>>>,

    #[account(
        init,
        payer = payer,
        space = 8 + InboxItem::INIT_SPACE,
        seeds = [
            InboxItem::SEED_PREFIX,
            vaa.message().manager_payload.chain_id.id.to_be_bytes().as_ref(),
            vaa.message().manager_payload.sequence.to_be_bytes().as_ref(),
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
            InboundRateLimit::SEED_PREFIX,
            vaa.emitter_chain().to_be_bytes().as_ref()
        ],
        bump,
    )]
    pub rate_limit: Account<'info, InboundRateLimit>,

    pub system_program: Program<'info, System>,
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct RedeemArgs {}

pub fn redeem(ctx: Context<Redeem>, _args: RedeemArgs) -> Result<()> {
    let accs = ctx.accounts;

    let message: ManagerMessage<NativeTokenTransfer> = accs.vaa.message().manager_payload.clone();

    let amount = message.payload.amount;
    let recipient_address =
        Pubkey::try_from(message.payload.to).map_err(|_| NTTError::InvalidRecipientAddress)?;

    let release_timestamp = accs.rate_limit.rate_limit.consume_or_delay(amount);

    accs.inbox_item.set_inner(InboxItem {
        bump: ctx.bumps.inbox_item,
        amount,
        recipient_address,
        release_timestamp,
        released: false,
    });

    Ok(())
}
