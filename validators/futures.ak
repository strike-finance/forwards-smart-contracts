use aiken/list
use aiken/transaction.{InlineDatum, Output, ScriptContext, find_script_outputs}
use aiken/transaction/value.{quantity_of}
use types.{AgreementDatum, FuturesDatum, ObligeeInfo}
use utils.{get_validators_inputs}

type LoanRedeemer {
  AcceptFuturesContract(ObligeeInfo)
  CancelfuturesContract
}

type Redeemer {
  action: LoanRedeemer,
}

fn accept_futures_contract_valid(
  datum: FuturesDatum,
  ctx: ScriptContext,
  cosumer_futures_validator: ByteArray,
  obligee_info: ObligeeInfo,
) {
  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(ctx)) == 1

  let outputs_to_consume_futures_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, cosumer_futures_validator)

  let only_two_outputs_to_validator =
    list.length(outputs_to_consume_futures_validator) == 2

  let expected_issuer_datum =
    AgreementDatum {
      owner_address_hash: datum.issuer_address_hash,
      owner_bech32_address: datum.issuer_bech32_address,
      asset: datum.to_asset,
      asset_amount: datum.to_asset_amount,
      exercise_contract_date: datum.exercise_contract_date,
    }

  let expected_obligee_datum =
    AgreementDatum {
      owner_address_hash: obligee_info.obligee_address_hash,
      owner_bech32_address: obligee_info.obligee_bech32_address,
      asset: datum.locked_asset,
      asset_amount: datum.locked_asset_amount,
      exercise_contract_date: datum.exercise_contract_date,
    }

  expect Some(expected_issuer_utxo) =
    list.find(
      outputs_to_consume_futures_validator,
      fn(output) {
        expect InlineDatum(output_datum) = output.datum
        expect output_datum_typed: AgreementDatum = output_datum

        output_datum_typed == expected_issuer_datum
      },
    )

  let expected_issuer_asset_locked_valid =
    quantity_of(
      expected_issuer_utxo.value,
      expected_issuer_datum.asset.policy_id,
      expected_issuer_datum.asset.asset_name,
    ) == expected_issuer_datum.asset_amount

  expect Some(expected_obligee_utxo) =
    list.find(
      outputs_to_consume_futures_validator,
      fn(output) {
        expect InlineDatum(output_datum) = output.datum
        expect output_datum_typed: AgreementDatum = output_datum

        output_datum_typed == expected_obligee_datum
      },
    )

  let expected_obligee_asset_locked_valid =
    quantity_of(
      expected_obligee_utxo.value,
      expected_obligee_datum.asset.policy_id,
      expected_obligee_datum.asset.asset_name,
    ) == expected_obligee_datum.asset_amount

  only_one_validator_input && only_two_outputs_to_validator && expected_issuer_asset_locked_valid && expected_obligee_asset_locked_valid
}

fn cancel_futures_contract_valid(datum: FuturesDatum, ctx: ScriptContext) {
  let must_be_signed_by_issuer =
    list.has(ctx.transaction.extra_signatories, datum.issuer_address_hash)

  must_be_signed_by_issuer
}

validator(consume_futures_validator: ByteArray) {
  fn spend(datum: FuturesDatum, redeemer: Redeemer, ctx: ScriptContext) -> Bool {
    when redeemer.action is {
      AcceptFuturesContract(obligee_info) ->
        accept_futures_contract_valid(
          datum,
          ctx,
          consume_futures_validator,
          obligee_info,
        )

      CancelfuturesContract -> cancel_futures_contract_valid(datum, ctx)
    }
  }
}
