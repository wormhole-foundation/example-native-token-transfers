// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DummyToken is ERC20 {
    constructor() ERC20("DummyToken", "DTKN") {}

    // NOTE: this is purposefully not called mint() to so we can test that in
    // locking mode the Manager contract doesn't call mint (or burn)
    function mintDummy(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function mint(address to, uint256 amount) public virtual {
        revert("Locking manager should not call 'mint()'");
    }

    function burnFrom(address to, uint256 amount) public virtual {
        revert("Locking manager should not call 'burnFrom()'");
    }
}

contract DummyTokenMintAndBurn is DummyToken {
    function mint(address to, uint256 amount) public override {
        // TODO - add access control here
        _mint(to, amount);
    }

    function burnFrom(address to, uint256 amount) public override {
        // TODO - add access control here
        _burn(to, amount);
    }
}
