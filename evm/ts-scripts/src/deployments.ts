import { Deployment} from "./env";

export type ContractsJson = {
  WormholeCore: Deployment[],
  WormholeRelayers: Deployment[],
  SpecializedRelayers: Deployment[],

  NttManagerProxies: Deployment[],
  NttManagerSetups: Deployment[],
  NttManagerImplementations: Deployment[],

  NttEndpointProxies: Deployment[],
  NttEndpointSetups: Deployment[],
  NttEndpointImplementations: Deployment[],
};

