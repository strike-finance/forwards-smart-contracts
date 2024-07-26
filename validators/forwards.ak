use aiken/list
use aiken/transaction.{InlineDatum, Output, ScriptContext, find_script_outputs}
use aiken/transaction/value.{quantity_of}
use types.{CollateralDatum, ForwardsDatum, ObligeeInfo}
use utils.{get_validators_inputs}

type ForwardsRedeemer {
  AcceptForwardsContract(ObligeeInfo)
  CancelforwardsContract
}

type Redeemer {
  action: ForwardsRedeemer,
}

fn accept_forwards_contract_valid(
  datum: ForwardsDatum,
  ctx: ScriptContext,
  collateral_validator: ByteArray,
  obligee_info: ObligeeInfo,
) {
  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(ctx)) == 1

  let outputs_to_collateral_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, collateral_validator)
  let only_two_outputs_to_validator =
    list.length(outputs_to_collateral_validator) == 1

  let collateral_datum =
    CollateralDatum {
      issuer_address_hash: datum.issuer_address_hash,
      issuer_has_deposited_asset: False,
      issuer_deposit_asset: datum.issuer_deposit_asset,
      issuer_deposit_asset_amount: datum.issuer_deposit_asset_amount,
      obligee_address_hash: obligee_info.obligee_address_hash,
      obligee_has_deposited_asset: False,
      obligee_deposit_asset: datum.obligee_deposit_asset,
      obligee_deposit_asset_amount: datum.obligee_deposit_asset_amount,
      collateral_asset: datum.collateral_asset,
      each_party_collateral_asset_amount: datum.collateral_asset_amount,
      exercise_contract_date: datum.exercise_contract_date,
    }

  expect Some(output_to_collater_utxo) =
    list.find(
      outputs_to_collateral_validator,
      fn(output) {
        expect InlineDatum(output_datum) = output.datum
        expect output_datum_typed: CollateralDatum = output_datum
        output_datum_typed == collateral_datum
      },
    )

  let expected_asset_locked_valid =
    quantity_of(
      output_to_collater_utxo.value,
      collateral_datum.collateral_asset.policy_id,
      collateral_datum.collateral_asset.asset_name,
    ) >= collateral_datum.each_party_collateral_asset_amount * 2

  only_one_validator_input && only_two_outputs_to_validator && expected_asset_locked_valid
}

fn cancel_forwards_contract_valid(datum: ForwardsDatum, ctx: ScriptContext) {
  let must_be_signed_by_issuer =
    list.has(ctx.transaction.extra_signatories, datum.issuer_address_hash)

  must_be_signed_by_issuer
}

validator(collateral_validator: ByteArray) {
  fn spend(datum: ForwardsDatum, redeemer: Redeemer, ctx: ScriptContext) -> Bool {
    when redeemer.action is {
      AcceptForwardsContract(obligee_info) ->
        accept_forwards_contract_valid(
          datum,
          ctx,
          collateral_validator,
          obligee_info,
        )

      CancelforwardsContract -> cancel_forwards_contract_valid(datum, ctx)
    }
  }
}
