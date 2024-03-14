// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

interface INTTToken {
    /// @notice the caller is not the minter.
    /// @dev Selector 0x5fb5729e.
    /// @param caller The caller of the function.
    error CallerNotMinter(address caller);

    /// @notice the minter is the zero address.
    /// @dev Selector 0x04a208c7.
    error InvalidMinterZeroAddress();

    /// @notice insufficient balance to burn the amount.
    /// @dev Selector 0xcf479181.
    /// @param balance The balance of the account.
    /// @param amount The amount to burn.
    error InsufficientBalance(uint256 balance, uint256 amount);

    /// @notice The minter has been changed.
    /// @dev Topic0
    ///     0x6adffd5c93085d835dac6f3b40adf7c242ca4b3284048d20c3d8a501748dc973.
    /// @param newMinter The new minter.
    event NewMinter(address newMinter);

    function mint(address account, uint256 amount) external;
    function setMinter(address newMinter) external;
    function burn(uint256 amount) external;
}
