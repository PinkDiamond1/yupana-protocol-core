#include "./FA2Methods.ligo"
#include "./AdminMethods.ligo"

function zeroCheck(
  const amt             : nat)
                        : unit is
    if amt = 0n
    then failwith("yToken/amount-is-zero");
    else unit

[@inline] function getReserveFactorContract(
  const rateAddress     : address)
                        : contract(entryRateAction) is
  case(
    Tezos.get_entrypoint_opt("%updReserveFactor", rateAddress)
                        : option(contract(entryRateAction))
  ) of
    Some(contr) -> contr
    | None -> (
      failwith("yToken/cant-get-interestRate-contract(rateUse)")
        : contract(entryRateAction)
    )
  end;

[@inline] function getUpdateBorrowRateContract(
  const selfAddress     : address)
                        : contract(yAssetParams) is
  case(
    Tezos.get_entrypoint_opt("%accrueInterest", selfAddress)
                        : option(contract(yAssetParams))
  ) of
    Some(contr) -> contr
    | None -> (
      failwith("yToken/cant-get-borrowRate") : contract(yAssetParams)
    )
  end;

[@inline] function getBorrowRateContract(
  const rateAddress     : address)
                        : contract(rateParams) is
  case(
    Tezos.get_entrypoint_opt("%getBorrowRate", rateAddress)
                        : option(contract(rateParams))
  ) of
    Some(contr) -> contr
    | None -> (
      failwith("yToken/cant-get-interestRate-contract(getBorrowRate)")
        : contract(rateParams)
    )
  end;

function verifyTokenUpdated(
    const token         : tokenInfo)
                        : unit is
    if token.lastUpdateTime < Tezos.now or token.priceUpdateTime < Tezos.now
    then failwith("yToken/need-update")
    else unit;

function calculateMaxCollaterallInCU(
  const userAccount     : account;
  var params            : calcCollParams)
                        : nat is
  block {
    function oneToken(
      var param         : calcCollParams;
      const tokenId     : tokenId)
                        : calcCollParams is
      block {
        const userInfo : balanceInfo = getMapInfo(
          userAccount.balances,
          tokenId
        );
        const token : tokenInfo = getTokenInfo(tokenId, param.s);

        verifyTokenUpdated(token);

        (* sum += collateralFactorFloat * exchangeRate * oraclePrice * balance *)
        param.res := param.res + ((userInfo.balance * token.lastPrice
          * token.collateralFactorFloat) * (abs(token.totalLiquidFloat
          + token.totalBorrowsFloat - token.totalReservesFloat)
          / token.totalSupplyFloat) / accuracy);
      } with param;
    const result : calcCollParams = Set.fold(
      oneToken,
      userAccount.markets,
      params
    );
  } with result.res

function calculateOutstandingBorrowInCU(
  var userAccount       : account;
  var params            : calcCollParams)
                        : nat is
  block {
    function oneToken(
      var param         : calcCollParams;
      const borrowMap   : tokenId * balanceInfo)
                        : calcCollParams is
      block {
        const token : tokenInfo = getTokenInfo(borrowMap.0, param.s);

        verifyTokenUpdated(token);

        (* sum += oraclePrice * balance *)
        param.res := param.res + ((borrowMap.1.borrow * token.lastPrice));
      } with param;
    const result : calcCollParams = Map.fold(
      oneToken,
      userAccount.balances,
      params
    );
  } with result.res

function updateInterest(
  const tokenId         : nat;
  var s                 : fullTokenStorage)
                        : fullReturn is
    block {
      var _token : tokenInfo := getTokenInfo(tokenId, s.storage);
      var operations : list(operation) := list[];

      if _token.totalBorrowsFloat = 0n
      then block {
        _token.lastUpdateTime := Tezos.now;
        s.storage.tokenInfo[tokenId] := _token;
      }
      else operations := list[
        Tezos.transaction(
          record[
            tokenId = tokenId;
            borrowsFloat = _token.totalBorrowsFloat;
            cashFloat = _token.totalLiquidFloat;
            reservesFloat = _token.totalReservesFloat;
            accuracy = accuracy;
            contract = getUpdateBorrowRateContract(Tezos.self_address);
          ],
          0mutez,
          getBorrowRateContract(_token.interstRateModel)
        )];
    } with (operations, s)

