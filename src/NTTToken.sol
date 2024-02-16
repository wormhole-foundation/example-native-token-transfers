// SPDX-License-Identifier: Apache 2
pragma solidity >=0.8.8 <0.9.0;

import {ERC20Burnable} from
    "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./interfaces/INTTToken.sol";

abstract contract NTTToken is INTTToken, ERC20Burnable {
    struct _Address {
        address minter;
    }

    bytes32 public constant MINTER_SLOT = bytes32(uint256(keccak256("ntttoken.minter")) - 1);

    function _getMinterStorage() internal pure returns (_Address storage $) {
        uint256 slot = uint256(MINTER_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    modifier onlyMinter() {
        if (msg.sender != _getMinterStorage().minter) {
            revert CallerNotMinter(msg.sender);
        }
        _;
    }

    function mint(address _account, uint256 _amount) external onlyMinter {
        _mint(_account, _amount);
    }

    function _setMinter(address newMinter) internal {
        if (newMinter == address(0)) {
            revert InvalidMinterZeroAddress();
        }
        _getMinterStorage().minter = newMinter;
        emit NewMinter(newMinter);
    }
}
