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
    pub peer: Account<'info, NttManagerPeer>,

    #[account(
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
        owner = transceiver.transceiver_address
    )]
    // pub transceiver_message: Account<'info, ValidatedTransceiverMessage<NativeTokenTransfer>>,
    pub transceiver_message: UncheckedAccount<'info>,

    #[account(
        constraint = config.enabled_transceivers.get(transceiver.id)? @ NTTError::DisabledTransceiver
    )]
    pub transceiver: Account<'info, RegisteredTransceiver>,

    #[account(
        constraint = mint.key() == config.mint
    )]
    pub mint: InterfaceAccount<'info, token_interface::Mint>,

    #[account(
        // init_if_needed,
        // payer = payer,
        // space = 8 + InboxItem::INIT_SPACE,
        // seeds = [
        //     InboxItem::SEED_PREFIX,
        //     transceiver_message.message.ntt_manager_payload.keccak256(
        //         transceiver_message.from_chain
        //     ).as_ref(),
        // ],
        // bump,
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
    pub inbox_item: UncheckedAccount<'info>,

    #[account(mut)]
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
        seeds = [NttManagerPeer::SEED_PREFIX, ValidatedTransceiverMessage::<NativeTokenTransfer>::from_chain(&transceiver_message)?.id.to_be_bytes().as_ref()],
        constraint = peer.address == ValidatedTransceiverMessage::<NativeTokenTransfer>::message(&transceiver_message.try_borrow_data()?[..])?.source_ntt_manager() @ NTTError::InvalidNttManagerPeer,
        bump = peer.bump,
    )]
    pub config: Account<'info, Config>,

    #[account()]
    pub peer: Account<'info, NttManagerPeer>,

    #[account(
        // check that the message is targeted to this chain
        constraint = ValidatedTransceiverMessage::<NativeTokenTransfer>::message(&transceiver_message.try_borrow_data()?[..])?.ntt_manager_payload().payload.to_chain == config.chain_id @ NTTError::InvalidChainId,
        // check that we're the intended recipient
        constraint = ValidatedTransceiverMessage::<NativeTokenTransfer>::message(&transceiver_message.try_borrow_data()?[..])?.recipient_ntt_manager() == crate::ID.to_bytes() @ NTTError::InvalidRecipientNttManager,
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
        owner = transceiver.transceiver_address
    )]
    /// CHECK: `transceiver_message` has to be manually deserialized as Anchor
    /// `Account<T>` and `owner` constraints are mutually-exclusive
    pub transceiver_message: UncheckedAccount<'info>,

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
            ValidatedTransceiverMessage::<NativeTokenTransfer>::message(&transceiver_message.try_borrow_data()?[..])?.ntt_manager_payload().keccak256(
                ValidatedTransceiverMessage::<NativeTokenTransfer>::from_chain(&transceiver_message)?
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
            ValidatedTransceiverMessage::<NativeTokenTransfer>::from_chain(&transceiver_message)?.id.to_be_bytes().as_ref(),
        ],
        bump,
    )]
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
        let transceiver_message: ValidatedTransceiverMessage<NativeTokenTransfer> =
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
                &[accs.peer.bump][..],
            ],
            &crate::ID,
        )
        .map_err(|_| {
            anchor_lang::error::Error::from(anchor_lang::error::ErrorCode::ConstraintSeeds)
                .with_account_name("peer")
        })?;
        if accs.peer.key() != pda_address {
            return Err(anchor_lang::error::Error::from(
                anchor_lang::error::ErrorCode::ConstraintSeeds,
            )
            .with_account_name("peer")
            .with_pubkeys((accs.peer.key(), pda_address)));
        }
        if accs.peer.address != transceiver_message.message.source_ntt_manager {
            return Err(NTTError::InvalidNttManagerPeer.into());
        }

        // inbox item check
        let (pda_address, inbox_item_bump) = Pubkey::find_program_address(
            &[
                InboxItem::SEED_PREFIX,
                transceiver_message
                    .message
                    .ntt_manager_payload
                    .keccak256(transceiver_message.from_chain)
                    .as_ref(),
            ],
            &crate::ID,
        );
        if accs.inbox_item.key() != pda_address {
            return Err(anchor_lang::error::Error::from(
                anchor_lang::error::ErrorCode::ConstraintSeeds,
            )
            .with_account_name("inbox_item")
            .with_pubkeys((accs.inbox_item.key(), pda_address)));
        }
        let anchor_rent = Rent::get()?;
        let _inbox_item = {
            let actual_field = AsRef::<AccountInfo>::as_ref(&accs.inbox_item);
            let actual_owner = actual_field.owner;
            let space = 8 + InboxItem::INIT_SPACE;
            let pa: anchor_lang::accounts::account::Account<InboxItem> = if !true
                || actual_owner == &anchor_lang::solana_program::system_program::ID
            {
                let __current_lamports = accs.inbox_item.lamports();
                if __current_lamports == 0 {
                    let space = space;
                    let lamports = anchor_rent.minimum_balance(space);
                    let cpi_accounts = anchor_lang::system_program::CreateAccount {
                        from: accs.payer.to_account_info(),
                        to: accs.inbox_item.to_account_info(),
                    };
                    let cpi_context = anchor_lang::context::CpiContext::new(
                        accs.system_program.to_account_info(),
                        cpi_accounts,
                    );
                    anchor_lang::system_program::create_account(
                        cpi_context.with_signer(&[&[
                            InboxItem::SEED_PREFIX,
                            transceiver_message
                                .message
                                .ntt_manager_payload
                                .keccak256(transceiver_message.from_chain)
                                .as_ref(),
                            &[inbox_item_bump][..],
                        ][..]]),
                        lamports,
                        space as u64,
                        &crate::ID,
                    )?;
                } else {
                    if accs.payer.key() == accs.inbox_item.key() {
                        return Err(
                                    anchor_lang::error::Error::from(anchor_lang::error::AnchorError {
                                            error_name: anchor_lang::error::ErrorCode::TryingToInitPayerAsProgramAccount
                                                .name(),
                                            error_code_number: anchor_lang::error::ErrorCode::TryingToInitPayerAsProgramAccount
                                                .into(),
                                            error_msg: anchor_lang::error::ErrorCode::TryingToInitPayerAsProgramAccount
                                                .to_string(),
                                            error_origin: Some(
                                                anchor_lang::error::ErrorOrigin::Source(anchor_lang::error::Source {
                                                    filename: "programs/example-native-token-transfers/src/instructions/redeem.rs",
                                                    line: 19u32,
                                                }),
                                            ),
                                            compared_values: None,
                                        })
                                        .with_pubkeys((accs.payer.key(), accs.inbox_item.key())),
                                );
                    }
                    let required_lamports = anchor_rent
                        .minimum_balance(space)
                        .max(1)
                        .saturating_sub(__current_lamports);
                    if required_lamports > 0 {
                        let cpi_accounts = anchor_lang::system_program::Transfer {
                            from: accs.payer.to_account_info(),
                            to: accs.inbox_item.to_account_info(),
                        };
                        let cpi_context = anchor_lang::context::CpiContext::new(
                            accs.system_program.to_account_info(),
                            cpi_accounts,
                        );
                        anchor_lang::system_program::transfer(cpi_context, required_lamports)?;
                    }
                    let cpi_accounts = anchor_lang::system_program::Allocate {
                        account_to_allocate: accs.inbox_item.to_account_info(),
                    };
                    let cpi_context = anchor_lang::context::CpiContext::new(
                        accs.system_program.to_account_info(),
                        cpi_accounts,
                    );
                    anchor_lang::system_program::allocate(
                        cpi_context.with_signer(&[&[
                            InboxItem::SEED_PREFIX,
                            transceiver_message
                                .message
                                .ntt_manager_payload
                                .keccak256(transceiver_message.from_chain)
                                .as_ref(),
                            &[inbox_item_bump][..],
                        ][..]]),
                        space as u64,
                    )?;
                    let cpi_accounts = anchor_lang::system_program::Assign {
                        account_to_assign: accs.inbox_item.to_account_info(),
                    };
                    let cpi_context = anchor_lang::context::CpiContext::new(
                        accs.system_program.to_account_info(),
                        cpi_accounts,
                    );
                    anchor_lang::system_program::assign(
                        cpi_context.with_signer(&[&[
                            InboxItem::SEED_PREFIX,
                            transceiver_message
                                .message
                                .ntt_manager_payload
                                .keccak256(transceiver_message.from_chain)
                                .as_ref(),
                            &[inbox_item_bump][..],
                        ][..]]),
                        &crate::ID,
                    )?;
                }
                match anchor_lang::accounts::account::Account::try_from_unchecked(&accs.inbox_item)
                {
                    Ok(val) => val,
                    Err(e) => return Err(e.with_account_name("inbox_item")),
                }
            } else {
                match anchor_lang::accounts::account::Account::try_from(&accs.inbox_item) {
                    Ok(val) => val,
                    Err(e) => return Err(e.with_account_name("inbox_item")),
                }
            };
            if space != actual_field.data_len() {
                return Err(anchor_lang::error::Error::from(
                    anchor_lang::error::ErrorCode::ConstraintSpace,
                )
                .with_account_name("inbox_item")
                .with_values((space, actual_field.data_len())));
            }
            if actual_owner != &crate::ID {
                return Err(anchor_lang::error::Error::from(
                    anchor_lang::error::ErrorCode::ConstraintOwner,
                )
                .with_account_name("inbox_item")
                .with_pubkeys((*actual_owner, crate::ID)));
            }
            {
                let required_lamports = anchor_rent.minimum_balance(space);
                if pa.to_account_info().lamports() < required_lamports {
                    return Err(anchor_lang::error::Error::from(
                        anchor_lang::error::ErrorCode::ConstraintRentExempt,
                    )
                    .with_account_name("inbox_item"));
                }
            }
            pa
        };
        if !AsRef::<AccountInfo>::as_ref(&accs.inbox_item).is_writable {
            return Err(anchor_lang::error::Error::from(
                anchor_lang::error::ErrorCode::ConstraintMut,
            )
            .with_account_name("inbox_item"));
        }

        // inbox rate limit check
        let (pda_address, _bump) = Pubkey::find_program_address(
            &[
                InboxRateLimit::SEED_PREFIX,
                transceiver_message.from_chain.id.to_be_bytes().as_ref(),
            ],
            &crate::ID,
        );
        if accs.inbox_rate_limit.key() != pda_address {
            return Err(anchor_lang::error::Error::from(
                anchor_lang::error::ErrorCode::ConstraintSeeds,
            )
            .with_account_name("inbox_rate_limit")
            .with_pubkeys((accs.inbox_rate_limit.key(), pda_address)));
        }

        return Ok(Self {
            payer: accs.payer,
            config: accs.config,
            inbox_item: Account::try_from(accs.inbox_item.into())?,
            peer: accs.peer,
            transceiver_message: Account::try_from(accs.transceiver_message.into())?,
            transceiver: accs.transceiver,
            mint: accs.mint,
            inbox_rate_limit: accs.inbox_rate_limit,
            outbox_rate_limit: accs.outbox_rate_limit,
            system_program: accs.system_program,
        });
    }
}
impl<'info> Redeem<'info> {
    pub fn verify_redeem_accs(
        &self,
    ) -> Result<(&Self, ValidatedTransceiverMessage<NativeTokenTransfer>, u8)> {
        // NOTE: we don't replay protect VAAs. Instead, we replay protect
        // executing the messages themselves with the [`released`] flag.
        let transceiver_message: ValidatedTransceiverMessage<NativeTokenTransfer> =
            ValidatedTransceiverMessage::try_from(
                self.transceiver_message.clone(),
                self.transceiver.transceiver_address,
            )?;
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

        // peer checks
        let pda_address = Pubkey::create_program_address(
            &[
                NttManagerPeer::SEED_PREFIX,
                transceiver_message.from_chain.id.to_be_bytes().as_ref(),
                &[self.peer.bump][..],
            ],
            &crate::ID,
        )
        .map_err(|_| {
            anchor_lang::error::Error::from(anchor_lang::error::ErrorCode::ConstraintSeeds)
                .with_account_name("peer")
        })?;
        if self.peer.key() != pda_address {
            return Err(anchor_lang::error::Error::from(
                anchor_lang::error::ErrorCode::ConstraintSeeds,
            )
            .with_account_name("peer")
            .with_pubkeys((self.peer.key(), pda_address)));
        }
        if self.peer.address != transceiver_message.message.source_ntt_manager {
            return Err(NTTError::InvalidNttManagerPeer.into());
        }

        // inbox item check
        let (pda_address, inbox_item_bump) = Pubkey::find_program_address(
            &[
                InboxItem::SEED_PREFIX,
                transceiver_message
                    .message
                    .ntt_manager_payload
                    .keccak256(transceiver_message.from_chain)
                    .as_ref(),
            ],
            &crate::ID,
        );
        if self.inbox_item.key() != pda_address {
            return Err(anchor_lang::error::Error::from(
                anchor_lang::error::ErrorCode::ConstraintSeeds,
            )
            .with_account_name("inbox_item")
            .with_pubkeys((self.inbox_item.key(), pda_address)));
        }
        // let anchor_rent = Rent::get()?;
        // let _inbox_item = {
        //     let actual_field = AsRef::<AccountInfo>::as_ref(&inbox_item);
        //     let actual_owner = actual_field.owner;
        //     let space = 8 + InboxItem::INIT_SPACE;
        //     let pa: anchor_lang::accounts::account::Account<InboxItem> = if !true
        //         || actual_owner == &anchor_lang::solana_program::system_program::ID
        //     {
        //         let __current_lamports = inbox_item.lamports();
        //         if __current_lamports == 0 {
        //             let space = space;
        //             let lamports = anchor_rent.minimum_balance(space);
        //             let cpi_accounts = anchor_lang::system_program::CreateAccount {
        //                 from: payer.to_account_info(),
        //                 to: inbox_item.to_account_info(),
        //             };
        //             let cpi_context = anchor_lang::context::CpiContext::new(
        //                 system_program.to_account_info(),
        //                 cpi_accounts,
        //             );
        //             anchor_lang::system_program::create_account(
        //                 cpi_context.with_signer(&[&[
        //                     InboxItem::SEED_PREFIX,
        //                     transceiver_message
        //                         .message
        //                         .ntt_manager_payload
        //                         .keccak256(transceiver_message.from_chain)
        //                         .as_ref(),
        //                     &[inbox_item_bump][..],
        //                 ][..]]),
        //                 lamports,
        //                 space as u64,
        //                 &crate::ID,
        //             )?;
        //         } else {
        //             if payer.key() == inbox_item.key() {
        //                 return Err(
        //                             anchor_lang::error::Error::from(anchor_lang::error::AnchorError {
        //                                     error_name: anchor_lang::error::ErrorCode::TryingToInitPayerAsProgramAccount
        //                                         .name(),
        //                                     error_code_number: anchor_lang::error::ErrorCode::TryingToInitPayerAsProgramAccount
        //                                         .into(),
        //                                     error_msg: anchor_lang::error::ErrorCode::TryingToInitPayerAsProgramAccount
        //                                         .to_string(),
        //                                     error_origin: Some(
        //                                         anchor_lang::error::ErrorOrigin::Source(anchor_lang::error::Source {
        //                                             filename: "programs/example-native-token-transfers/src/instructions/redeem.rs",
        //                                             line: 19u32,
        //                                         }),
        //                                     ),
        //                                     compared_values: None,
        //                                 })
        //                                 .with_pubkeys((payer.key(), inbox_item.key())),
        //                         );
        //             }
        //             let required_lamports = anchor_rent
        //                 .minimum_balance(space)
        //                 .max(1)
        //                 .saturating_sub(__current_lamports);
        //             if required_lamports > 0 {
        //                 let cpi_accounts = anchor_lang::system_program::Transfer {
        //                     from: payer.to_account_info(),
        //                     to: inbox_item.to_account_info(),
        //                 };
        //                 let cpi_context = anchor_lang::context::CpiContext::new(
        //                     system_program.to_account_info(),
        //                     cpi_accounts,
        //                 );
        //                 anchor_lang::system_program::transfer(cpi_context, required_lamports)?;
        //             }
        //             let cpi_accounts = anchor_lang::system_program::Allocate {
        //                 account_to_allocate: inbox_item.to_account_info(),
        //             };
        //             let cpi_context = anchor_lang::context::CpiContext::new(
        //                 system_program.to_account_info(),
        //                 cpi_accounts,
        //             );
        //             anchor_lang::system_program::allocate(
        //                 cpi_context.with_signer(&[&[
        //                     InboxItem::SEED_PREFIX,
        //                     transceiver_message
        //                         .message
        //                         .ntt_manager_payload
        //                         .keccak256(transceiver_message.from_chain)
        //                         .as_ref(),
        //                     &[inbox_item_bump][..],
        //                 ][..]]),
        //                 space as u64,
        //             )?;
        //             let cpi_accounts = anchor_lang::system_program::Assign {
        //                 account_to_assign: inbox_item.to_account_info(),
        //             };
        //             let cpi_context = anchor_lang::context::CpiContext::new(
        //                 system_program.to_account_info(),
        //                 cpi_accounts,
        //             );
        //             anchor_lang::system_program::assign(
        //                 cpi_context.with_signer(&[&[
        //                     InboxItem::SEED_PREFIX,
        //                     transceiver_message
        //                         .message
        //                         .ntt_manager_payload
        //                         .keccak256(transceiver_message.from_chain)
        //                         .as_ref(),
        //                     &[inbox_item_bump][..],
        //                 ][..]]),
        //                 &crate::ID,
        //             )?;
        //         }
        //         match anchor_lang::accounts::account::Account::try_from_unchecked(&inbox_item) {
        //             Ok(val) => val,
        //             Err(e) => return Err(e.with_account_name("inbox_item")),
        //         }
        //     } else {
        //         match anchor_lang::accounts::account::Account::try_from(&inbox_item) {
        //             Ok(val) => val,
        //             Err(e) => return Err(e.with_account_name("inbox_item")),
        //         }
        //     };
        //     if space != actual_field.data_len() {
        //         return Err(anchor_lang::error::Error::from(
        //             anchor_lang::error::ErrorCode::ConstraintSpace,
        //         )
        //         .with_account_name("inbox_item")
        //         .with_values((space, actual_field.data_len())));
        //     }
        //     if actual_owner != &crate::ID {
        //         return Err(anchor_lang::error::Error::from(
        //             anchor_lang::error::ErrorCode::ConstraintOwner,
        //         )
        //         .with_account_name("inbox_item")
        //         .with_pubkeys((*actual_owner, crate::ID)));
        //     }
        //     {
        //         let required_lamports = anchor_rent.minimum_balance(space);
        //         if pa.to_account_info().lamports() < required_lamports {
        //             return Err(anchor_lang::error::Error::from(
        //                 anchor_lang::error::ErrorCode::ConstraintRentExempt,
        //             )
        //             .with_account_name("inbox_item"));
        //         }
        //     }
        //     pa
        // };
        // if !AsRef::<AccountInfo>::as_ref(&inbox_item).is_writable {
        //     return Err(
        //         anchor_lang::error::Error::from(anchor_lang::error::ErrorCode::ConstraintMut)
        //             .with_account_name("inbox_item"),
        //     );
        // }

        // inbox rate limit check
        let (pda_address, _bump) = Pubkey::find_program_address(
            &[
                InboxRateLimit::SEED_PREFIX,
                transceiver_message.from_chain.id.to_be_bytes().as_ref(),
            ],
            &crate::ID,
        );
        if self.inbox_rate_limit.key() != pda_address {
            return Err(anchor_lang::error::Error::from(
                anchor_lang::error::ErrorCode::ConstraintSeeds,
            )
            .with_account_name("inbox_rate_limit")
            .with_pubkeys((self.inbox_rate_limit.key(), pda_address)));
        }

        Ok((self, transceiver_message, inbox_item_bump))
    }
}

