use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Input, Output, ScriptContext, ValidityRange}
use aiken/transaction/credential.{Address, Credential, ScriptCredential}
use aiken/transaction/value.{AssetName, PolicyId, quantity_of}
use types.{AddressHash, AssetClass, CollateralDatum}

pub fn is_script_credential(credential: Credential) -> Bool {
  when credential is {
    ScriptCredential(_validator_hash) -> True
    _ -> False
  }
}

pub fn get_validators_inputs(ctx: ScriptContext) -> List<Input> {
  list.filter(
    ctx.transaction.inputs,
    fn(input) { is_script_credential(input.output.address.payment_credential) },
  )
}

pub fn get_lower_bound(range: ValidityRange) -> Int {
  expect Finite(lower_bound) = range.lower_bound.bound_type
  lower_bound
}

pub fn get_validators_outputs(ctx: ScriptContext) -> List<Output> {
  list.filter(
    ctx.transaction.outputs,
    fn(output) { is_script_credential(output.address.payment_credential) },
  )
}

pub fn get_address_outputs(ctx: ScriptContext, address: Address) -> List<Output> {
  list.filter(ctx.transaction.outputs, fn(output) { output.address == address })
}

pub fn get_datum_based_on_party(
  datum: CollateralDatum,
  deposit_party: Int,
) -> CollateralDatum {
  let is_issuer = deposit_party == 0
  if is_issuer {
    let expected_new_datum =
      CollateralDatum {
        issuer_address_hash: datum.issuer_address_hash,
        issuer_has_deposited_asset: True,
        issuer_deposit_asset: datum.issuer_deposit_asset,
        issuer_deposit_asset_amount: datum.issuer_deposit_asset_amount,
        obligee_address_hash: datum.obligee_address_hash,
        obligee_has_deposited_asset: False,
        obligee_deposit_asset: datum.obligee_deposit_asset,
        obligee_deposit_asset_amount: datum.obligee_deposit_asset_amount,
        collateral_asset: datum.collateral_asset,
        each_party_collateral_asset_amount: datum.each_party_collateral_asset_amount,
        strike_collateral_asset: datum.strike_collateral_asset,
        each_party_strike_collateral_asset_amount: datum.each_party_strike_collateral_asset_amount,
        exercise_contract_date: datum.exercise_contract_date,
      }
    expected_new_datum
  } else {
    let expected_new_datum =
      CollateralDatum {
        issuer_address_hash: datum.issuer_address_hash,
        issuer_has_deposited_asset: False,
        obligee_address_hash: datum.obligee_address_hash,
        obligee_has_deposited_asset: True,
        issuer_deposit_asset: datum.issuer_deposit_asset,
        issuer_deposit_asset_amount: datum.issuer_deposit_asset_amount,
        obligee_deposit_asset: datum.obligee_deposit_asset,
        obligee_deposit_asset_amount: datum.obligee_deposit_asset_amount,
        collateral_asset: datum.collateral_asset,
        each_party_collateral_asset_amount: datum.each_party_collateral_asset_amount,
        strike_collateral_asset: datum.strike_collateral_asset,
        each_party_strike_collateral_asset_amount: datum.each_party_strike_collateral_asset_amount,
        exercise_contract_date: datum.exercise_contract_date,
      }
    expected_new_datum
  }
}

pub fn get_asset_locked_based_on_party(
  datum: CollateralDatum,
  deposit_party: Int,
) -> AssetClass {
  let is_issuer = deposit_party == 0
  if is_issuer {
    datum.issuer_deposit_asset
  } else {
    datum.obligee_deposit_asset
  }
}

pub fn get_asset_amount_locked_based_on_party(
  datum: CollateralDatum,
  deposit_party: Int,
) -> Int {
  let is_issuer = deposit_party == 0
  if is_issuer {
    datum.issuer_deposit_asset_amount
  } else {
    datum.obligee_deposit_asset_amount
  }
}

pub fn get_address_hash_based_on_party(
  datum: CollateralDatum,
  deposit_party: Int,
) -> AddressHash {
  let is_issuer = deposit_party == 0
  if is_issuer {
    datum.issuer_address_hash
  } else {
    datum.obligee_address_hash
  }
}

pub fn get_party_has_deposited_asset(
  datum: CollateralDatum,
  deposit_party: Int,
) -> Bool {
  let is_issuer = deposit_party == 0
  if is_issuer {
    datum.issuer_has_deposited_asset
  } else {
    datum.obligee_has_deposited_asset
  }
}

pub fn get_asset_to_address(
  outputs: List<Output>,
  address: Address,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Int {
  let output_to_address =
    list.find(
      outputs,
      fn(output) {
        output.address.payment_credential == address.payment_credential
      },
    )

  when output_to_address is {
    Some(output) -> quantity_of(output.value, policy_id, asset_name)
    None -> 0
  }
}

pub fn get_asset_to_address_valid(
  datum: CollateralDatum,
  party: Int,
  outputs: List<Output>,
  address: Address,
) -> Bool {
  let is_issuer = party == 0
  if is_issuer {
    let amount_to_issuer =
      get_asset_to_address(
        outputs,
        address,
        datum.issuer_deposit_asset.policy_id,
        datum.issuer_deposit_asset.asset_name,
      )
    amount_to_issuer == datum.issuer_deposit_asset_amount
  } else {
    let amount_to_obligee =
      get_asset_to_address(
        outputs,
        address,
        datum.obligee_deposit_asset.policy_id,
        datum.obligee_deposit_asset.asset_name,
      )
    amount_to_obligee == datum.obligee_deposit_asset_amount
  }
}