function mint(
  const p               : useAction;
  var s                 : tokenStorage)
                        : return is
  block {
    var operations : list(operation) := list[];
      case p of
        Mint(yAssetParams) -> {
          zeroCheck(yAssetParams.amount);

          if yAssetParams.tokenId < s.lastTokenId
          then skip
          else failwith("yToken/yToken-undefined");

          var mintTokensFloat : nat := yAssetParams.amount * accuracy;
          var token : tokenInfo := getTokenInfo(yAssetParams.tokenId, s);

          if token.totalSupplyFloat =/= 0n
          then {
            verifyTokenUpdated(token);
            mintTokensFloat := mintTokensFloat * token.totalSupplyFloat /
              abs(token.totalLiquidFloat + token.totalBorrowsFloat
                - token.totalReservesFloat);
          } else skip;

          var userAccount : account := getAccount(Tezos.sender, s);
          var userInfo : balanceInfo := getMapInfo(
            userAccount.balances,
            yAssetParams.tokenId
          );

          userInfo.balance := userInfo.balance + mintTokensFloat;

          userAccount.balances[yAssetParams.tokenId] := userInfo;
          s.accountInfo[Tezos.sender] := userAccount;
          token.totalSupplyFloat := token.totalSupplyFloat + mintTokensFloat;
          token.totalLiquidFloat := token.totalLiquidFloat
            + yAssetParams.amount * accuracy;
          s.tokenInfo[yAssetParams.tokenId] := token;

          operations := list [
              case token.faType of
              | FA12 -> Tezos.transaction(
                  TransferOutside(record [
                    from_ = Tezos.sender;
                    to_ = Tezos.self_address;
                    value = yAssetParams.amount
                  ]),
                  0mutez,
                  getTokenContract(token.mainToken)
                )
              | FA2(assetId) -> Tezos.transaction(
                  IterateTransferOutside(record [
                    from_ = Tezos.sender;
                    txs = list[
                      record[
                        tokenId = assetId;
                        to_ = Tezos.self_address;
                        amount = yAssetParams.amount
                      ]
                    ]
                  ]),
                  0mutez,
                  getIterTranserContract(token.mainToken)
                )
              end
          ];
        }
      | _                         -> skip
      end
  } with (operations, s)

function redeem(
  const p               : useAction;
  var s                 : tokenStorage)
                        : return is
  block {
    var operations : list(operation) := list[];
      case p of
        Redeem(yAssetParams) -> {
          zeroCheck(yAssetParams.amount);

          if yAssetParams.tokenId < s.lastTokenId
          then skip
          else failwith("yToken/yToken-undefined");

          var token : tokenInfo := getTokenInfo(yAssetParams.tokenId, s);

          verifyTokenUpdated(token);

          var accountUser : account := getAccount(Tezos.sender, s);

          if Set.mem(yAssetParams.tokenId, accountUser.markets)
          then failwith("yToken/token-taken-as-collateral")
          else skip;

          var userInfo : balanceInfo := getMapInfo(
            accountUser.balances,
            yAssetParams.tokenId
          );
          const liquidityFloat : nat = abs(token.totalLiquidFloat
            + token.totalBorrowsFloat - token.totalReservesFloat);

          const redeemAmount : nat = if yAssetParams.amount = 0n
          then userInfo.balance * liquidityFloat / token.totalSupplyFloat / accuracy
          else yAssetParams.amount;

          if redeemAmount * accuracy > token.totalLiquidFloat
          then failwith("yToken/not-enough-liquid")
          else skip;

          var burnTokensFloat : nat := redeemAmount * accuracy *
            token.totalSupplyFloat / liquidityFloat;
          if userInfo.balance < burnTokensFloat
          then failwith("yToken/not-enough-tokens-to-burn")
          else skip;

          userInfo.balance := abs(userInfo.balance - burnTokensFloat);
          accountUser.balances[yAssetParams.tokenId] := userInfo;
          s.accountInfo[Tezos.sender] := accountUser;
          token.totalSupplyFloat := abs(token.totalSupplyFloat - burnTokensFloat);
          token.totalLiquidFloat := abs(token.totalLiquidFloat - redeemAmount *
            accuracy);
          s.tokenInfo[yAssetParams.tokenId] := token;

          operations := list [
              case token.faType of
              | FA12 -> Tezos.transaction(
                  TransferOutside(record [
                    from_ = Tezos.self_address;
                    to_ = Tezos.sender;
                    value = redeemAmount
                  ]),
                  0mutez,
                  getTokenContract(token.mainToken)
                )
              | FA2(assetId) -> Tezos.transaction(
                  IterateTransferOutside(record [
                    from_ = Tezos.self_address;
                    txs = list[
                      record[
                        tokenId = assetId;
                        to_ = Tezos.sender;
                        amount = redeemAmount
                      ]
                    ]
                  ]),
                  0mutez,
                  getIterTranserContract(token.mainToken)
                )
              end
          ];
        }
      | _               -> skip
      end
  } with (operations, s)

