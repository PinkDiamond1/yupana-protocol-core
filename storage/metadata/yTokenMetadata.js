const { MichelsonMap } = require("@taquito/michelson-encoder");
const yTokenErrors = require("./yTokenTZIP16Errors");

const metadata = MichelsonMap.fromLiteral({
  "": Buffer.from("tezos-storage:yupana", "ascii").toString("hex"),
  yupana: Buffer.from(
    JSON.stringify({
      name: "Yupana",
      version: "v0.3.3",
      description: "Yupana protocol.",
      authors: ["Madfish.Solutions <https://www.madfish.solutions>"],
      source: {
        tools: ["Ligo", "Flextesa"],
        location:
          "https://github.com/madfish-solutions/yupana-protocol-core/blob/master/contracts/main/yToken.ligo",
      },
      homepage: "https://yupana.com",
      interfaces: ["TZIP-012 git 1728fcfe", "TZIP-016"],
      errors: yTokenErrors,
      views: [],
    }),
    "ascii"
  ).toString("hex"),
});

module.exports = metadata;
