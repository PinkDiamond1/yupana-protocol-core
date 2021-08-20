type rateStorage        is [@layout:comb] record [
  admin                 : address;
  yToken                : address;
  kickRate              : nat;
  baseRate              : nat;
  multiplier            : nat;
  jumpMultiplier        : nat;
  reserveFactor         : nat;
]

type setCoeffParams     is record [
  kickRate              : nat;
  baseRate              : nat;
  multiplier            : nat;
  jumpMultiplier        : nat;
]

type rateParams         is [@layout:comb] record [
  tokenId               : nat;
  borrows               : nat;
  cash                  : nat;
  reserves              : nat;
  contract              : contract(mainParams);
]

type supplyRateParams   is [@layout:comb] record [
  tokenId               : nat;
  borrows               : nat;
  cash                  : nat;
  reserves              : nat;
  contract              : contract(mainParams);
]