function borrow(
  const p               : useAction;
  var s                 : tokenStorage)
                        : return is
  block {
    var operations : list(operation) := list[];
      case p of
        Borrow(yAssetParams) -> {
          zeroCheck(yAssetParams.amount);

          if yAssetParams.tokenId < s.lastTokenId
          then skip
          else failwith("yToken/yToken-undefined");

          var accountUser : account := getAccount(Tezos.sender, s);
          var token : tokenInfo := getTokenInfo(yAssetParams.tokenId, s);
          verifyTokenUpdated(token);

          const borrowsFloat : nat = yAssetParams.amount * accuracy;

          if borrowsFloat > token.totalLiquidFloat
          then failwith("yToken/amount-too-big")
          else skip;


          var userInfo : balanceInfo := getMapInfo(
            accountUser.balances,
            yAssetParams.tokenId
          );

          if userInfo.lastBorrowIndex =/= 0n
          then userInfo.borrow := userInfo.borrow *
              token.borrowIndex / userInfo.lastBorrowIndex;
          else skip;

          userInfo.lastBorrowIndex := token.borrowIndex;

          userInfo.borrow := userInfo.borrow + borrowsFloat;
          accountUser.balances[yAssetParams.tokenId] := userInfo;
          s.accountInfo[Tezos.sender] := accountUser;

          const maxBorrowInCU : nat = calculateMaxCollaterallInCU(
            accountUser,
            record[s = s; res = 0n; userAccount = accountUser]
          );
          const outstandingBorrowInCU : nat = calculateOutstandingBorrowInCU(
            accountUser,
            record[s = s; res = 0n; userAccount = accountUser]
          );

          if outstandingBorrowInCU > maxBorrowInCU
          then failwith("yToken/exceeds-the-permissible-debt");
          else skip;

          token.totalBorrowsFloat := token.totalBorrowsFloat + borrowsFloat;
          token.totalLiquidFloat := abs(token.totalLiquidFloat - borrowsFloat);
          s.tokenInfo[yAssetParams.tokenId] := token;

          operations := list [
              case token.faType of
              | FA12 -> Tezos.transaction(
                  TransferOutside(record [
                    from_ = Tezos.self_address;
                    to_ = Tezos.sender;
                    value = yAssetParams.amount
                  ]),
                  0mutez,
                  getTokenContract(token.mainToken)
                )
              | FA2(assetId) -> Tezos.transaction(
                  IterateTransferOutside(record [
                    from_ = Tezos.self_address;
                    txs = list[
                      record[
                        tokenId = assetId;
                        to_ = Tezos.sender;
                        amount = yAssetParams.amount
                      ]
                    ]
                  ]),
                  0mutez,
                  getIterTranserContract(token.mainToken)
                )
              end
          ];
        }
      | _                         -> skip
      end
  } with (operations, s)

