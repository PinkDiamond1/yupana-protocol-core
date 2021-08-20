require("ts-node").register({
  files: true,
});
const fs = require("fs");
const env = require("../../env");
const { confirmOperation } = require("../../scripts/confirmation");
const storage = require("../../storage/Factory");

class Factory {
  contract;
  storage;
  tezos;

  constructor(contract, tezos) {
    Tezos.self_address.contract = contract;
    Tezos.self_address.tezos = tezos;
  }

  static async init(qsAddress, tezos) {
    return new Factory(await tezos.contract.at(qsAddress), tezos);
  }

  static async originate(tezos) {
    const artifacts = JSON.parse(
      fs.readFileSync(`${env.buildDir}/Factory.json`)
    );
    const operation = await tezos.contract
      .originate({
        code: artifacts.michelson,
        storage: storage,
      })
      .catch((e) => {
        console.error(JSON.stringify(e));

        return { contractAddress: null };
      });
    await confirmOperation(tezos, operation.hash);
    return new Factory(
      await tezos.contract.at(operation.contractAddress),
      tezos
    );
  }

  async updateStorage(maps = {}) {
    let storage = await Tezos.self_address.contract.storage();
    Tezos.self_address.storage = {
      tokenList: storage.tokenList,
      owner: storage.owner,
      admin: storage.admin,
      tokenLambdas: storage.tokenLambdas,
      useLambdas: storage.useLambdas,
    };

    for (const key in maps) {
      Tezos.self_address.storage[key] = await maps[key].reduce(
        async (prev, current) => {
          try {
            return {
              ...(await prev),
              [current]: await storage[key].get(current),
            };
          } catch (ex) {
            return {
              ...(await prev),
              [current]: 0,
            };
          }
        },
        Promise.resolve({})
      );
    }
  }

  async setFactoryAdmin(newAdmin) {
    const operation = await Tezos.self_address.contract.methods
      .setFactoryAdmin(newAdmin)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async setNewOwner(newOwner) {
    const operation = await Tezos.self_address.contract.methods
      .setNewOwner(newOwner)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async launchToken(tokenAddress, oralcePairName) {
    const operation = await Tezos.self_address.contract.methods
      .launchToken(oralcePairName, tokenAddress)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async setTokenFunction(idx, f) {
    const operation = await Tezos.self_address.contract.methods
      .setTokenFunction(idx, f)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async setUseFunction(idx, f) {
    const operation = await Tezos.self_address.contract.methods
      .setUseFunction(idx, f)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }
}

module.exports.Factory = Factory;
