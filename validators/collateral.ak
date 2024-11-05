use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Script, from_verification_key}
use cardano/assets.{Value, flatten, lovelace_of, match}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_script_outputs,
}
use constants.{
  burn_address, min_lovelace_amount, strike_asset_name,
  strike_consume_address_hash, strike_policy_id, strike_stake_credential,
}
use types.{
  AgreementDatum, AssetClass, BothSidesDepositAgreement, CollateralDatum,
  CollateralRedeemerAction, ForwardsDatum, Issuer, LiquidateBothParties,
  LiquidateCollateral, Obligee, OneSideDepositAgreement, Party,
}
use utils.{
  get_asset_and_amount_locked_based_on_party, get_datum_based_on_party,
  get_lower_bound, get_party_has_deposited_asset, get_upper_bound,
  get_validators_inputs, signed_by_party,
}

validator collateral(agreement_validator: ScriptHash) {
  spend(
    datum: Option<CollateralDatum>,
    rdmr: CollateralRedeemerAction,
    my_output_reference: OutputReference,
    self: Transaction,
  ) {
    when rdmr is {
      OneSideDepositAgreement(deposit_party, output_index) ->
        one_side_deposit_agreement_valid(
          datum,
          self,
          deposit_party,
          my_output_reference,
          output_index,
        )

      BothSidesDepositAgreement(deposit_party) ->
        both_sides_deposit_agreement_valid(
          datum,
          self,
          deposit_party,
          agreement_validator,
        )

      LiquidateCollateral(liquidate_party) ->
        liquidate_collateral_valid(datum, self, liquidate_party)

      LiquidateBothParties(strike_consume_output_index) ->
        liquidate_both_parties_valid(datum, self, strike_consume_output_index)
    }
  }

  else(_) {
    fail
  }
}

fn one_side_deposit_agreement_valid(
  maybe_datum: Option<CollateralDatum>,
  transaction: Transaction,
  deposit_party: Party,
  my_output_reference: OutputReference,
  output_index: Int,
) {
  expect Some(datum) = maybe_datum

  let Transaction { inputs, outputs, validity_range, .. } = transaction

  let CollateralDatum { obligee_address_hash, .. } = datum

  let ForwardsDatum {
    exercise_contract_date,
    collateral_asset,
    mint_asset_policy_id,
    issuer_deposit_asset,
    issuer_deposit_asset_amount,
    obligee_deposit_asset,
    obligee_deposit_asset_amount,
    each_party_strike_collateral_asset_amount,
    issuer_address_hash,
    ..
  } = datum.associated_forwards_datum

  expect Some(input_from_validator) =
    inputs
      |> transaction.find_input(my_output_reference)

  expect Some(output_to_validator) = list.at(outputs, output_index)

  let output_address_valid =
    output_to_validator.address == input_from_validator.output.address

  expect InlineDatum(output_datum) = output_to_validator.datum

  let expected_new_datum = get_datum_based_on_party(datum, deposit_party)
  let expected_new_datum_data: Data = expected_new_datum

  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1

  let updated_datum_correct: Bool = output_datum == expected_new_datum_data

  let deadline_not_passed: Bool =
    exercise_contract_date > get_upper_bound(validity_range)

  let (expected_asset_locked, expected_asset_amount_locked) =
    get_asset_and_amount_locked_based_on_party(
      deposit_party,
      issuer_deposit_asset,
      issuer_deposit_asset_amount,
      obligee_deposit_asset,
      obligee_deposit_asset_amount,
    )

  let expected_assets_locked: Value =
    assets.from_lovelace(lovelace_of(input_from_validator.output.value))
      |> assets.add(
          collateral_asset.policy_id,
          collateral_asset.asset_name,
          expected_asset_amount_locked,
        )
      |> assets.add(mint_asset_policy_id, issuer_address_hash, 1)
      |> assets.add(mint_asset_policy_id, obligee_address_hash, 1)
      |> assets.add(
          expected_asset_locked.policy_id,
          expected_asset_locked.asset_name,
          expected_asset_amount_locked,
        )

  let ref_script_empty = output_to_validator.reference_script == None

  let no_side_has_deposited_asset: Bool =
    !datum.issuer_has_deposited_asset && !datum.obligee_has_deposited_asset

  let signed_transaction: Bool =
    signed_by_party(transaction, deposit_party, datum)

  expect
    only_one_validator_input && updated_datum_correct && deadline_not_passed && ref_script_empty && no_side_has_deposited_asset && signed_transaction && output_address_valid

  let strike_is_used_as_collateral: Bool =
    each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let expected_assets_locked_with_strike: Value =
      expected_assets_locked
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            each_party_strike_collateral_asset_amount,
          )

    let assets_match =
      match(output_to_validator.value, expected_assets_locked_with_strike, >=)

    assets_match
  } else {
    let assets_match =
      match(output_to_validator.value, expected_assets_locked, >=)

    assets_match
  }
}

