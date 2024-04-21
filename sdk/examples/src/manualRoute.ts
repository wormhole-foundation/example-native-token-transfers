import { canonicalAddress, routes, wormhole } from "@wormhole-foundation/sdk";
import evm from "@wormhole-foundation/sdk/evm";
import solana from "@wormhole-foundation/sdk/solana";

// register protocol implementations
import "@wormhole-foundation/sdk-evm-ntt";
import "@wormhole-foundation/sdk-solana-ntt";

import { nttManualRoute } from "@wormhole-foundation/sdk-route-ntt";
import { NttTokens } from "./consts.js";
import { getSigner } from "./helpers.js";

(async function () {
  const wh = await wormhole("Testnet", [solana, evm]);

  const src = wh.getChain("Solana");
  const dst = wh.getChain("ArbitrumSepolia");

  const srcSigner = await getSigner(src);
  const dstSigner = await getSigner(dst);

  const resolver = wh.resolver([nttManualRoute({ tokens: NttTokens })]);

  const srcTokens = await resolver.supportedSourceTokens(src);
  console.log(
    "Allowed source tokens: ",
    srcTokens.map((t) => canonicalAddress(t))
  );
  // Just grab the first one
  const sendToken = srcTokens[0]!;

  // given the send token, what can we possibly get on the destination chain?
  const destTokens = await resolver.supportedDestinationTokens(
    sendToken,
    src,
    dst
  );
  console.log(
    "For the given source token and routes configured, the following tokens may be receivable: ",
    destTokens.map((t) => canonicalAddress(t))
  );
  //grab the first one for the example
  const destinationToken = destTokens[0]!;

  // creating a transfer request fetches token details
  // since all routes will need to know about the tokens
  const tr = await routes.RouteTransferRequest.create(wh, {
    from: srcSigner.address,
    to: dstSigner.address,
    source: sendToken,
    destination: destinationToken,
  });

  // resolve the transfer request to a set of routes that can perform it
  const foundRoutes = await resolver.findRoutes(tr);
  console.log(
    "For the transfer parameters, we found these routes: ",
    foundRoutes
  );

  // Sort the routes given some input (not required for mvp)
  // const bestRoute = (await resolver.sortRoutes(foundRoutes, "cost"))[0]!;
  const bestRoute = foundRoutes[0]!;
  console.log("Selected: ", bestRoute);

  console.log(
    "This route offers the following default options",
    bestRoute.getDefaultOptions()
  );

  // Specify the amount as a decimal string
  const amt = "0.00001";

  // validate the transfer params passed, this returns a new type of ValidatedTransferParams
  // which (believe it or not) is a validated version of the input params
  // this new var must be passed to the next step, quote
  const validated = await bestRoute.validate({ amount: amt });
  if (!validated.valid) throw validated.error;
  console.log("Validated parameters: ", validated.params);

  // get a quote for the transfer, this too returns a new type that must
  // be passed to the next step, execute (if you like the quote)
  const quote = await bestRoute.quote(validated.params);
  if (!quote.success) throw quote.error;
  console.log("Best route quote: ", quote);

  // Now the transfer may be initiated
  // A receipt will be returned, guess what you gotta do with that?
  const receipt = await bestRoute.initiate(srcSigner.signer, quote);
  console.log("Initiated transfer with receipt: ", receipt);

  // Kick off a wait log, if there is an opportunity to complete, this function will do it
  // see the implementation for how this works
  await routes.checkAndCompleteTransfer(bestRoute, receipt, dstSigner.signer);
})();
