use aiken/list
use aiken/transaction.{
  InlineDatum, Output, ScriptContext, Spend, find_script_outputs,
}
use aiken/transaction/value.{quantity_of}
use types.{AddressHash, AgreementDatum, AssetClass, CollateralDatum}
use utils.{
  get_address_hash_based_on_party, get_address_outputs,
  get_asset_amount_locked_based_on_party, get_asset_locked_based_on_party,
  get_datum_based_on_party, get_lower_bound, get_party_has_deposited_asset,
  get_validators_inputs,
}

// 0 = issuer, 1 = obligee
type CollateralRedeemer {
  OneSideDepositAgreement(Int)
  BothSidesDepositAgreement
  LiquidateCollateral(Int)
}

type Redeemer {
  action: CollateralRedeemer,
}

fn one_side_deposit_agreement(
  datum: CollateralDatum,
  ctx: ScriptContext,
  deposit_party: Int,
) {
  // update the collateral datum, to say true, check the asset has actually been deposited, make sure deadline not passed, and it has not been deposited already 
  expect Spend(my_output_reference) = ctx.purpose
  expect Some(input_from_validator) =
    ctx.transaction.inputs
      |> transaction.find_input(my_output_reference)

  let outputs_to_validator: List<Output> =
    get_address_outputs(ctx, input_from_validator.output.address)
  expect Some(output_to_validator) = list.at(outputs_to_validator, 0)
  expect InlineDatum(output_datum) = output_to_validator.datum
  expect output_datum_typed: CollateralDatum = output_datum

  let expected_new_datum = get_datum_based_on_party(datum, deposit_party)

  let only_one_validator_output: Bool = list.length(outputs_to_validator) == 1
  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(ctx)) == 1
  let updated_datum_correct: Bool = output_datum_typed == expected_new_datum

  let deadline_not_passed: Bool =
    datum.exercise_contract_date > get_lower_bound(
      ctx.transaction.validity_range,
    )
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

  only_one_validator_input && only_one_validator_output && updated_datum_correct && deadline_not_passed && collateral_send_back_valid && asset_locked_valid
}

// 
fn both_sides_deposit_agreement(
  datum: CollateralDatum,
  ctx: ScriptContext,
  agreement_validator: ByteArray,
) {
  // make sure two outs to agreement validator, the datum is correct, make sure deadline not passed 

  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(ctx)) == 1

  let outputs_to_consume_forwards_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, agreement_validator)
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

  let expected_issuer_utxo_contains_correct_asset =
    quantity_of(
      expected_issuer_utxo.value,
      datum.obligee_deposit_asset.policy_id,
      datum.obligee_deposit_asset.asset_name,
    ) >= datum.obligee_deposit_asset_amount

  let expected_obligee_contains_correct_asset =
    quantity_of(
      expected_obligee_utxo.value,
      datum.issuer_deposit_asset.policy_id,
      datum.issuer_deposit_asset.asset_name,
    ) >= datum.issuer_deposit_asset_amount

  let deadline_not_passed =
    datum.exercise_contract_date > get_lower_bound(
      ctx.transaction.validity_range,
    )

  only_one_validator_input && two_outputs_to_agreement_validator && deadline_not_passed && expected_issuer_utxo_contains_correct_asset && expected_obligee_contains_correct_asset
}

fn consume_collateral_valid(
  datum: CollateralDatum,
  ctx: ScriptContext,
  party: Int,
) {
  let party_address_hash: AddressHash =
    get_address_hash_based_on_party(datum, party)

  let party_has_deposited_asset: Bool =
    get_party_has_deposited_asset(datum, party)

  let must_be_signed_by_party =
    list.has(ctx.transaction.extra_signatories, party_address_hash)

  let deadline_has_passed =
    datum.exercise_contract_date < get_lower_bound(
      ctx.transaction.validity_range,
    )

  must_be_signed_by_party && deadline_has_passed && party_has_deposited_asset
}

validator(agreement_validator: ByteArray) {
  fn spend(
    datum: CollateralDatum,
    redeemer: Redeemer,
    ctx: ScriptContext,
  ) -> Bool {
    when redeemer.action is {
      OneSideDepositAgreement(deposit_party) ->
        one_side_deposit_agreement(datum, ctx, deposit_party)

      BothSidesDepositAgreement ->
        both_sides_deposit_agreement(datum, ctx, agreement_validator)

      LiquidateCollateral(liquidate_party) ->
        consume_collateral_valid(datum, ctx, liquidate_party)
    }
  }
}
