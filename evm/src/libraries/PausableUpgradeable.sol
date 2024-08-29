// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

/**
 * @dev Contact Module that allows children to implement logic to pause and unpause the contract.
 * This is based on the OpenZeppelin Pausable contract but makes use of deterministic storage slots
 * and the EVM native word size to optimize gas costs.
 *
 * The `whenPaused` and `whenNotPaused` modifiers are used to
 * execute code based on the current state of the contract.
 *
 */
import {Initializable} from "./external/Initializable.sol";

abstract contract PausableUpgradeable is Initializable {
    /*
     * @custom:storage-location erc7201:openzeppelin.storage.Pausable.
     * @dev Storage slot with the pauser account, this is managed by the `PauserStorage` struct
    */
    struct PauserStorage {
        address _pauser;
    }

    // @dev Storage slot with the pause flag, this is managed by the `PauseStorage` struct
    struct PauseStorage {
        uint256 _pauseFlag;
    }

    /// NOTE: use uint256 to save on gas because it is the native word size of the EVM
    /// it is cheaper than using a bool because modifying a boolean value requires an extra SLOAD
    uint256 private constant NOT_PAUSED = 1;
    uint256 private constant PAUSED = 2;

    event PauserTransferred(address indexed oldPauser, address indexed newPauser);

    /**
     * @dev Contract is not paused, functionality is unblocked
     */
    error RequireContractIsNotPaused();
    /**
     * @dev Contract state is paused, blocking
     */
    error RequireContractIsPaused();

    /**
     * @dev the pauser is not a valid pauser account (e.g. `address(0)`)
     */
    error InvalidPauser(address account);

    // @dev Emitted when the contract is paused
    event Paused(bool paused);
    event NotPaused(bool notPaused);

    bytes32 private constant PAUSE_SLOT = bytes32(uint256(keccak256("Pause.pauseFlag")) - 1);
    bytes32 private constant PAUSER_ROLE_SLOT = bytes32(uint256(keccak256("Pause.pauseRole")) - 1);

    function _getPauserStorage() internal pure returns (PauserStorage storage $) {
        uint256 slot = uint256(PAUSER_ROLE_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /**
     * @dev Returns the current pauser account address.
     */
    function pauser() public view returns (address) {
        return _getPauserStorage()._pauser;
    }

    function _getPauseStorage() private pure returns (PauseStorage storage $) {
        uint256 slot = uint256(PAUSE_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _setPauseStorage(
        uint256 pauseFlag
    ) internal {
        _getPauseStorage()._pauseFlag = pauseFlag;
    }

    function __Paused_init(
        address initialPauser
    ) internal onlyInitializing {
        __Paused_init_unchained(initialPauser);
    }

    function __Paused_init_unchained(
        address initialPauser
    ) internal onlyInitializing {
        // set pause flag to false initially
        PauseStorage storage $ = _getPauseStorage();
        $._pauseFlag = NOT_PAUSED;

        // set the initial pauser
        PauserStorage storage $_role = _getPauserStorage();
        $_role._pauser = initialPauser;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     * Calling a function when this flag is set to `PAUSED` will cause the transaction to revert.
     */
    modifier whenNotPaused() {
        if (isPaused()) {
            revert RequireContractIsNotPaused();
        }
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     * Calling a function when this flag is set to `PAUSED` will cause the transaction to revert.
     */
    modifier whenPaused() {
        if (!isPaused()) {
            revert RequireContractIsPaused();
        }
        _;
    }

    /*
     * @dev Modifier to allow only the Pauser to access pausing functionality
     */
    modifier onlyPauser() {
        _checkPauser();
        _;
    }

    /*
     * @dev Modifier to allow only the Pauser to access some functionality
     */
    function _checkPauser() internal view {
        if (pauser() != msg.sender) {
            revert InvalidPauser(msg.sender);
        }
    }

    /**
     * @dev pauses the function and emits the `Paused` event
     */
    function _pause() internal virtual whenNotPaused {
        // this can only be set to PAUSED when the state is NOTPAUSED
        _setPauseStorage(PAUSED);
        emit Paused(true);
    }

    /**
     * @dev unpauses the function
     */
    function _unpause() internal virtual whenPaused {
        // this can only be set to NOTPAUSED when the state is PAUSED
        _setPauseStorage(NOT_PAUSED);
        emit NotPaused(false);
    }

    /**
     * @dev Returns true if the method is paused, and false otherwise.
     */
    function isPaused() public view returns (bool) {
        PauseStorage storage $ = _getPauseStorage();
        return $._pauseFlag == PAUSED;
    }
}