pub fn verify_redeem_accs(
    config: &Account<Config>,
    transceiver_message: &UncheckedAccount,
    transceiver: &Account<RegisteredTransceiver>,
    peer: &Account<NttManagerPeer>,
    inbox_item: &UncheckedAccount,
    inbox_rate_limit: &Account<InboxRateLimit>,
) -> Result<(ValidatedTransceiverMessage<NativeTokenTransfer>, u8)> {
    // NOTE: we don't replay protect VAAs. Instead, we replay protect
    // executing the messages themselves with the [`released`] flag.
    let transceiver_message: ValidatedTransceiverMessage<NativeTokenTransfer> =
        ValidatedTransceiverMessage::try_from(
            transceiver_message.clone(),
            transceiver.transceiver_address,
        )?;
    // check that the message is targeted to this chain
    if transceiver_message
        .message
        .ntt_manager_payload
        .payload
        .to_chain
        != config.chain_id
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
            &[peer.bump][..],
        ],
        &crate::ID,
    )
    .map_err(|_| {
        anchor_lang::error::Error::from(anchor_lang::error::ErrorCode::ConstraintSeeds)
            .with_account_name("peer")
    })?;
    if peer.key() != pda_address {
        return Err(anchor_lang::error::Error::from(
            anchor_lang::error::ErrorCode::ConstraintSeeds,
        )
        .with_account_name("peer")
        .with_pubkeys((peer.key(), pda_address)));
    }
    if peer.address != transceiver_message.message.source_ntt_manager {
        return Err(NTTError::InvalidNttManagerPeer.into());
    }

    // inbox item check
    let (pda_address, inbox_item_bump) = Pubkey::find_program_address(
        &[
            InboxItem::SEED_PREFIX,
            transceiver_message
                .message
                .ntt_manager_payload
                .keccak256(transceiver_message.from_chain)
                .as_ref(),
        ],
        &crate::ID,
    );
    if inbox_item.key() != pda_address {
        return Err(anchor_lang::error::Error::from(
            anchor_lang::error::ErrorCode::ConstraintSeeds,
        )
        .with_account_name("inbox_item")
        .with_pubkeys((inbox_item.key(), pda_address)));
    }
    // let anchor_rent = Rent::get()?;
    // let _inbox_item = {
    //     let actual_field = AsRef::<AccountInfo>::as_ref(&inbox_item);
    //     let actual_owner = actual_field.owner;
    //     let space = 8 + InboxItem::INIT_SPACE;
    //     let pa: anchor_lang::accounts::account::Account<InboxItem> = if !true
    //         || actual_owner == &anchor_lang::solana_program::system_program::ID
    //     {
    //         let __current_lamports = inbox_item.lamports();
    //         if __current_lamports == 0 {
    //             let space = space;
    //             let lamports = anchor_rent.minimum_balance(space);
    //             let cpi_accounts = anchor_lang::system_program::CreateAccount {
    //                 from: payer.to_account_info(),
    //                 to: inbox_item.to_account_info(),
    //             };
    //             let cpi_context = anchor_lang::context::CpiContext::new(
    //                 system_program.to_account_info(),
    //                 cpi_accounts,
    //             );
    //             anchor_lang::system_program::create_account(
    //                 cpi_context.with_signer(&[&[
    //                     InboxItem::SEED_PREFIX,
    //                     transceiver_message
    //                         .message
    //                         .ntt_manager_payload
    //                         .keccak256(transceiver_message.from_chain)
    //                         .as_ref(),
    //                     &[inbox_item_bump][..],
    //                 ][..]]),
    //                 lamports,
    //                 space as u64,
    //                 &crate::ID,
    //             )?;
    //         } else {
    //             if payer.key() == inbox_item.key() {
    //                 return Err(
    //                             anchor_lang::error::Error::from(anchor_lang::error::AnchorError {
    //                                     error_name: anchor_lang::error::ErrorCode::TryingToInitPayerAsProgramAccount
    //                                         .name(),
    //                                     error_code_number: anchor_lang::error::ErrorCode::TryingToInitPayerAsProgramAccount
    //                                         .into(),
    //                                     error_msg: anchor_lang::error::ErrorCode::TryingToInitPayerAsProgramAccount
    //                                         .to_string(),
    //                                     error_origin: Some(
    //                                         anchor_lang::error::ErrorOrigin::Source(anchor_lang::error::Source {
    //                                             filename: "programs/example-native-token-transfers/src/instructions/redeem.rs",
    //                                             line: 19u32,
    //                                         }),
    //                                     ),
    //                                     compared_values: None,
    //                                 })
    //                                 .with_pubkeys((payer.key(), inbox_item.key())),
    //                         );
    //             }
    //             let required_lamports = anchor_rent
    //                 .minimum_balance(space)
    //                 .max(1)
    //                 .saturating_sub(__current_lamports);
    //             if required_lamports > 0 {
    //                 let cpi_accounts = anchor_lang::system_program::Transfer {
    //                     from: payer.to_account_info(),
    //                     to: inbox_item.to_account_info(),
    //                 };
    //                 let cpi_context = anchor_lang::context::CpiContext::new(
    //                     system_program.to_account_info(),
    //                     cpi_accounts,
    //                 );
    //                 anchor_lang::system_program::transfer(cpi_context, required_lamports)?;
    //             }
    //             let cpi_accounts = anchor_lang::system_program::Allocate {
    //                 account_to_allocate: inbox_item.to_account_info(),
    //             };
    //             let cpi_context = anchor_lang::context::CpiContext::new(
    //                 system_program.to_account_info(),
    //                 cpi_accounts,
    //             );
    //             anchor_lang::system_program::allocate(
    //                 cpi_context.with_signer(&[&[
    //                     InboxItem::SEED_PREFIX,
    //                     transceiver_message
    //                         .message
    //                         .ntt_manager_payload
    //                         .keccak256(transceiver_message.from_chain)
    //                         .as_ref(),
    //                     &[inbox_item_bump][..],
    //                 ][..]]),
    //                 space as u64,
    //             )?;
    //             let cpi_accounts = anchor_lang::system_program::Assign {
    //                 account_to_assign: inbox_item.to_account_info(),
    //             };
    //             let cpi_context = anchor_lang::context::CpiContext::new(
    //                 system_program.to_account_info(),
    //                 cpi_accounts,
    //             );
    //             anchor_lang::system_program::assign(
    //                 cpi_context.with_signer(&[&[
    //                     InboxItem::SEED_PREFIX,
    //                     transceiver_message
    //                         .message
    //                         .ntt_manager_payload
    //                         .keccak256(transceiver_message.from_chain)
    //                         .as_ref(),
    //                     &[inbox_item_bump][..],
    //                 ][..]]),
    //                 &crate::ID,
    //             )?;
    //         }
    //         match anchor_lang::accounts::account::Account::try_from_unchecked(&inbox_item) {
    //             Ok(val) => val,
    //             Err(e) => return Err(e.with_account_name("inbox_item")),
    //         }
    //     } else {
    //         match anchor_lang::accounts::account::Account::try_from(&inbox_item) {
    //             Ok(val) => val,
    //             Err(e) => return Err(e.with_account_name("inbox_item")),
    //         }
    //     };
    //     if space != actual_field.data_len() {
    //         return Err(anchor_lang::error::Error::from(
    //             anchor_lang::error::ErrorCode::ConstraintSpace,
    //         )
    //         .with_account_name("inbox_item")
    //         .with_values((space, actual_field.data_len())));
    //     }
    //     if actual_owner != &crate::ID {
    //         return Err(anchor_lang::error::Error::from(
    //             anchor_lang::error::ErrorCode::ConstraintOwner,
    //         )
    //         .with_account_name("inbox_item")
    //         .with_pubkeys((*actual_owner, crate::ID)));
    //     }
    //     {
    //         let required_lamports = anchor_rent.minimum_balance(space);
    //         if pa.to_account_info().lamports() < required_lamports {
    //             return Err(anchor_lang::error::Error::from(
    //                 anchor_lang::error::ErrorCode::ConstraintRentExempt,
    //             )
    //             .with_account_name("inbox_item"));
    //         }
    //     }
    //     pa
    // };
    // if !AsRef::<AccountInfo>::as_ref(&inbox_item).is_writable {
    //     return Err(
    //         anchor_lang::error::Error::from(anchor_lang::error::ErrorCode::ConstraintMut)
    //             .with_account_name("inbox_item"),
    //     );
    // }

    // inbox rate limit check
    let (pda_address, _bump) = Pubkey::find_program_address(
        &[
            InboxRateLimit::SEED_PREFIX,
            transceiver_message.from_chain.id.to_be_bytes().as_ref(),
        ],
        &crate::ID,
    );
    if inbox_rate_limit.key() != pda_address {
        return Err(anchor_lang::error::Error::from(
            anchor_lang::error::ErrorCode::ConstraintSeeds,
        )
        .with_account_name("inbox_rate_limit")
        .with_pubkeys((inbox_rate_limit.key(), pda_address)));
    }

    Ok((transceiver_message, inbox_item_bump))
}

