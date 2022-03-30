const { MichelsonMap } = require("@taquito/michelson-encoder");
const { alice } = require("../scripts/sandbox/accounts");
const metadata = require("./metadata/yTokenMetadata");

const yStorage = {
  admin: alice.pkh,
  admin_candidate: null,
  ledger: MichelsonMap.fromLiteral({}),
  accounts: MichelsonMap.fromLiteral({}),
  tokens: MichelsonMap.fromLiteral({}),
  lastTokenId: "0",
  priceFeedProxy: alice.pkh,
  closeFactorF: "0",
  liqIncentiveF: "0",
  maxMarkets: "0",
  markets: MichelsonMap.fromLiteral({}),
  borrows: MichelsonMap.fromLiteral({}),
  assets: MichelsonMap.fromLiteral({}),
};

module.exports = {
  storage: yStorage,
  metadata,
  token_metadata: MichelsonMap.fromLiteral({}),
  tokenLambdas: MichelsonMap.fromLiteral({}),
  useLambdas: MichelsonMap.fromLiteral({}),
};