fn both_sides_deposit_agreement_valid(
  datum: Option<CollateralDatum>,
  transaction: Transaction,
  deposit_party: Party,
  agreement_validator: ScriptHash,
) {
  let Transaction { outputs, validity_range, .. } = transaction

  expect Some(datum) = datum
  let CollateralDatum {
    issuer_has_deposited_asset,
    obligee_has_deposited_asset,
    obligee_address_hash,
    ..
  } = datum

  let ForwardsDatum {
    exercise_contract_date,
    mint_asset_policy_id,
    issuer_address_hash,
    issuer_deposit_asset,
    issuer_deposit_asset_amount,
    obligee_deposit_asset,
    obligee_deposit_asset_amount,
    ..
  } = datum.associated_forwards_datum

  if deposit_party == Issuer {
    expect obligee_has_deposited_asset
  } else {
    expect issuer_has_deposited_asset
  }

  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1

  let outputs_to_consume_forwards_validator: List<Output> =
    find_script_outputs(outputs, agreement_validator)
  let two_outputs_to_agreement_validator: Bool =
    list.length(outputs_to_consume_forwards_validator) == 2

  expect [expected_issuer_utxo,
    expected_obligee_utxo] = find_script_outputs(outputs, agreement_validator)

  let expected_issuer_datum =
    AgreementDatum {
      utxo_owner_address_hash: issuer_address_hash,
      associated_forwards_datum: datum.associated_forwards_datum,
    }

  let expected_issuer_datum_as_data: Data = expected_issuer_datum

  expect InlineDatum(issuer_datum) = expected_issuer_utxo.datum

  let issuer_datum_match: Bool = expected_issuer_datum_as_data == issuer_datum

  let expected_issuer_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(mint_asset_policy_id, issuer_address_hash, 1)
      |> assets.add(
          obligee_deposit_asset.policy_id,
          obligee_deposit_asset.asset_name,
          obligee_deposit_asset_amount,
        )

  let expected_issuer_assets_locked_match: Bool =
    match(expected_issuer_utxo.value, expected_issuer_assets_locked, >=)

  let expected_obligee_datum =
    AgreementDatum {
      utxo_owner_address_hash: obligee_address_hash,
      associated_forwards_datum: datum.associated_forwards_datum,
    }

  expect InlineDatum(obligee_datum) = expected_obligee_utxo.datum

  let expected_obligee_datum_as_data: Data = expected_obligee_datum

  let obligee_datum_match: Bool =
    expected_obligee_datum_as_data == obligee_datum

  let expected_obligee_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(obligee_address_hash, obligee_address_hash, 1)
      |> assets.add(
          issuer_deposit_asset.policy_id,
          issuer_deposit_asset.asset_name,
          issuer_deposit_asset_amount,
        )

  let expected_obligee_assets_locked_match: Bool =
    match(expected_obligee_utxo.value, expected_obligee_assets_locked, >=)

  let deadline_not_passed: Bool =
    exercise_contract_date > get_upper_bound(validity_range)

  expect Some(obligee_stake_credential) =
    expected_obligee_utxo.address.stake_credential

  expect Some(issuer_stake_credential) =
    expected_issuer_utxo.address.stake_credential

  let stake_credential_is_valid: Bool =
    obligee_stake_credential == strike_stake_credential && issuer_stake_credential == strike_stake_credential

  let obligee_ref_script_empty = expected_obligee_utxo.reference_script == None

  let issuer_ref_script_empty = expected_issuer_utxo.reference_script == None

  let signed_transaction: Bool =
    signed_by_party(transaction, deposit_party, datum)

  stake_credential_is_valid && only_one_validator_input && two_outputs_to_agreement_validator && deadline_not_passed && obligee_ref_script_empty && issuer_ref_script_empty && expected_obligee_assets_locked_match && expected_issuer_assets_locked_match && issuer_datum_match && obligee_datum_match && signed_transaction
}

