export type NttTransceiver = {
  "version": "3.0.0",
  "name": "ntt_transceiver",
  "instructions": [
    {
      "name": "transceiverType",
      "accounts": [],
      "args": [],
      "returns": "string"
    },
    {
      "name": "setWormholePeer",
      "accounts": [
        {
          "name": "config",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "owner",
          "isMut": false,
          "isSigner": true
        },
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "peer",
          "isMut": true,
          "isSigner": false
        },
        {
          "name": "systemProgram",
          "isMut": false,
          "isSigner": false
        }
      ],
      "args": [
        {
          "name": "args",
          "type": {
            "defined": "SetTransceiverPeerArgs"
          }
        }
      ]
    },
    {
      "name": "receiveWormholeMessage",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "config",
          "accounts": [
            {
              "name": "config",
              "isMut": false,
              "isSigner": false
            }
          ]
        },
        {
          "name": "peer",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "vaa",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "transceiverMessage",
          "isMut": true,
          "isSigner": false
        },
        {
          "name": "systemProgram",
          "isMut": false,
          "isSigner": false
        }
      ],
      "args": []
    },
    {
      "name": "releaseWormholeOutbound",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "config",
          "accounts": [
            {
              "name": "config",
              "isMut": false,
              "isSigner": false
            }
          ]
        },
        {
          "name": "outboxItem",
          "isMut": true,
          "isSigner": false
        },
        {
          "name": "transceiver",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormholeMessage",
          "isMut": true,
          "isSigner": false
        },
        {
          "name": "emitter",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormhole",
          "accounts": [
            {
              "name": "bridge",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "feeCollector",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "sequence",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "program",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "systemProgram",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "clock",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "rent",
              "isMut": false,
              "isSigner": false
            }
          ]
        },
        {
          "name": "manager",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "outboxItemSigner",
          "isMut": false,
          "isSigner": false
        }
      ],
      "args": [
        {
          "name": "args",
          "type": {
            "defined": "ReleaseOutboundArgs"
          }
        }
      ]
    },
    {
      "name": "broadcastWormholeId",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "config",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "mint",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormholeMessage",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "emitter",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormhole",
          "accounts": [
            {
              "name": "bridge",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "feeCollector",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "sequence",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "program",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "systemProgram",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "clock",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "rent",
              "isMut": false,
              "isSigner": false
            }
          ]
        }
      ],
      "args": []
    },
    {
      "name": "broadcastWormholePeer",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "config",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "peer",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormholeMessage",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "emitter",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormhole",
          "accounts": [
            {
              "name": "bridge",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "feeCollector",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "sequence",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "program",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "systemProgram",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "clock",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "rent",
              "isMut": false,
              "isSigner": false
            }
          ]
        }
      ],
      "args": [
        {
          "name": "args",
          "type": {
            "defined": "BroadcastPeerArgs"
          }
        }
      ]
    }
  ],
  "accounts": [
    {
      "name": "config",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "bump",
            "type": "u8"
          },
          {
            "name": "owner",
            "docs": [
              "Owner of the program."
            ],
            "type": "publicKey"
          },
          {
            "name": "pendingOwner",
            "docs": [
              "Pending next owner (before claiming ownership)."
            ],
            "type": {
              "option": "publicKey"
            }
          },
          {
            "name": "mint",
            "docs": [
              "Mint address of the token managed by this program."
            ],
            "type": "publicKey"
          },
          {
            "name": "tokenProgram",
            "docs": [
              "Address of the token program (token or token22). This could always be queried",
              "from the [`mint`] account's owner, but storing it here avoids an indirection",
              "on the client side."
            ],
            "type": "publicKey"
          },
          {
            "name": "mode",
            "docs": [
              "The mode that this program is running in. This is used to determine",
              "whether the program is burning tokens or locking tokens."
            ],
            "type": {
              "defined": "Mode"
            }
          },
          {
            "name": "chainId",
            "docs": [
              "The chain id of the chain that this program is running on. We don't",
              "hardcode this so that the program is deployable on any potential SVM",
              "forks."
            ],
            "type": {
              "defined": "ChainId"
            }
          },
          {
            "name": "nextTransceiverId",
            "docs": [
              "The next transceiver id to use when registering an transceiver."
            ],
            "type": "u8"
          },
          {
            "name": "threshold",
            "docs": [
              "The number of transceivers that must attest to a transfer before it is",
              "accepted."
            ],
            "type": "u8"
          },
          {
            "name": "enabledTransceivers",
            "docs": [
              "Bitmap of enabled transceivers.",
              "The maximum number of transceivers is equal to [`Bitmap::BITS`]."
            ],
            "type": {
              "defined": "Bitmap"
            }
          },
          {
            "name": "paused",
            "docs": [
              "Pause the program. This is useful for upgrades and other maintenance."
            ],
            "type": "bool"
          },
          {
            "name": "custody",
            "docs": [
              "The custody account that holds tokens in locking mode."
            ],
            "type": "publicKey"
          }
        ]
      }
    },
    {
      "name": "outboxItem",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "amount",
            "type": {
              "defined": "TrimmedAmount"
            }
          },
          {
            "name": "sender",
            "type": "publicKey"
          },
          {
            "name": "recipientChain",
            "type": {
              "defined": "ChainId"
            }
          },
          {
            "name": "recipientNttManager",
            "type": {
              "array": [
                "u8",
                32
              ]
            }
          },
          {
            "name": "recipientAddress",
            "type": {
              "array": [
                "u8",
                32
              ]
            }
          },
          {
            "name": "releaseTimestamp",
            "type": "i64"
          },
          {
            "name": "released",
            "type": {
              "defined": "Bitmap"
            }
          }
        ]
      }
    },
    {
      "name": "registeredTransceiver",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "bump",
            "type": "u8"
          },
          {
            "name": "id",
            "type": "u8"
          },
          {
            "name": "transceiverAddress",
            "type": "publicKey"
          }
        ]
      }
    },
    {
      "name": "transceiverPeer",
      "docs": [
        "A peer on another chain. Stored in a PDA seeded by the chain id."
      ],
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "bump",
            "type": "u8"
          },
          {
            "name": "address",
            "type": {
              "array": [
                "u8",
                32
              ]
            }
          }
        ]
      }
    },
    {
      "name": "bridgeData",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "guardianSetIndex",
            "docs": [
              "The current guardian set index, used to decide which signature sets to accept."
            ],
            "type": "u32"
          },
          {
            "name": "lastLamports",
            "docs": [
              "Lamports in the collection account"
            ],
            "type": "u64"
          },
          {
            "name": "config",
            "docs": [
              "Bridge configuration, which is set once upon initialization."
            ],
            "type": {
              "defined": "BridgeConfig"
            }
          }
        ]
      }
    }
  ],
  "types": [
    {
      "name": "Bitmap",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "map",
            "type": "u128"
          }
        ]
      }
    },
    {
      "name": "ChainId",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "id",
            "type": "u16"
          }
        ]
      }
    },
    {
      "name": "Mode",
      "type": {
        "kind": "enum",
        "variants": [
          {
            "name": "Locking"
          },
          {
            "name": "Burning"
          }
        ]
      }
    },
    {
      "name": "TrimmedAmount",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "amount",
            "type": "u64"
          },
          {
            "name": "decimals",
            "type": "u8"
          }
        ]
      }
    },
    {
      "name": "SetTransceiverPeerArgs",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "chainId",
            "type": {
              "defined": "ChainId"
            }
          },
          {
            "name": "address",
            "type": {
              "array": [
                "u8",
                32
              ]
            }
          }
        ]
      }
    },
    {
      "name": "BroadcastPeerArgs",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "chainId",
            "type": "u16"
          }
        ]
      }
    },
    {
      "name": "ReleaseOutboundArgs",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "revertOnDelay",
            "type": "bool"
          }
        ]
      }
    },
    {
      "name": "BridgeConfig",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "guardianSetExpirationTime",
            "docs": [
              "Period for how long a guardian set is valid after it has been replaced by a new one.  This",
              "guarantees that VAAs issued by that set can still be submitted for a certain period.  In",
              "this period we still trust the old guardian set."
            ],
            "type": "u32"
          },
          {
            "name": "fee",
            "docs": [
              "Amount of lamports that needs to be paid to the protocol to post a message"
            ],
            "type": "u64"
          }
        ]
      }
    }
  ]
}
export const IDL: NttTransceiver = {
  "version": "3.0.0",
  "name": "ntt_transceiver",
  "instructions": [
    {
      "name": "transceiverType",
      "accounts": [],
      "args": [],
      "returns": "string"
    },
    {
      "name": "setWormholePeer",
      "accounts": [
        {
          "name": "config",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "owner",
          "isMut": false,
          "isSigner": true
        },
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "peer",
          "isMut": true,
          "isSigner": false
        },
        {
          "name": "systemProgram",
          "isMut": false,
          "isSigner": false
        }
      ],
      "args": [
        {
          "name": "args",
          "type": {
            "defined": "SetTransceiverPeerArgs"
          }
        }
      ]
    },
    {
      "name": "receiveWormholeMessage",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "config",
          "accounts": [
            {
              "name": "config",
              "isMut": false,
              "isSigner": false
            }
          ]
        },
        {
          "name": "peer",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "vaa",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "transceiverMessage",
          "isMut": true,
          "isSigner": false
        },
        {
          "name": "systemProgram",
          "isMut": false,
          "isSigner": false
        }
      ],
      "args": []
    },
    {
      "name": "releaseWormholeOutbound",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "config",
          "accounts": [
            {
              "name": "config",
              "isMut": false,
              "isSigner": false
            }
          ]
        },
        {
          "name": "outboxItem",
          "isMut": true,
          "isSigner": false
        },
        {
          "name": "transceiver",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormholeMessage",
          "isMut": true,
          "isSigner": false
        },
        {
          "name": "emitter",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormhole",
          "accounts": [
            {
              "name": "bridge",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "feeCollector",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "sequence",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "program",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "systemProgram",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "clock",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "rent",
              "isMut": false,
              "isSigner": false
            }
          ]
        },
        {
          "name": "manager",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "outboxItemSigner",
          "isMut": false,
          "isSigner": false
        }
      ],
      "args": [
        {
          "name": "args",
          "type": {
            "defined": "ReleaseOutboundArgs"
          }
        }
      ]
    },
    {
      "name": "broadcastWormholeId",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "config",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "mint",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormholeMessage",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "emitter",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormhole",
          "accounts": [
            {
              "name": "bridge",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "feeCollector",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "sequence",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "program",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "systemProgram",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "clock",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "rent",
              "isMut": false,
              "isSigner": false
            }
          ]
        }
      ],
      "args": []
    },
    {
      "name": "broadcastWormholePeer",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "config",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "peer",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormholeMessage",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "emitter",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "wormhole",
          "accounts": [
            {
              "name": "bridge",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "feeCollector",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "sequence",
              "isMut": true,
              "isSigner": false
            },
            {
              "name": "program",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "systemProgram",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "clock",
              "isMut": false,
              "isSigner": false
            },
            {
              "name": "rent",
              "isMut": false,
              "isSigner": false
            }
          ]
        }
      ],
      "args": [
        {
          "name": "args",
          "type": {
            "defined": "BroadcastPeerArgs"
          }
        }
      ]
    }
  ],
  "accounts": [
    {
      "name": "config",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "bump",
            "type": "u8"
          },
          {
            "name": "owner",
            "docs": [
              "Owner of the program."
            ],
            "type": "publicKey"
          },
          {
            "name": "pendingOwner",
            "docs": [
              "Pending next owner (before claiming ownership)."
            ],
            "type": {
              "option": "publicKey"
            }
          },
          {
            "name": "mint",
            "docs": [
              "Mint address of the token managed by this program."
            ],
            "type": "publicKey"
          },
          {
            "name": "tokenProgram",
            "docs": [
              "Address of the token program (token or token22). This could always be queried",
              "from the [`mint`] account's owner, but storing it here avoids an indirection",
              "on the client side."
            ],
            "type": "publicKey"
          },
          {
            "name": "mode",
            "docs": [
              "The mode that this program is running in. This is used to determine",
              "whether the program is burning tokens or locking tokens."
            ],
            "type": {
              "defined": "Mode"
            }
          },
          {
            "name": "chainId",
            "docs": [
              "The chain id of the chain that this program is running on. We don't",
              "hardcode this so that the program is deployable on any potential SVM",
              "forks."
            ],
            "type": {
              "defined": "ChainId"
            }
          },
          {
            "name": "nextTransceiverId",
            "docs": [
              "The next transceiver id to use when registering an transceiver."
            ],
            "type": "u8"
          },
          {
            "name": "threshold",
            "docs": [
              "The number of transceivers that must attest to a transfer before it is",
              "accepted."
            ],
            "type": "u8"
          },
          {
            "name": "enabledTransceivers",
            "docs": [
              "Bitmap of enabled transceivers.",
              "The maximum number of transceivers is equal to [`Bitmap::BITS`]."
            ],
            "type": {
              "defined": "Bitmap"
            }
          },
          {
            "name": "paused",
            "docs": [
              "Pause the program. This is useful for upgrades and other maintenance."
            ],
            "type": "bool"
          },
          {
            "name": "custody",
            "docs": [
              "The custody account that holds tokens in locking mode."
            ],
            "type": "publicKey"
          }
        ]
      }
    },
    {
      "name": "outboxItem",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "amount",
            "type": {
              "defined": "TrimmedAmount"
            }
          },
          {
            "name": "sender",
            "type": "publicKey"
          },
          {
            "name": "recipientChain",
            "type": {
              "defined": "ChainId"
            }
          },
          {
            "name": "recipientNttManager",
            "type": {
              "array": [
                "u8",
                32
              ]
            }
          },
          {
            "name": "recipientAddress",
            "type": {
              "array": [
                "u8",
                32
              ]
            }
          },
          {
            "name": "releaseTimestamp",
            "type": "i64"
          },
          {
            "name": "released",
            "type": {
              "defined": "Bitmap"
            }
          }
        ]
      }
    },
    {
      "name": "registeredTransceiver",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "bump",
            "type": "u8"
          },
          {
            "name": "id",
            "type": "u8"
          },
          {
            "name": "transceiverAddress",
            "type": "publicKey"
          }
        ]
      }
    },
    {
      "name": "transceiverPeer",
      "docs": [
        "A peer on another chain. Stored in a PDA seeded by the chain id."
      ],
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "bump",
            "type": "u8"
          },
          {
            "name": "address",
            "type": {
              "array": [
                "u8",
                32
              ]
            }
          }
        ]
      }
    },
    {
      "name": "bridgeData",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "guardianSetIndex",
            "docs": [
              "The current guardian set index, used to decide which signature sets to accept."
            ],
            "type": "u32"
          },
          {
            "name": "lastLamports",
            "docs": [
              "Lamports in the collection account"
            ],
            "type": "u64"
          },
          {
            "name": "config",
            "docs": [
              "Bridge configuration, which is set once upon initialization."
            ],
            "type": {
              "defined": "BridgeConfig"
            }
          }
        ]
      }
    }
  ],
  "types": [
    {
      "name": "Bitmap",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "map",
            "type": "u128"
          }
        ]
      }
    },
    {
      "name": "ChainId",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "id",
            "type": "u16"
          }
        ]
      }
    },
    {
      "name": "Mode",
      "type": {
        "kind": "enum",
        "variants": [
          {
            "name": "Locking"
          },
          {
            "name": "Burning"
          }
        ]
      }
    },
    {
      "name": "TrimmedAmount",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "amount",
            "type": "u64"
          },
          {
            "name": "decimals",
            "type": "u8"
          }
        ]
      }
    },
    {
      "name": "SetTransceiverPeerArgs",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "chainId",
            "type": {
              "defined": "ChainId"
            }
          },
          {
            "name": "address",
            "type": {
              "array": [
                "u8",
                32
              ]
            }
          }
        ]
      }
    },
    {
      "name": "BroadcastPeerArgs",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "chainId",
            "type": "u16"
          }
        ]
      }
    },
    {
      "name": "ReleaseOutboundArgs",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "revertOnDelay",
            "type": "bool"
          }
        ]
      }
    },
    {
      "name": "BridgeConfig",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "guardianSetExpirationTime",
            "docs": [
              "Period for how long a guardian set is valid after it has been replaced by a new one.  This",
              "guarantees that VAAs issued by that set can still be submitted for a certain period.  In",
              "this period we still trust the old guardian set."
            ],
            "type": "u32"
          },
          {
            "name": "fee",
            "docs": [
              "Amount of lamports that needs to be paid to the protocol to post a message"
            ],
            "type": "u64"
          }
        ]
      }
    }
  ]
}

