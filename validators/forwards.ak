use aiken/collection/list
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Output, Transaction, find_script_outputs}
use types.{
  AcceptForwardsContract, CancelBurn, CancelForwardsContract, CollateralDatum,
  EnterMint, ForwardsDatum, ForwardsRedeemer, MintRedeemer, ObligeeInfo,
}
use utils.{get_validators_inputs}

fn accept_forwards_contract_valid(
  datum: Option<ForwardsDatum>,
  transaction: Transaction,
  collateral_validator: ByteArray,
  obligee_info: ObligeeInfo,
) {
  expect Some(datum) = datum
  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1

  let outputs_to_collateral_validator: List<Output> =
    find_script_outputs(transaction.outputs, collateral_validator)
  let only_one_output_to_collateral_validator =
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
      strike_collateral_asset: datum.strike_collateral_asset,
      each_party_strike_collateral_asset_amount: datum.each_party_strike_collateral_asset_amount,
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

  let expected_strike_collateral_asset_locked_valid =
    quantity_of(
      output_to_collater_utxo.value,
      collateral_datum.strike_collateral_asset.policy_id,
      collateral_datum.strike_collateral_asset.asset_name,
    ) >= collateral_datum.each_party_strike_collateral_asset_amount * 2

  only_one_validator_input && only_one_output_to_collateral_validator && expected_asset_locked_valid && expected_strike_collateral_asset_locked_valid
}

fn cancel_forwards_contract_valid(
  datum: Option<ForwardsDatum>,
  transaction: Transaction,
) {
  expect Some(datum) = datum
  let must_be_signed_by_issuer =
    list.has(transaction.extra_signatories, datum.issuer_address_hash)

  must_be_signed_by_issuer
}

fn enter_mint_valid(rdmr: MintRedeemer, tx: Transaction) -> Bool {
  False
}

fn cancel_burn_valid(rdmr: MintRedeemer, tx: Transaction) -> Bool {
  False
}

validator forwards(collateral_validator: ByteArray) {
  spend(
    datum: Option<ForwardsDatum>,
    redeemer: ForwardsRedeemer,
    _0: Data,
    ctx: Transaction,
  ) {
    when redeemer is {
      AcceptForwardsContract(obligee_info) ->
        accept_forwards_contract_valid(
          datum,
          ctx,
          collateral_validator,
          obligee_info,
        )

      CancelForwardsContract -> cancel_forwards_contract_valid(datum, ctx)
    }
  }

  mint(rdmr: MintRedeemer, policy_id: PolicyId, tx: Transaction) {
    when rdmr is {
      EnterMint -> enter_mint_valid(rdmr, tx)
      CancelBurn -> cancel_burn_valid(rdmr, tx)
    }
  }

  else(_) {
    fail
  }
}
