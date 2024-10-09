use aiken/collection/list
use cardano/address.{StakeCredential}
use cardano/assets.{quantity_of}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_script_outputs,
}
use types.{
  AddressHash, AgreementDatum, AssetClass, BothSidesDepositAgreement,
  CollateralDatum, CollateralRedeemerAction, LiquidateCollateral,
  OneSideDepositAgreement,
}
use utils.{
  get_address_hash_based_on_party, get_address_outputs,
  get_asset_amount_locked_based_on_party, get_asset_locked_based_on_party,
  get_datum_based_on_party, get_lower_bound, get_party_has_deposited_asset,
  get_validators_inputs, validate_token_mint,
}

fn one_side_deposit_agreement(
  datum: Option<CollateralDatum>,
  transaction: Transaction,
  deposit_party: Int,
  my_output_reference: OutputReference,
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
    datum.exercise_contract_date > get_lower_bound(transaction.validity_range)
  let collateral_send_back_valid: Bool =
    quantity_of(
      output_to_validator.value,
      datum.collateral_asset.policy_id,
      datum.collateral_asset.asset_name,
    ) >= datum.each_party_collateral_asset_amount

  let expected_asset_locked: AssetClass =
    get_asset_locked_based_on_party(datum, deposit_party)

  let expected_asset_amount_locked: Int =
    get_asset_amount_locked_based_on_party(datum, deposit_party)

  let asset_locked_valid: Bool =
    quantity_of(
      output_to_validator.value,
      expected_asset_locked.policy_id,
      expected_asset_locked.asset_name,
    ) >= expected_asset_amount_locked

  let mint_asset_not_consumed =
    quantity_of(
      output_to_validator.value,
      datum.mint_asset.policy_id,
      datum.mint_asset.asset_name,
    ) == 2

  expect Some(output_stake_credential) =
    output_to_validator.address.stake_credential

  let stake_credential_is_valid =
    output_stake_credential == strike_stake_credential

  let default_case =
    stake_credential_is_valid && mint_asset_not_consumed && only_one_validator_input && only_one_validator_output && updated_datum_correct && deadline_not_passed && collateral_send_back_valid && asset_locked_valid

  let strike_is_used_as_collateral: Bool =
    datum.each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let strike_collateral_asset_send_back_valid: Bool =
      quantity_of(
        output_to_validator.value,
        datum.strike_collateral_asset.policy_id,
        datum.strike_collateral_asset.asset_name,
      ) >= datum.each_party_strike_collateral_asset_amount
    default_case && strike_collateral_asset_send_back_valid
  } else {
    default_case
  }
}

fn both_sides_deposit_agreement(
  datum: Option<CollateralDatum>,
  transaction: Transaction,
  agreement_validator: ByteArray,
  strike_stake_credential: StakeCredential,
) {
  expect Some(datum) = datum

  // // make sure two outs to agreement validator, the datum is correct, make sure deadline not passed 
  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1
  let outputs_to_consume_forwards_validator: List<Output> =
    find_script_outputs(transaction.outputs, agreement_validator)
  let two_outputs_to_agreement_validator =
    list.length(outputs_to_consume_forwards_validator) == 2

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
  expect Some(expected_issuer_utxo) =
    list.find(
      outputs_to_consume_forwards_validator,
      fn(output) {
        expect InlineDatum(output_datum) = output.datum
        expect output_datum_typed: AgreementDatum = output_datum
        output_datum_typed == expected_issuer_datum
      },
    )

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

  expect Some(expected_obligee_utxo) =
    list.find(
      outputs_to_consume_forwards_validator,
      fn(output) {
        expect InlineDatum(output_datum) = output.datum
        expect output_datum_typed: AgreementDatum = output_datum
        output_datum_typed == expected_obligee_datum
      },
    )

  let obligee_utxo_contains_asset: Bool =
    quantity_of(
      expected_obligee_utxo.value,
      datum.mint_asset.policy_id,
      datum.mint_asset.asset_name,
    ) == 1

  let issuer_utxo_contains_asset: Bool =
    quantity_of(
      expected_issuer_utxo.value,
      datum.mint_asset.policy_id,
      datum.mint_asset.asset_name,
    ) == 1

  let expected_issuer_utxo_contains_correct_asset: Bool =
    quantity_of(
      expected_issuer_utxo.value,
      datum.obligee_deposit_asset.policy_id,
      datum.obligee_deposit_asset.asset_name,
    ) >= datum.obligee_deposit_asset_amount

  let expected_obligee_contains_correct_asset: Bool =
    quantity_of(
      expected_obligee_utxo.value,
      datum.issuer_deposit_asset.policy_id,
      datum.issuer_deposit_asset.asset_name,
    ) >= datum.issuer_deposit_asset_amount

  let deadline_not_passed: Bool =
    datum.exercise_contract_date > get_lower_bound(transaction.validity_range)

  expect Some(obligee_stake_credential) =
    expected_obligee_utxo.address.stake_credential

  expect Some(issuer_stake_credential) =
    expected_issuer_utxo.address.stake_credential

  let stake_credential_is_valid =
    obligee_stake_credential == strike_stake_credential && issuer_stake_credential == strike_stake_credential

  stake_credential_is_valid && issuer_utxo_contains_asset && obligee_utxo_contains_asset && expected_issuer_utxo_contains_correct_asset && expected_obligee_contains_correct_asset && only_one_validator_input && two_outputs_to_agreement_validator && deadline_not_passed && stake_credential_is_valid
}

fn consume_collateral_valid(
  datum: Option<CollateralDatum>,
  transaction: Transaction,
  party: Int,
  liquidate_validator: ByteArray,
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

  let default_case: Bool =
    deadline_has_passed && party_has_deposited_asset && valid_mint && must_be_signed_by_owner

  let strike_is_used_as_collateral: Bool =
    datum.each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let outputs_to_liquidate_validator: List<Output> =
      find_script_outputs(transaction.outputs, liquidate_validator)

    expect Some(output_to_collateral_validator) =
      list.head(outputs_to_liquidate_validator)

    let strike_collateral_asset_burnt: Bool =
      quantity_of(
        output_to_collateral_validator.value,
        datum.strike_collateral_asset.policy_id,
        datum.strike_collateral_asset.asset_name,
      ) >= datum.each_party_strike_collateral_asset_amount

    default_case && strike_collateral_asset_burnt
  } else {
    default_case
  }
}

validator collateral(
  agreement_validator: ByteArray,
  liquidate_validator: ByteArray,
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
        consume_collateral_valid(
          datum,
          self,
          liquidate_party,
          liquidate_validator,
        )
    }
  }

  else(_) {
    fail
  }
}
