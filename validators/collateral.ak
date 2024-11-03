use aiken/builtin
use aiken/collection/list
use cardano/address.{StakeCredential, from_verification_key}
use cardano/assets.{AssetName, PolicyId, Value, lovelace_of, match}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_script_outputs,
}
use constants.{min_lovelace_amount}
use types.{
  AddressHash, AgreementDatum, AssetClass, BothSidesDepositAgreement,
  CollateralDatum, CollateralRedeemerAction, LiquidateBothParties,
  LiquidateCollateral, OneSideDepositAgreement, ScriptHash,
}
use utils.{
  get_address_hash_based_on_party, get_address_outputs,
  get_asset_amount_locked_based_on_party, get_asset_locked_based_on_party,
  get_datum_based_on_party, get_lower_bound, get_party_has_deposited_asset,
  get_upper_bound, get_validators_inputs, ref_script_empty, validate_token_mint,
}

fn one_side_deposit_agreement(
  datum: Option<CollateralDatum>,
  transaction: Transaction,
  deposit_party: Int,
  my_output_reference: OutputReference,
  strike_policy_id: PolicyId,
  strike_asset_name: AssetName,
  strike_stake_credential: StakeCredential,
) {
  expect Some(datum) = datum

  // // update the collateral datum, to say true, check the asset has actually been deposited, make sure deadline not passed, and it has not been deposited already 
  expect Some(input_from_validator) =
    transaction.inputs
      |> transaction.find_input(my_output_reference)
  let outputs_to_validator: List<Output> =
    get_address_outputs(transaction, input_from_validator.output.address)
  expect Some(output_to_validator) = list.at(outputs_to_validator, 0)
  expect InlineDatum(output_datum) = output_to_validator.datum
  expect output_datum_typed: CollateralDatum = output_datum

  let expected_new_datum = get_datum_based_on_party(datum, deposit_party)

  let only_one_validator_output: Bool = list.length(outputs_to_validator) == 1
  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1

  let updated_datum_correct: Bool = output_datum_typed == expected_new_datum

  let deadline_not_passed: Bool =
    datum.exercise_contract_date > get_upper_bound(transaction.validity_range)

  let expected_asset_locked: AssetClass =
    get_asset_locked_based_on_party(datum, deposit_party)

  let expected_asset_amount_locked: Int =
    get_asset_amount_locked_based_on_party(datum, deposit_party)

  let expected_assets_locked: Value =
    assets.from_lovelace(lovelace_of(input_from_validator.output.value))
      |> assets.add(
          output_datum_typed.collateral_asset.policy_id,
          output_datum_typed.collateral_asset.asset_name,
          output_datum_typed.each_party_collateral_asset_amount,
        )
      |> assets.add(datum.mint_asset.policy_id, datum.mint_asset.asset_name, 2)
      |> assets.add(
          expected_asset_locked.policy_id,
          expected_asset_locked.asset_name,
          expected_asset_amount_locked,
        )

  expect Some(output_stake_credential) =
    output_to_validator.address.stake_credential

  let stake_credential_is_valid =
    output_stake_credential == strike_stake_credential

  let ref_script_empty = ref_script_empty(output_to_validator)

  let no_side_has_deposited_asset: Bool =
    !datum.issuer_has_deposited_asset && !datum.obligee_has_deposited_asset

  expect
    stake_credential_is_valid && only_one_validator_input && only_one_validator_output && updated_datum_correct && deadline_not_passed && ref_script_empty && no_side_has_deposited_asset

  let strike_is_used_as_collateral: Bool =
    datum.each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let expected_assets_locked_with_strike: Value =
      expected_assets_locked
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            datum.each_party_strike_collateral_asset_amount,
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

fn both_sides_deposit_agreement(
  datum: Option<CollateralDatum>,
  transaction: Transaction,
  agreement_validator: ScriptHash,
  strike_stake_credential: StakeCredential,
) {
  expect Some(datum) = datum

  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1

  let outputs_to_consume_forwards_validator: List<Output> =
    find_script_outputs(transaction.outputs, agreement_validator)
  let two_outputs_to_agreement_validator: Bool =
    list.length(outputs_to_consume_forwards_validator) == 2

  expect [expected_issuer_utxo,
    expected_obligee_utxo] =
    find_script_outputs(transaction.outputs, agreement_validator)

  let expected_issuer_datum =
    AgreementDatum {
      issuer_address_hash: datum.issuer_address_hash,
      utxo_owner_address_hash: datum.issuer_address_hash,
      issuer_deposit_asset: datum.issuer_deposit_asset,
      issuer_deposit_asset_amount: datum.issuer_deposit_asset_amount,
      obligee_deposit_asset: datum.obligee_deposit_asset,
      obligee_deposit_asset_amount: datum.obligee_deposit_asset_amount,
      collateral_asset: datum.collateral_asset,
      collateral_asset_amount: datum.each_party_collateral_asset_amount,
      exercise_contract_date: datum.exercise_contract_date,
      mint_asset: datum.mint_asset,
    }

  let expected_issuer_datum_as_data: Data =
    builtin.serialise_data(expected_issuer_datum)

  expect InlineDatum(issuer_datum) = expected_issuer_utxo.datum

  let issuer_datum_match: Bool = expected_issuer_datum_as_data == issuer_datum

  let expected_issuer_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(datum.mint_asset.policy_id, datum.mint_asset.asset_name, 1)
      |> assets.add(
          datum.obligee_deposit_asset.policy_id,
          datum.obligee_deposit_asset.asset_name,
          datum.obligee_deposit_asset_amount,
        )

  let expected_issuer_assets_locked_match: Bool =
    match(expected_issuer_utxo.value, expected_issuer_assets_locked, >=)

  let expected_obligee_datum =
    AgreementDatum {
      issuer_address_hash: datum.issuer_address_hash,
      utxo_owner_address_hash: datum.obligee_address_hash,
      issuer_deposit_asset: datum.issuer_deposit_asset,
      issuer_deposit_asset_amount: datum.issuer_deposit_asset_amount,
      obligee_deposit_asset: datum.obligee_deposit_asset,
      obligee_deposit_asset_amount: datum.obligee_deposit_asset_amount,
      collateral_asset: datum.collateral_asset,
      collateral_asset_amount: datum.each_party_collateral_asset_amount,
      exercise_contract_date: datum.exercise_contract_date,
      mint_asset: datum.mint_asset,
    }

  expect InlineDatum(obligee_datum) = expected_obligee_utxo.datum

  let expected_obligee_datum_as_data: Data =
    builtin.serialise_data(expected_obligee_datum)

  let obligee_datum_match: Bool =
    expected_obligee_datum_as_data == obligee_datum

  let expected_obligee_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(datum.mint_asset.policy_id, datum.mint_asset.asset_name, 1)
      |> assets.add(
          datum.issuer_deposit_asset.policy_id,
          datum.issuer_deposit_asset.asset_name,
          datum.issuer_deposit_asset_amount,
        )

  let expected_obligee_assets_locked_match: Bool =
    match(expected_obligee_utxo.value, expected_obligee_assets_locked, >=)

  let deadline_not_passed: Bool =
    datum.exercise_contract_date > get_upper_bound(transaction.validity_range)

  expect Some(obligee_stake_credential) =
    expected_obligee_utxo.address.stake_credential

  expect Some(issuer_stake_credential) =
    expected_issuer_utxo.address.stake_credential

  let stake_credential_is_valid: Bool =
    obligee_stake_credential == strike_stake_credential && issuer_stake_credential == strike_stake_credential

  let obligee_ref_script_empty = ref_script_empty(expected_obligee_utxo)

  let issuer_ref_script_empty = ref_script_empty(expected_issuer_utxo)

  stake_credential_is_valid && only_one_validator_input && two_outputs_to_agreement_validator && deadline_not_passed && obligee_ref_script_empty && issuer_ref_script_empty && expected_obligee_assets_locked_match && expected_issuer_assets_locked_match && issuer_datum_match && obligee_datum_match
}

fn liquidate_collateral_valid(
  datum: Option<CollateralDatum>,
  transaction: Transaction,
  party: Int,
  liquidate_validator: ScriptHash,
  strike_policy_id: PolicyId,
  strike_asset_name: AssetName,
) {
  expect Some(datum) = datum
  let party_address_hash: AddressHash =
    get_address_hash_based_on_party(datum, party)

  let must_be_signed_by_owner =
    list.has(transaction.extra_signatories, party_address_hash)

  let party_has_deposited_asset: Bool =
    get_party_has_deposited_asset(datum, party)

  let deadline_has_passed: Bool =
    datum.exercise_contract_date < get_lower_bound(transaction.validity_range)

  let expected_mint =
    (datum.mint_asset.policy_id, datum.mint_asset.asset_name, -2)

  let valid_mint: Bool = validate_token_mint(transaction.mint, expected_mint)

  let all_validators_inputs = get_validators_inputs(transaction)
  let only_one_validator_input = list.length(all_validators_inputs) == 1

  expect
    deadline_has_passed && party_has_deposited_asset && valid_mint && must_be_signed_by_owner && only_one_validator_input

  let strike_is_used_as_collateral: Bool =
    datum.each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let outputs_to_liquidate_validator: List<Output> =
      find_script_outputs(transaction.outputs, liquidate_validator)

    expect Some(output_to_collateral_validator) =
      list.head(outputs_to_liquidate_validator)

    let expected_strike_collateral_asset_locked: Value =
      assets.from_lovelace(lovelace_of(output_to_collateral_validator.value))
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            datum.each_party_strike_collateral_asset_amount,
          )

    let strike_collateral_asset_burnt: Bool =
      match(
        output_to_collateral_validator.value,
        expected_strike_collateral_asset_locked,
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
  liquidate_validator: ScriptHash,
  strike_policy_id: PolicyId,
  strike_asset_name: AssetName,
  strike_consume_address_hash: AddressHash,
) {
  expect Some(datum) = datum

  let deadline_has_passed: Bool =
    datum.exercise_contract_date < get_lower_bound(transaction.validity_range)

  let strike_address = from_verification_key(strike_consume_address_hash)

  let outputs_send_to_strike_consume_address: List<Output> =
    list.filter(
      transaction.outputs,
      fn(output) { output.address == strike_address },
    )

  expect Some(output_send_to_strike_consume_address) =
    list.head(outputs_send_to_strike_consume_address)

  let expected_assets_to_strike: Value =
    assets.from_lovelace(
      lovelace_of(output_send_to_strike_consume_address.value),
    )
      |> assets.add(
          datum.collateral_asset.policy_id,
          datum.collateral_asset.asset_name,
          datum.each_party_collateral_asset_amount * 2,
        )

  let collateral_assets_sent: Bool =
    match(
      output_send_to_strike_consume_address.value,
      expected_assets_to_strike,
      >=,
    )

  let outputs_to_liquidate_validator: List<Output> =
    find_script_outputs(transaction.outputs, liquidate_validator)

  let both_party_has_not_deposited_asset: Bool =
    !get_party_has_deposited_asset(datum, 0) && !get_party_has_deposited_asset(
      datum,
      1,
    )

  let expected_mint =
    (datum.mint_asset.policy_id, datum.mint_asset.asset_name, -2)

  let valid_mint: Bool = validate_token_mint(transaction.mint, expected_mint)

  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1

  expect
    deadline_has_passed && collateral_assets_sent && both_party_has_not_deposited_asset && valid_mint && only_one_validator_input

  if datum.each_party_strike_collateral_asset_amount > 0 {
    expect Some(output_to_liquidate_validator) =
      list.head(outputs_to_liquidate_validator)

    let expected_strike_collateral_asset_locked: Value =
      assets.from_lovelace(lovelace_of(output_to_liquidate_validator.value))
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            datum.each_party_strike_collateral_asset_amount * 2,
          )

    let strike_collateral_asset_burnt: Bool =
      match(
        output_to_liquidate_validator.value,
        expected_strike_collateral_asset_locked,
        >=,
      )

    strike_collateral_asset_burnt
  } else {
    True
  }
}

