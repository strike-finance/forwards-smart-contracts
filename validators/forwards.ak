use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId, Value, flatten, match}
use cardano/transaction.{InlineDatum, Output, Transaction}
use constants.{
  min_lovelace_amount, strike_asset_name, strike_policy_id,
  strike_stake_credential,
}
use types.{
  AcceptForwardsContract, CancelForwardsContract, CollateralDatum,
  CreateForwardMint, EnterForwardMint, ForwardsDatum, ForwardsRedeemer,
  LiquidateBurn, MintRedeemer, SingleBurn,
}
use utils.{get_script_hash, get_upper_bound, get_validators_inputs}

validator forwards(collateral_validator: ByteArray, asset_name: AssetName) {
  spend(
    datum: Option<ForwardsDatum>,
    redeemer: ForwardsRedeemer,
    _0: Data,
    transaction: Transaction,
  ) {
    when redeemer is {
      AcceptForwardsContract(obligee_address_hash, output_index) ->
        accept_forwards_contract_valid(
          datum,
          transaction,
          collateral_validator,
          obligee_address_hash,
          output_index,
        )

      CancelForwardsContract ->
        cancel_forwards_contract_valid(datum, transaction)
    }
  }

  mint(rdmr: MintRedeemer, policy_id: PolicyId, transaction: Transaction) {
    when rdmr is {
      CreateForwardMint(output_index) ->
        create_forward_mint_valid(transaction, policy_id, output_index)
      EnterForwardMint(obligee_address_hash, output_index) ->
        enter_forward_mint_valid(
          transaction,
          policy_id,
          output_index,
          obligee_address_hash,
        )
      SingleBurn -> single_burn_valid(transaction, policy_id, asset_name)
      LiquidateBurn -> liquidate_burn_valid(transaction, policy_id, asset_name)
    }
  }

  else(_) {
    fail
  }
}

fn accept_forwards_contract_valid(
  maybe_datum: Option<ForwardsDatum>,
  transaction: Transaction,
  collateral_validator: ByteArray,
  obligee_address_hash: VerificationKeyHash,
  output_index: Int,
) {
  let Transaction { outputs, validity_range, .. } = transaction

  expect Some(datum) = maybe_datum

  let ForwardsDatum {
    collateral_asset,
    each_party_collateral_asset_amount,
    each_party_strike_collateral_asset_amount,
    exercise_contract_date,
    mint_asset,
    ..
  } = datum

  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1

  expect Some(output_to_collateral_utxo) = list.at(outputs, output_index)

  expect Script(output_to_collateral_hash) =
    output_to_collateral_utxo.address.payment_credential

  let output_is_to_collateral_validator: Bool =
    output_to_collateral_hash == collateral_validator

  let expected_collateral_datum =
    CollateralDatum {
      issuer_has_deposited_asset: False,
      obligee_address_hash,
      obligee_has_deposited_asset: False,
      associated_forwards_datum: datum,
    }

  let datum_as_data: Data = expected_collateral_datum

  expect InlineDatum(output_datum) = output_to_collateral_utxo.datum

  let expected_collateral_datum_match: Bool = output_datum == datum_as_data

  let expected_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(
          collateral_asset.policy_id,
          collateral_asset.asset_name,
          each_party_collateral_asset_amount * 2,
        )
      |> assets.add(mint_asset.policy_id, mint_asset.asset_name, 2)

  expect Some(output_to_collateral_stake_credential) =
    output_to_collateral_utxo.address.stake_credential

  let stake_credential_is_valid: Bool =
    output_to_collateral_stake_credential == strike_stake_credential

  let deadline_not_passed =
    exercise_contract_date > get_upper_bound(validity_range)

  let ref_script_empty = output_to_collateral_utxo.reference_script == None

  expect
    only_one_validator_input && stake_credential_is_valid && deadline_not_passed && ref_script_empty && expected_collateral_datum_match && output_is_to_collateral_validator

  let strike_is_used_as_collateral: Bool =
    each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let expected_asset_locked_with_strike: Value =
      expected_assets_locked
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            each_party_strike_collateral_asset_amount * 2,
          )

    let assets_match: Bool =
      match(
        output_to_collateral_utxo.value,
        expected_asset_locked_with_strike,
        >=,
      )

    assets_match
  } else {
    let assets_match: Bool =
      match(output_to_collateral_utxo.value, expected_assets_locked, >=)

    assets_match
  }
}

