require("ts-node").register({
  files: true,
});
const fs = require("fs");
const env = require("../../env");
const { confirmOperation } = require("../../scripts/confirmation");
const storage = require("../../storage/Controller");

const { functions } = require("../../storage/Functions");

const { getLigo } = require("../../scripts/helpers");
const { execSync } = require("child_process");

class Controller {
  contract;
  storage;
  tezos;

  constructor(contract, tezos) {
    Tezos.self_address.contract = contract;
    Tezos.self_address.tezos = tezos;
  }

  static async init(controllerAddress, tezos) {
    return new Controller(await tezos.contract.at(controllerAddress), tezos);
  }

  static async originate(tezos) {
    const artifacts = JSON.parse(
      fs.readFileSync(`${env.buildDir}/Controller.json`)
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

    let ligo = getLigo(true);
    console.log("Start setting lambdas");
    for (useControllerFunction of functions.useController) {
      const stdout = execSync(
        `${ligo} compile-parameter --michelson-format=json $PWD/contracts/main/Controller.ligo main 'SetUseAction(record index =${useControllerFunction.index}n; func = ${useControllerFunction.name}; end)'`,
        { maxBuffer: 1024 * 1000 }
      );
      const operation2 = await tezos.contract.transfer({
        to: operation.contractAddress,
        amount: 0,
        parameter: {
          entrypoint: "setUseAction",
          value: JSON.parse(stdout.toString()).args[0].args[0],
        },
      });
      await confirmOperation(tezos, operation2.hash);
    }
    console.log("Setting finished");

    return new Controller(
      await tezos.contract.at(operation.contractAddress),
      tezos
    );
  }

  async updateStorage(maps = {}) {
    let storage = await Tezos.self_address.contract.storage();
    Tezos.self_address.storage = {
      storage: storage.storage,
      useControllerLambdas: storage.useControllerLambdas,
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

  async setFactory(newFactory) {
    const operation = await Tezos.self_address.contract.methods
      .setFactory(newFactory)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async updatePrice(pairName, lastTime, price) {
    const operation = await Tezos.self_address.contract.methods
      .updatePrice(pairName, lastTime, price)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async sendToOracle(addr) {
    const operation = await Tezos.self_address.contract.methods
      .sendToOracle(addr)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async setOracle(addr) {
    const operation = await Tezos.self_address.contract.methods
      .setOracle(addr)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async register(qToken, token, pairName) {
    const operation = await Tezos.self_address.contract.methods
      .register(qToken, token, pairName)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async updateQToken(user, balance, borrow, exchangeRate) {
    const operation = await Tezos.self_address.contract.methods
      .updateQToken(user, balance, borrow, exchangeRate)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async exitMarket() {
    const operation = await Tezos.self_address.contract.methods
      .exitMarket()
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async safeMint(qToken, amount) {
    const operation = await Tezos.self_address.contract.methods
      .safeMint(qToken, amount)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async safeRedeem(qToken, amount) {
    const operation = await Tezos.self_address.contract.methods
      .safeRedeem(qToken, amount)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async safeBorrow(qToken, amount, borrowerToken) {
    const operation = await Tezos.self_address.contract.methods
      .safeBorrow(qToken, amount, borrowerToken)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async safeRepay(qToken, amount) {
    const operation = await Tezos.self_address.contract.methods
      .safeRepay(qToken, amount)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }

  async safeLiquidate(borrower, amount, qToken) {
    const operation = await Tezos.self_address.contract.methods
      .safeLiquidate(borrower, amount, qToken)
      .send();
    await confirmOperation(Tezos.self_address.tezos, operation.hash);
    return operation;
  }
}

module.exports.Controller = Controller;