fn liquidate_collateral_valid(
  datum: Option<CollateralDatum>,
  transaction: Transaction,
  liquidate_party: Party,
) {
  let Transaction { mint, outputs, validity_range, .. } = transaction

  expect Some(datum) = datum

  let CollateralDatum { obligee_address_hash, .. } = datum

  let ForwardsDatum {
    exercise_contract_date,
    mint_asset_policy_id,
    issuer_address_hash,
    each_party_strike_collateral_asset_amount,
    ..
  } = datum.associated_forwards_datum

  let signed_transaction: Bool =
    signed_by_party(transaction, liquidate_party, datum)

  let party_has_deposited_asset: Bool =
    get_party_has_deposited_asset(datum, liquidate_party)

  let deadline_has_passed: Bool =
    exercise_contract_date < get_lower_bound(validity_range)

  let expected_mint =
    [
      (mint_asset_policy_id, issuer_address_hash, -1),
      (mint_asset_policy_id, obligee_address_hash, -1),
    ]

  let valid_mint: Bool = expected_mint == flatten(mint)

  let only_one_validator_input =
    list.length(get_validators_inputs(transaction)) == 1

  expect
    deadline_has_passed && party_has_deposited_asset && valid_mint && signed_transaction && only_one_validator_input

  let strike_is_used_as_collateral: Bool =
    each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    expect Some(output_to_burn_address) =
      list.find(
        outputs,
        fn(output) {
          expect Script(output_to_liquidate_hash) =
            output.address.payment_credential

          output_to_liquidate_hash == burn_address
        },
      )

    let expected_strike_collateral_asset_burnt: Value =
      assets.from_lovelace(lovelace_of(output_to_burn_address.value))
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            each_party_strike_collateral_asset_amount,
          )

    let strike_collateral_asset_burnt: Bool =
      match(
        output_to_burn_address.value,
        expected_strike_collateral_asset_burnt,
        >=,
      )

    strike_collateral_asset_burnt
  } else {
    True
  }
}

pub fn liquidate_both_parties_valid(
  datum: Option<CollateralDatum>,
  transaction: Transaction,
  strike_consume_output_index: Int,
) {
  let Transaction { mint, outputs, validity_range, .. } = transaction

  expect Some(datum) = datum

  let CollateralDatum { obligee_address_hash, .. } = datum

  let ForwardsDatum {
    exercise_contract_date,
    collateral_asset,
    mint_asset_policy_id,
    each_party_strike_collateral_asset_amount,
    issuer_address_hash,
    ..
  } = datum.associated_forwards_datum

  let deadline_has_passed: Bool =
    exercise_contract_date < get_lower_bound(validity_range)

  let strike_address = from_verification_key(strike_consume_address_hash)

  expect Some(output_send_to_strike_consume_address) =
    list.at(outputs, strike_consume_output_index)

  let output_is_to_strike_consume_address =
    output_send_to_strike_consume_address.address == strike_address

  let expected_assets_to_strike: Value =
    assets.from_lovelace(
      lovelace_of(output_send_to_strike_consume_address.value),
    )
      |> assets.add(
          collateral_asset.policy_id,
          collateral_asset.asset_name,
          each_party_strike_collateral_asset_amount * 2,
        )

  let collateral_assets_sent: Bool =
    match(
      output_send_to_strike_consume_address.value,
      expected_assets_to_strike,
      >=,
    )

  let both_party_has_not_deposited_asset: Bool =
    !get_party_has_deposited_asset(datum, Issuer) && !get_party_has_deposited_asset(
      datum,
      Obligee,
    )

  let expected_mint =
    [
      (mint_asset_policy_id, issuer_address_hash, -1),
      (mint_asset_policy_id, obligee_address_hash, -1),
    ]

  let valid_mint: Bool = expected_mint == flatten(mint)

  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1

  expect
    deadline_has_passed && collateral_assets_sent && both_party_has_not_deposited_asset && valid_mint && only_one_validator_input && output_is_to_strike_consume_address

  if each_party_strike_collateral_asset_amount > 0 {
    expect Some(output_to_burn_address) =
      list.find(
        outputs,
        fn(output) {
          expect Script(output_to_liquidate_hash) =
            output.address.payment_credential

          output_to_liquidate_hash == burn_address
        },
      )

    let expected_strike_collateral_asset_burnt: Value =
      assets.from_lovelace(lovelace_of(output_to_burn_address.value))
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            each_party_strike_collateral_asset_amount * 2,
          )

    let strike_collateral_asset_burnt: Bool =
      match(
        output_to_burn_address.value,
        expected_strike_collateral_asset_burnt,
        >=,
      )

    strike_collateral_asset_burnt
  } else {
    True
  }
}
