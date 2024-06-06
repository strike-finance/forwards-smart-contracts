use aiken/list
use aiken/transaction.{InlineDatum, Output, ScriptContext, find_script_outputs}
use aiken/transaction/value.{quantity_of}
use types.{ConsumeFeatureDatum, FeatureDatum, ObligeeInfo}
use utils.{get_validators_inputs}

type LoanRedeemer {
  AcceptFeatureContract(ObligeeInfo)
  CancelFeatureContract
}

type Redeemer {
  action: LoanRedeemer,
}

// offer feature contract contains datum
// asset, amount, deadline, owner pub key
// takes in consume feature contract as params
// can only consume if it is going to that contract
// can cancel feature, 

// check consumer_feature contact has two ouputs going there. 1 containing the
// datum for swap, one containing the other. Use a simple filter function for both

fn accept_feature_contract_valid(
  datum: FeatureDatum,
  ctx: ScriptContext,
  cosumer_feature_validator: ByteArray,
  obligee_info: ObligeeInfo,
) {
  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(ctx)) == 1

  let outputs_to_consume_feature_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, cosumer_feature_validator)

  let only_two_outputs_to_validator =
    list.length(outputs_to_consume_feature_validator) == 2

  let expected_issuer_datum =
    ConsumeFeatureDatum {
      owner_address_hash: datum.issuer_address_hash,
      owner_bech32_address: datum.issuer_bech32_address,
      asset: datum.to_asset,
      asset_amount: datum.to_asset_amount,
      exercise_contract_date: datum.exercise_contract_date,
      cancellation_fee: datum.cancellation_fee,
    }

  // get owner address hash and address, change asset amount
  let expected_obligee_datum =
    ConsumeFeatureDatum {
      owner_address_hash: obligee_info.obligee_address_hash,
      owner_bech32_address: obligee_info.obligee_bech32_address,
      asset: datum.locked_asset,
      asset_amount: datum.locked_asset_amount,
      exercise_contract_date: datum.exercise_contract_date,
      cancellation_fee: datum.cancellation_fee,
    }

  // map through the outputs and get their datum 
  expect Some(expected_issuer_utxo) =
    list.find(
      outputs_to_consume_feature_validator,
      fn(output) {
        expect InlineDatum(output_datum) = output.datum
        expect output_datum_typed: ConsumeFeatureDatum = output_datum

        output_datum_typed == expected_issuer_datum
      },
    )

  let expected_issuer_asset_locked_valid =
    quantity_of(
      expected_issuer_utxo.value,
      expected_issuer_datum.asset.policy_id,
      expected_issuer_datum.asset.asset_name,
    ) == expected_issuer_datum.asset_amount

  // map through the outputs and get their datum 
  expect Some(expected_obligee_utxo) =
    list.find(
      outputs_to_consume_feature_validator,
      fn(output) {
        expect InlineDatum(output_datum) = output.datum
        expect output_datum_typed: ConsumeFeatureDatum = output_datum

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

fn cancel_feature_contract_valid(datum: FeatureDatum, ctx: ScriptContext) {
  let must_be_signed_by_issuer =
    list.has(ctx.transaction.extra_signatories, datum.issuer_address_hash)

  must_be_signed_by_issuer
}

validator(consume_feature_validator: ByteArray) {
  fn spend(datum: FeatureDatum, redeemer: Redeemer, ctx: ScriptContext) -> Bool {
    when redeemer.action is {
      AcceptFeatureContract(obligee_info) ->
        accept_feature_contract_valid(
          datum,
          ctx,
          consume_feature_validator,
          obligee_info,
        )

      CancelFeatureContract -> cancel_feature_contract_valid(datum, ctx)
    }
  }
}