#[derive(AnchorDeserialize, AnchorSerialize)]
pub struct RedeemArgs {}

pub fn redeem<'info>(
    ctx: Context<'_, '_, '_, 'info, Redeem<'info>>,
    _args: RedeemArgs,
) -> Result<()> {
    // let accs = ctx.accounts;

    let transceiver_message: ValidatedTransceiverMessage<NativeTokenTransfer<Payload>> =
        ValidatedTransceiverMessage::try_from(
            &accs.transceiver_message,
            &accs.transceiver.transceiver_address,
        )?;
    let message: NttManagerMessage<NativeTokenTransfer> =
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

        inbox_item.set_inner(InboxItem {
            init: true,
            bump: inbox_item_bump,
            amount,
            recipient_address,
            release_status: ReleaseStatus::NotApproved,
            votes: Bitmap::new(),
        });
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

    let _release_timestamp = match accs.inbox_rate_limit.rate_limit.consume_or_delay(amount) {
        RateLimitResult::Consumed(now) => {
            // When receiving a transfer, we refill the outbound rate limit with
            // the same amount (we call this "backflow")
            accs.outbox_rate_limit.rate_limit.refill(now, amount);
            now
        }
        RateLimitResult::Delayed(release_timestamp) => release_timestamp,
    };

    // inbox_item.release_after(release_timestamp)?;

    Ok(())
}
