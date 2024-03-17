// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {INonFungibleNttManager} from "../interfaces/INonFungibleNttManager.sol";

contract DummyNft is ERC721 {
    // Common URI for all NFTs handled by this contract.
    bytes32 private immutable _baseUri;
    uint8 private immutable _baseUriLength;

    error BaseUriEmpty();
    error BaseUriTooLong();

    constructor(bytes memory baseUri) ERC721("DummyNft", "DNFT") {
        if (baseUri.length == 0) {
            revert BaseUriEmpty();
        }
        if (baseUri.length > 32) {
            revert BaseUriTooLong();
        }

        _baseUri = bytes32(baseUri);
        _baseUriLength = uint8(baseUri.length);
    }

    // NOTE: this is purposefully not called mint() to so we can test that in
    // locking mode the NttManager contract doesn't call mint (or burn)
    function mintDummy(address to, uint256 amount) public {
        _safeMint(to, amount);
    }

    function mint(address, uint256) public virtual {
        revert("Locking nttManager should not call 'mint()'");
    }

    function burn(address, uint256) public virtual {
        revert("Locking nttManager should not call 'burn()'");
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    function _baseURI() internal view virtual override returns (string memory baseUri) {
        baseUri = new string(_baseUriLength);
        bytes32 tmp = _baseUri;
        assembly ("memory-safe") {
            mstore(add(baseUri, 32), tmp)
        }
    }
}

contract DummyNftMintAndBurn is DummyNft {
    bool private reentrant;
    address private owner;

    constructor(bytes memory baseUri) DummyNft(baseUri) {
        owner = msg.sender;
    }

    function setReentrant(bool enabled) public {
        require(msg.sender == owner, "DummyNftMintAndBurn: not owner");
        reentrant = enabled;
    }

    function mint(address to, uint256 tokenId) public override {
        _safeMint(to, tokenId);

        _callback();
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);

        _callback();
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        super.safeTransferFrom(from, to, tokenId, "");

        _callback();
    }

    function _callback() public {
        if (!reentrant) {
            return;
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        INonFungibleNttManager(msg.sender).transfer(
            tokenIds, 69, bytes32(uint256(uint160(msg.sender))), ""
        );
    }
}