function repay (
  const p               : useAction;
  var s                 : tokenStorage)
                        : return is
  block {
    var operations : list(operation) := list[];
      case p of
        Repay(yAssetParams) -> {
          var token : tokenInfo := getTokenInfo(yAssetParams.tokenId, s);

          if yAssetParams.tokenId < s.lastTokenId
          then skip
          else failwith("yToken/yToken-undefined");

          verifyTokenUpdated(token);

          var repayAmountFloat : nat := yAssetParams.amount * accuracy;

          var accountUser : account := getAccount(Tezos.sender, s);
          var userInfo : balanceInfo := getMapInfo(
            accountUser.balances,
            yAssetParams.tokenId
          );

          if userInfo.lastBorrowIndex =/= 0n
          then userInfo.borrow := userInfo.borrow *
            token.borrowIndex / userInfo.lastBorrowIndex;
          else skip;

          if repayAmountFloat = 0n
          then repayAmountFloat := userInfo.borrow;
          else skip;

          if repayAmountFloat > userInfo.borrow
          then failwith("yToken/amount-should-be-less-or-equal")
          else skip;

          userInfo.borrow := abs(
            userInfo.borrow - repayAmountFloat
          );

          userInfo.lastBorrowIndex := token.borrowIndex;
          accountUser.balances[yAssetParams.tokenId] := userInfo;
          s.accountInfo[Tezos.sender] := accountUser;
          token.totalBorrowsFloat := abs(token.totalBorrowsFloat
            - repayAmountFloat);
          token.totalLiquidFloat := token.totalLiquidFloat + repayAmountFloat;
          s.tokenInfo[yAssetParams.tokenId] := token;

          var value : nat := case ediv(repayAmountFloat, accuracy) of
            Some(result) -> if result.1 > 0n
              then result.0 + 1n
              else result.0
          | None -> failwith("error")
          end;

          operations := list [
              case token.faType of
              | FA12 -> Tezos.transaction(
                  TransferOutside(record [
                    from_ = Tezos.sender;
                    to_ = Tezos.self_address;
                    value = value
                  ]),
                  0mutez,
                  getTokenContract(token.mainToken)
                )
              | FA2(assetId) -> Tezos.transaction(
                  IterateTransferOutside(record [
                    from_ = Tezos.self_address;
                    txs = list[
                      record[
                        tokenId = assetId;
                        to_ = Tezos.self_address;
                        amount = value
                      ]
                    ]
                  ]),
                  0mutez,
                  getIterTranserContract(token.mainToken)
                )
              end
          ];
        }
      | _                         -> skip
      end
  } with (operations, s)

