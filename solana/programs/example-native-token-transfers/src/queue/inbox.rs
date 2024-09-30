use std::ops::{Deref, DerefMut};

use anchor_lang::{prelude::*, system_program};
use ntt_messages::ntt::NativeTokenTransfer;

use crate::{
    bitmap::Bitmap, clock::current_timestamp, error::NTTError,
    messages::ValidatedTransceiverMessage,
};

use super::rate_limit::RateLimitState;

#[account]
#[derive(InitSpace)]
// TODO: generalise this to arbitrary inbound messages (via a generic parameter in place of amount and recipient info)
pub struct InboxItem {
    // Whether the InboxItem has already been initialized. This is used during the redeem process
    // to guard against modifications to the `bump` and `amounts` fields.
    pub init: bool,
    pub bump: u8,
    pub amount: u64,
    pub recipient_address: Pubkey,
    pub votes: Bitmap,
    pub release_status: ReleaseStatus,
}

/// The status of an InboxItem. This determines whether the tokens are minted/unlocked to the recipient. As
/// such, this must be used as a state machine that moves forward in a linear manner. A state
/// should never "move backward" to a previous state (e.g. should never move from `Released` to
/// `ReleaseAfter`).
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug, PartialEq, Eq, InitSpace)]
pub enum ReleaseStatus {
    NotApproved,
    ReleaseAfter(i64),
    Released,
}

impl InboxItem {
    pub const SEED_PREFIX: &'static [u8] = b"inbox_item";

    /// Inits inbox_item if not done so previously
    /// Returns (deserialized inbox_item, bump)
    pub fn init_if_needed<'info>(
        info: &UncheckedAccount<'info>,
        transceiver_message: &ValidatedTransceiverMessage<NativeTokenTransfer>,
        payer: &Signer<'info>,
        system_program: &Program<'info, System>,
    ) -> Result<(Self, u8)> {
        let (pda_address, bump) = Pubkey::find_program_address(
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
        if info.key() != pda_address {
            return Err(Error::from(ErrorCode::ConstraintSeeds)
                .with_account_name("inbox_item")
                .with_pubkeys((info.key(), pda_address)));
        }
        let anchor_rent = Rent::get()?;
        let space = 8 + InboxItem::INIT_SPACE;
        let inbox_item: InboxItem = if info.owner == &system_program::ID {
            let current_lamports = info.lamports();
            if current_lamports == 0 {
                let lamports = anchor_rent.minimum_balance(space);
                system_program::create_account(
                    CpiContext::new(
                        system_program.to_account_info(),
                        system_program::CreateAccount {
                            from: payer.to_account_info(),
                            to: info.to_account_info(),
                        },
                    )
                    .with_signer(&[&[
                        InboxItem::SEED_PREFIX,
                        transceiver_message
                            .message
                            .ntt_manager_payload
                            .keccak256(transceiver_message.from_chain)
                            .as_ref(),
                        &[bump][..],
                    ][..]]),
                    lamports,
                    space as u64,
                    &crate::ID,
                )?;
            } else {
                if payer.key() == info.key() {
                    return Err(Error::from(ErrorCode::TryingToInitPayerAsProgramAccount)
                        .with_pubkeys((payer.key(), info.key())));
                }
                let required_lamports = anchor_rent
                    .minimum_balance(space)
                    .max(1)
                    .saturating_sub(current_lamports);
                if required_lamports > 0 {
                    system_program::transfer(
                        CpiContext::new(
                            system_program.to_account_info(),
                            system_program::Transfer {
                                from: payer.to_account_info(),
                                to: info.to_account_info(),
                            },
                        ),
                        required_lamports,
                    )?;
                }
                system_program::allocate(
                    CpiContext::new(
                        system_program.to_account_info(),
                        system_program::Allocate {
                            account_to_allocate: info.to_account_info(),
                        },
                    )
                    .with_signer(&[&[
                        InboxItem::SEED_PREFIX,
                        transceiver_message
                            .message
                            .ntt_manager_payload
                            .keccak256(transceiver_message.from_chain)
                            .as_ref(),
                        &[bump][..],
                    ][..]]),
                    space as u64,
                )?;
                system_program::assign(
                    CpiContext::new(
                        system_program.to_account_info(),
                        system_program::Assign {
                            account_to_assign: info.to_account_info(),
                        },
                    )
                    .with_signer(&[&[
                        InboxItem::SEED_PREFIX,
                        transceiver_message
                            .message
                            .ntt_manager_payload
                            .keccak256(transceiver_message.from_chain)
                            .as_ref(),
                        &[bump][..],
                    ][..]]),
                    &crate::ID,
                )?;
            }
            let mut data: &[u8] = &info.try_borrow_data()?;
            InboxItem::try_deserialize_unchecked(&mut data)?
        } else {
            let mut data: &[u8] = &info.try_borrow_data()?;
            InboxItem::try_deserialize(&mut data)?
        };
        if space != info.data_len() {
            return Err(Error::from(ErrorCode::ConstraintSpace)
                .with_account_name("inbox_item")
                .with_values((space, info.data_len())));
        }
        if info.owner != &crate::ID {
            return Err(Error::from(ErrorCode::ConstraintOwner)
                .with_account_name("inbox_item")
                .with_pubkeys((*info.owner, crate::ID)));
        }
        {
            let required_lamports = anchor_rent.minimum_balance(space);
            if info.to_account_info().lamports() < required_lamports {
                return Err(
                    Error::from(ErrorCode::ConstraintRentExempt).with_account_name("inbox_item")
                );
            }
        }
        Ok((inbox_item, bump))
    }

    /// Attempt to release the transfer.
    /// Returns true if the transfer was released, false if it was not yet time to release it.
    pub fn try_release(&mut self) -> Result<bool> {
        let now = current_timestamp();

        match self.release_status {
            ReleaseStatus::NotApproved => Ok(false),
            ReleaseStatus::ReleaseAfter(release_timestamp) => {
                if release_timestamp > now {
                    return Ok(false);
                }
                self.release_status = ReleaseStatus::Released;
                Ok(true)
            }
            ReleaseStatus::Released => Err(NTTError::TransferAlreadyRedeemed.into()),
        }
    }

    pub fn release_after(&mut self, release_timestamp: i64) -> Result<()> {
        if self.release_status != ReleaseStatus::NotApproved {
            return Err(NTTError::TransferCannotBeRedeemed.into());
        };
        self.release_status = ReleaseStatus::ReleaseAfter(release_timestamp);
        Ok(())
    }
}

/// Inbound rate limit per chain.
/// SECURITY: must check the PDA (since there are multiple PDAs, namely one for each chain.)
#[account]
#[derive(InitSpace)]
pub struct InboxRateLimit {
    pub bump: u8,
    pub rate_limit: RateLimitState,
}

impl InboxRateLimit {
    pub const SEED_PREFIX: &'static [u8] = b"inbox_rate_limit";
}

impl Deref for InboxRateLimit {
    type Target = RateLimitState;
    fn deref(&self) -> &Self::Target {
        &self.rate_limit
    }
}

impl DerefMut for InboxRateLimit {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.rate_limit
    }
}