validator collateral(
  agreement_validator: ScriptHash,
  liquidate_validator: ScriptHash,
  strike_policy_id: PolicyId,
  strike_asset_name: ByteArray,
  strike_consume_address_hash: AddressHash,
  strike_stake_credential: StakeCredential,
) {
  spend(
    datum: Option<CollateralDatum>,
    rdmr: CollateralRedeemerAction,
    my_output_reference: OutputReference,
    self: Transaction,
  ) {
    when rdmr is {
      OneSideDepositAgreement(deposit_party) ->
        one_side_deposit_agreement(
          datum,
          self,
          deposit_party,
          my_output_reference,
          strike_policy_id,
          strike_asset_name,
          strike_stake_credential,
        )

      BothSidesDepositAgreement ->
        both_sides_deposit_agreement(
          datum,
          self,
          agreement_validator,
          strike_stake_credential,
        )

      LiquidateCollateral(liquidate_party) ->
        liquidate_collateral_valid(
          datum,
          self,
          liquidate_party,
          liquidate_validator,
          strike_policy_id,
          strike_asset_name,
        )

      LiquidateBothParties ->
        liquidate_both_parties_valid(
          datum,
          self,
          liquidate_validator,
          strike_policy_id,
          strike_asset_name,
          strike_consume_address_hash,
        )
    }
  }

  else(_) {
    fail
  }
}