function liquidate(
  const p               : useAction;
  var s                 : tokenStorage)
                        : return is
  block {
    var operations : list(operation) := list[];
      case p of
        Liquidate(liquidateParams) -> {
          zeroCheck(liquidateParams.amount);

          if liquidateParams.borrowToken < s.lastTokenId
          then skip
          else failwith("yToken/yToken-undefined(borrowToken)");

          if liquidateParams.collateralToken < s.lastTokenId
          then skip
          else failwith("yToken/yToken-undefined(collateralToken)");

          var accountBorrower : account := getAccount(
            liquidateParams.borrower,
            s
          );
          var borrowToken : tokenInfo := getTokenInfo(
            liquidateParams.borrowToken,
            s
          );

          verifyTokenUpdated(borrowToken);

          if Tezos.sender = liquidateParams.borrower
          then failwith("yToken/borrower-cannot-be-liquidator")
          else skip;

          var borrowerInfo : balanceInfo := getMapInfo(
            accountBorrower.balances,
            liquidateParams.borrowToken
          );

          const maxBorrowInCU : nat = calculateMaxCollaterallInCU(
            accountBorrower,
            record[s = s; res = 0n; userAccount = accountBorrower]
          );
          const outstandingBorrowInCU : nat = calculateOutstandingBorrowInCU(
            accountBorrower,
            record[s = s; res = 0n; userAccount = accountBorrower]
          );

          if outstandingBorrowInCU > maxBorrowInCU
          then skip
          else failwith("yToken/liquidation-not-achieved");
          if borrowerInfo.borrow = 0n
          then failwith("yToken/debt-is-zero");
          else skip;

          var liqAmountFloat : nat := liquidateParams.amount * accuracy;

          if borrowerInfo.lastBorrowIndex =/= 0n
          then borrowerInfo.borrow := borrowerInfo.borrow *
            borrowToken.borrowIndex /
            borrowerInfo.lastBorrowIndex;
          else skip;

          (* liquidate amount can't be more than allowed close factor *)
          const maxClose : nat = borrowerInfo.borrow * s.closeFactorFloat
            / accuracy;

          if liqAmountFloat <= maxClose
          then skip
          else failwith("yToken/too-much-repay");

          borrowerInfo.borrow := abs(
            borrowerInfo.borrow - liqAmountFloat
          );
          borrowerInfo.lastBorrowIndex := borrowToken.borrowIndex;
          borrowToken.totalBorrowsFloat := abs(
            borrowToken.totalBorrowsFloat - liqAmountFloat
          );
          borrowToken.totalLiquidFloat := borrowToken.totalLiquidFloat + liqAmountFloat;

          accountBorrower.balances[liquidateParams.borrowToken] := borrowerInfo;

          operations := list [
              case borrowToken.faType of
              | FA12 -> Tezos.transaction(
                  TransferOutside(record [
                    from_ = Tezos.sender;
                    to_ = Tezos.self_address;
                    value = liqAmountFloat
                  ]),
                  0mutez,
                  getTokenContract(borrowToken.mainToken)
                )
              | FA2(assetId) -> Tezos.transaction(
                  IterateTransferOutside(record [
                    from_ = Tezos.self_address;
                    txs = list[
                      record[
                        tokenId = assetId;
                        to_ = Tezos.self_address;
                        amount = liqAmountFloat
                      ]
                    ]
                  ]),
                  0mutez,
                  getIterTranserContract(borrowToken.mainToken)
                )
              end
          ];

          if accountBorrower.markets contains liquidateParams.collateralToken
          then skip
          else failwith("yToken/collateralToken-not-contains-in-borrow-market");


          var collateralToken : tokenInfo := getTokenInfo(
            liquidateParams.collateralToken,
            s
          );

          verifyTokenUpdated(collateralToken);

          (* seizeAmount = actualRepayAmount * liquidationIncentive
            * priceBorrowed / priceCollateral
            seizeTokens = seizeAmount / exchangeRate
          *)
          const seizeAmount : nat = liqAmountFloat * s.liqIncentiveFloat
            * borrowToken.lastPrice * collateralToken.totalSupplyFloat;

          const exchangeRateFloat : nat = abs(
            collateralToken.totalLiquidFloat + collateralToken.totalBorrowsFloat
            - collateralToken.totalReservesFloat
          ) * accuracy * collateralToken.lastPrice;

          const seizeTokensFloat : nat = seizeAmount / exchangeRateFloat;

          var liquidatorAccount : account := getAccount(
            Tezos.sender,
            s
          );

          var borrowerCollateralInfo : balanceInfo := getMapInfo(
            accountBorrower.balances,
            liquidateParams.collateralToken
          );

          if borrowerCollateralInfo.balance < seizeTokensFloat
          then failwith("yToken/seize/not-enough-tokens")
          else skip;

          var liquidatorInfo : balanceInfo := getMapInfo(
            liquidatorAccount.balances,
            liquidateParams.collateralToken
          );
          borrowerCollateralInfo.balance := abs(borrowerCollateralInfo.balance - seizeTokensFloat);
          liquidatorInfo.balance := liquidatorInfo.balance + seizeTokensFloat;

          accountBorrower.balances[liquidateParams.collateralToken] := borrowerCollateralInfo;
          liquidatorAccount.balances[liquidateParams.collateralToken] := liquidatorInfo;
          s.accountInfo[liquidateParams.borrower] := accountBorrower;
          s.accountInfo[Tezos.sender] := liquidatorAccount;
          s.tokenInfo[liquidateParams.collateralToken] := collateralToken;
        }
      | _                         -> skip
      end
  } with (operations, s)

function enterMarket(
  const p               : useAction;
  var s                 : tokenStorage)
                        : return is
  block {
    var operations : list(operation) := list[];
      case p of
        EnterMarket(tokenId) -> {
          var userAccount : account := getAccount(Tezos.sender, s);

          if tokenId < s.lastTokenId
          then skip
          else failwith("yToken/yToken-undefined");

          if Set.size(userAccount.markets) >= s.maxMarkets
          then failwith("yToken/max-market-limit");
          else skip;

          userAccount.markets := Set.add(tokenId, userAccount.markets);
          s.accountInfo[Tezos.sender] := userAccount;
        }
      | _                         -> skip
      end
  } with (operations, s)

function exitMarket(
  const p               : useAction;
  var s                 : tokenStorage)
                        : return is
  block {
    var operations : list(operation) := list[];
      case p of
        ExitMarket(tokenId) -> {
          var userAccount : account := getAccount(Tezos.sender, s);

          if tokenId < s.lastTokenId
          then skip
          else failwith("yToken/yToken-undefined");

          var token : tokenInfo := getTokenInfo(
            tokenId,
            s
          );
          verifyTokenUpdated(token);

          userAccount.markets := Set.remove(tokenId, userAccount.markets);
          const maxBorrowInCU : nat = calculateMaxCollaterallInCU(
            userAccount,
            record[s = s; res = 0n; userAccount = userAccount]
          );
          const outstandingBorrowInCU : nat = calculateOutstandingBorrowInCU(
            userAccount,
            record[s = s; res = 0n; userAccount = userAccount]
          );

          if outstandingBorrowInCU <= maxBorrowInCU
          then s.accountInfo[Tezos.sender] := userAccount;
          else failwith("yToken/debt-not-repaid");
        }
      | _                         -> skip
      end
  } with (operations, s)

function returnPrice(
  const params          : yAssetParams;
  var s                 : fullTokenStorage)
                        : fullReturn is
  block {
    if Tezos.sender =/= s.storage.priceFeedProxy
    then failwith("yToken/permition-error");
    else skip;

    var token : tokenInfo := getTokenInfo(
      params.tokenId,
      s.storage
    );
    token.lastPrice := params.amount;
    token.priceUpdateTime := Tezos.now;
    s.storage.tokenInfo[params.tokenId] := token;
  } with (noOperations, s)

function accrueInterest(
  const params          : yAssetParams;
  var s                 : fullTokenStorage)
                        : fullReturn is
  block {

    var token : tokenInfo := getTokenInfo(params.tokenId, s.storage);
    const borrowRate : nat = params.amount;

    if Tezos.sender =/= token.interstRateModel
    then failwith("yToken/not-self-address")
    else skip;

    if borrowRate >= token.maxBorrowRate
    then failwith("yToken/borrow-rate-is-absurdly-high");
    else skip;

    //  Calculate the number of blocks elapsed since the last accrual
    const blockDelta : nat = abs(Tezos.now - token.lastUpdateTime);

    const simpleInterestFactorFloat : nat = borrowRate * blockDelta;
    const interestAccumulatedFloat : nat = simpleInterestFactorFloat *
      token.totalBorrowsFloat / accuracy;

    token.totalBorrowsFloat := interestAccumulatedFloat + token.totalBorrowsFloat;
    // one mult operation with float require accuracy division
    token.totalReservesFloat := interestAccumulatedFloat * token.reserveFactorFloat /
      accuracy + token.totalReservesFloat;
    // one mult operation with float require accuracy division
    token.borrowIndex := simpleInterestFactorFloat * token.borrowIndex /
      accuracy + token.borrowIndex;
    token.lastUpdateTime := Tezos.now;

    s.storage.tokenInfo[params.tokenId] := token;
  } with (noOperations, s)

function getReserveFactor(
  const tokenId         : tokenId;
  var s                 : fullTokenStorage)
                        : fullReturn is
  block {
    var token : tokenInfo := getTokenInfo(tokenId, s.storage);
    const operations : list(operation) = list [
      Tezos.transaction(
        UpdReserveFactor(token.reserveFactorFloat),
        0mutez,
        getReserveFactorContract(token.interstRateModel)
      )
    ];
  } with (operations, s)
