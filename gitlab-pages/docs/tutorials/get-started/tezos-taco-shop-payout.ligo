type taco_supply is
  record [
    current_stock : nat;
    max_price     : tez
  ]

type taco_shop_storage is map (nat, taco_supply)

type return is list (operation) * taco_shop_storage

const ownerAddress : address = "tz1TGu6TN5GSez2ndXXeDX6LgUDvLzPLqgYV"
const donationAddress : address = "tz1KqTpEZ7Yob7QbPE4Hy4Wo8fHG8LhKxZSx"

function buy_taco (const taco_kind_index : nat; var taco_shop_storage : taco_shop_storage) : return is
  block {
    // Retrieve the taco_kind from the contract's storage or fail
    const taco_kind : taco_supply =
      case taco_shop_storage[taco_kind_index] of
        Some (kind) -> kind
      | None -> (failwith ("Unknown kind of taco.") : taco_supply)
      end;

    const current_purchase_price : tez =
      taco_kind.max_price / taco_kind.current_stock;

    if amount =/= current_purchase_price then
      // We won't sell tacos if the amount is not correct
      failwith ("Sorry, the taco you are trying to purchase has a different price");
    else skip;

    // Decrease the stock by 1n, because we have just sold one
    taco_kind.current_stock := abs (taco_kind.current_stock - 1n);

    // Update the storage with the refreshed taco_kind
    taco_shop_storage[taco_kind_index] := taco_kind;

    const receiver : contract (unit) = get_contract (ownerAddress);
    const donationReceiver : contract (unit) = get_contract (donationAddress);

    const donationAmount : tez = amount / 10n;

    const operations : list (operation) = list [
      transaction (unit, amount - donationAmount, receiver);
      transaction (unit, donationAmount, donationReceiver);
    ]
  } with (operations, taco_shop_storage)
