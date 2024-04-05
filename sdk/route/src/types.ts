export type TransceiverType = "wormhole";

export type NttTokenConfig = {
  chain: string;
  token: string;
  manager: string;
  transceiver: [
    {
      type: TransceiverType;
      address: string;
    }
  ];
};

export type NttRouteConfig = {
  // map of token name to configs
  tokens: Record<string, NttTokenConfig[]>;
};