// asset is burnt and signed by issuer
fn cancel_forwards_contract_valid(
  maybe_datum: Option<ForwardsDatum>,
  transaction: Transaction,
) {
  expect Some(datum) = maybe_datum

  let Transaction { extra_signatories, mint, .. } = transaction

  let ForwardsDatum { issuer_address_hash, mint_asset, .. } = datum

  let only_one_validator_input =
    list.length(get_validators_inputs(transaction)) == 1

  let must_be_signed_by_issuer =
    list.has(extra_signatories, issuer_address_hash)

  let expected_mint = [(mint_asset.policy_id, mint_asset.asset_name, -1)]
  let valid_mint = expected_mint == flatten(mint)
  must_be_signed_by_issuer && valid_mint && only_one_validator_input
}

fn create_forward_mint_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  output_index: Int,
) -> Bool {
  let Transaction { mint, outputs, validity_range, .. } = transaction

  expect Some(Output {
    value: output_to_forward_contract_value,
    datum: InlineDatum(output_datum),
    address: output_to_contract_address,
    reference_script,
  }) = list.at(outputs, output_index)

  expect output_datum_typed: ForwardsDatum = output_datum

  let ForwardsDatum {
    collateral_asset,
    each_party_collateral_asset_amount,
    exercise_contract_date,
    issuer_deposit_asset,
    obligee_deposit_asset,
    issuer_deposit_asset_amount,
    obligee_deposit_asset_amount,
    mint_asset,
    each_party_strike_collateral_asset_amount,
    ..
  } = output_datum_typed

  let output_script_hash: ScriptHash =
    get_script_hash(output_to_contract_address)

  let output_is_to_forward_validator: Bool = output_script_hash == policy_id

  expect Some(output_to_collateral_stake_credential) =
    output_to_contract_address.stake_credential

  let stake_credential_is_valid: Bool =
    output_to_collateral_stake_credential == strike_stake_credential

  let expected_mint = [(policy_id, asset_name, 1)]

  let valid_mint: Bool = expected_mint == flatten(mint)

  let expected_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(
          collateral_asset.policy_id,
          collateral_asset.asset_name,
          each_party_collateral_asset_amount,
        )
      |> assets.add(policy_id, asset_name, 1)

  let ref_script_empty = reference_script == None

  let deadline_not_passed =
    exercise_contract_date > get_upper_bound(validity_range)

  let issuer_and_obligee_asset_different: Bool =
    issuer_deposit_asset != obligee_deposit_asset

  let issuer_asset_positive: Bool = issuer_deposit_asset_amount > 0

  let obligee_asset_positive: Bool = obligee_deposit_asset_amount > 0

  let mint_asset_valid =
    mint_asset.policy_id == policy_id && mint_asset.asset_name == asset_name

  expect
    valid_mint && output_is_to_forward_validator && stake_credential_is_valid && ref_script_empty && deadline_not_passed && issuer_and_obligee_asset_different && issuer_asset_positive && obligee_asset_positive && mint_asset_valid

  let strike_is_used_as_collateral: Bool =
    each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let expected_assets_locked_with_strike: Value =
      expected_assets_locked
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            output_datum_typed.each_party_strike_collateral_asset_amount,
          )

    let assets_match =
      match(
        output_to_forward_contract_value,
        expected_assets_locked_with_strike,
        >=,
      )

    assets_match
  } else {
    let assets_match =
      match(output_to_forward_contract_value, expected_assets_locked, >=)

    assets_match
  }
}

fn enter_forward_mint_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  output_index: Int,
  obligee_address_hash: VerificationKeyHash,
) -> Bool {
  let Transaction { mint, .. } = transaction

  let all_inputs_from_script = get_validators_inputs(transaction)

  let only_one_validator_input: Bool = list.length(all_inputs_from_script) == 1

  expect Some(input) = list.at(all_inputs_from_script, output_index)

  let input_is_from_forward_validator: Bool =
    get_script_hash(input.output.address) == policy_id

  let expected_mint = [(policy_id, obligee_address_hash, 1)]
  let valid_mint = expected_mint == flatten(mint)

  valid_mint && only_one_validator_input && input_is_from_forward_validator
}

fn single_burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Bool {
  burn_valid(transaction, policy_id, asset_name, 1)
}

fn liquidate_burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  asset_name: AssetName,
) -> Bool {
  burn_valid(transaction, policy_id, asset_name, 2)
}

fn burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  asset_name: AssetName,
  burnt_amount: Int,
) -> Bool {
  let Transaction { mint, .. } = transaction

  let mint_asset = [(policy_id, asset_name, -burnt_amount)]
  let valid_mint = mint_asset == flatten(mint)

  valid_mint
}
