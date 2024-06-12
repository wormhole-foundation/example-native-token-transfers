export type WormholeGovernance = {
  "version": "2.0.0",
  "name": "wormhole_governance",
  "instructions": [
    {
      "name": "governance",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "governance",
          "isMut": true,
          "isSigner": false,
          "docs": [
            "governed program."
          ]
        },
        {
          "name": "vaa",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "program",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "replay",
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
    }
  ],
  "accounts": [
    {
      "name": "replayProtection",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "bump",
            "type": "u8"
          }
        ]
      }
    }
  ],
  "errors": [
    {
      "code": 6000,
      "name": "InvalidGovernanceChain",
      "msg": "InvalidGovernanceChain"
    },
    {
      "code": 6001,
      "name": "InvalidGovernanceEmitter",
      "msg": "InvalidGovernanceEmitter"
    },
    {
      "code": 6002,
      "name": "InvalidGovernanceProgram",
      "msg": "InvalidGovernanceProgram"
    }
  ]
};

export const IDL: WormholeGovernance = {
  "version": "2.0.0",
  "name": "wormhole_governance",
  "instructions": [
    {
      "name": "governance",
      "accounts": [
        {
          "name": "payer",
          "isMut": true,
          "isSigner": true
        },
        {
          "name": "governance",
          "isMut": true,
          "isSigner": false,
          "docs": [
            "governed program."
          ]
        },
        {
          "name": "vaa",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "program",
          "isMut": false,
          "isSigner": false
        },
        {
          "name": "replay",
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
    }
  ],
  "accounts": [
    {
      "name": "replayProtection",
      "type": {
        "kind": "struct",
        "fields": [
          {
            "name": "bump",
            "type": "u8"
          }
        ]
      }
    }
  ],
  "errors": [
    {
      "code": 6000,
      "name": "InvalidGovernanceChain",
      "msg": "InvalidGovernanceChain"
    },
    {
      "code": 6001,
      "name": "InvalidGovernanceEmitter",
      "msg": "InvalidGovernanceEmitter"
    },
    {
      "code": 6002,
      "name": "InvalidGovernanceProgram",
      "msg": "InvalidGovernanceProgram"
    }
  ]
};
