function getFA12Transfer(
  const tokenAddress    : address)
                        : contract(transferType) is
  case(
    Tezos.get_entrypoint_opt("%transfer", tokenAddress)
                        : option(contract(transferType))
  ) of
    Some(contr) -> contr
    | None -> (
      failwith("token/cant-get-contract-token") : contract(transferType)
    )
  end;

function getFA2Transfer(
  const tokenAddress    : address)
                        : contract(iterTransferType) is
  case(
    Tezos.get_entrypoint_opt("%transfer", tokenAddress)
                        : option(contract(iterTransferType))
  ) of
    Some(contr) -> contr
    | None -> (
      failwith("token/cant-get-contract-fa2-token") : contract(iterTransferType)
    )
  end;

function wrap_fa12_transfer_trx(
  const from_           : address;
  const to_             : address;
  const amt             : nat)
                        : transferType is
  TransferOutside((from_, (to_, amt)))

function wrap_fa2_transfer_trx(
  const from_           : address;
  const to_             : address;
  const amt             : nat;
  const id              : nat)
                        : iterTransferType is
  FA2TransferOutside(list[(from_, list[
        (to_, (id, amt))
    ])])

function transfer_fa12(
  const from_           : address;
  const to_             : address;
  const amt             : nat;
  const token           : address)
                        : list(operation) is
  list[Tezos.transaction(
    wrap_fa12_transfer_trx(from_, to_, amt),
    0mutez,
    getFA12Transfer(token)
  )];

function transfer_fa2(
  const from_           : address;
  const to_             : address;
  const amt             : nat;
  const token           : address;
  const id              : nat)
                        : list(operation) is
  list[Tezos.transaction(
    wrap_fa2_transfer_trx(from_, to_, amt, id),
    0mutez,
    getFA2Transfer(token)
  )];

function transfer_token(
  const from_           : address;
  const to_             : address;
  const amt             : nat;
  const token           : assetType)
                        : list(operation) is
  case token of
    FA12(token) -> transfer_fa12(from_, to_, amt, token)
  | FA2(token)  -> transfer_fa2(from_, to_, amt, token.0, token.1)
  end