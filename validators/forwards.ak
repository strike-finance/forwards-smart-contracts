use aiken/collection/list
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Output, Transaction, find_script_outputs}
use types.{
  AcceptForwardsContract, CancelForwardsContract, CollateralDatum,
  CreateForwardMint, EnterForwardMint, ForwardsDatum, ForwardsRedeemer,
  LiquidateBurn, MintRedeemer, ObligeeInfo, SingleBurn,
}
use utils.{get_validators_inputs, validate_token_mint}

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

  let expected_collateral_datum =
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
      mint_asset: datum.mint_asset,
    }

  expect Some(output_to_collater_utxo) =
    list.find(
      outputs_to_collateral_validator,
      fn(output) {
        expect InlineDatum(output_datum) = output.datum
        expect output_datum_typed: CollateralDatum = output_datum
        output_datum_typed == expected_collateral_datum
      },
    )

  let expected_asset_locked_valid =
    quantity_of(
      output_to_collater_utxo.value,
      expected_collateral_datum.collateral_asset.policy_id,
      expected_collateral_datum.collateral_asset.asset_name,
    ) >= expected_collateral_datum.each_party_collateral_asset_amount * 2

  let expected_strike_collateral_asset_locked_valid =
    quantity_of(
      output_to_collater_utxo.value,
      expected_collateral_datum.strike_collateral_asset.policy_id,
      expected_collateral_datum.strike_collateral_asset.asset_name,
    ) >= expected_collateral_datum.each_party_strike_collateral_asset_amount * 2

  only_one_validator_input && only_one_output_to_collateral_validator && expected_asset_locked_valid && expected_strike_collateral_asset_locked_valid
}

// asset is burnt 
fn cancel_forwards_contract_valid(
  datum: Option<ForwardsDatum>,
  transaction: Transaction,
) {
  expect Some(datum) = datum
  let must_be_signed_by_issuer =
    list.has(transaction.extra_signatories, datum.issuer_address_hash)

  must_be_signed_by_issuer
}

fn create_forward_mint_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  token_name: ByteArray,
) -> Bool {
  let expected_mint = (policy_id, token_name, 1)

  let valid_mint = validate_token_mint(transaction.mint, expected_mint)

  valid_mint
}

fn enter_forward_mint_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  token_name: ByteArray,
  collateral_validator: ByteArray,
) -> Bool {
  let outputs_to_collateral_validator: List<Output> =
    find_script_outputs(transaction.outputs, collateral_validator)

  let only_one_output_to_collateral_validator =
    list.length(outputs_to_collateral_validator) == 1

  expect Some(output_to_collateral_validator) =
    list.head(outputs_to_collateral_validator)

  expect InlineDatum(output_datum) = output_to_collateral_validator.datum
  expect output_datum_typed: CollateralDatum = output_datum

  let expected_mint = (policy_id, token_name, 1)

  let valid_mint = validate_token_mint(transaction.mint, expected_mint)

  let utxo_contains_two_assets =
    quantity_of(output_to_collateral_validator.value, policy_id, token_name) == 2

  let valid_mint_asset =
    output_datum_typed.mint_asset.policy_id == policy_id && output_datum_typed.mint_asset.asset_name == token_name

  valid_mint && only_one_output_to_collateral_validator && utxo_contains_two_assets && valid_mint_asset
}

fn single_burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  token_name: ByteArray,
) -> Bool {
  let expected_mint = (policy_id, token_name, -1)

  let valid_mint = validate_token_mint(transaction.mint, expected_mint)

  valid_mint
}

fn liquidate_burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  token_name: ByteArray,
) -> Bool {
  let expected_mint = (policy_id, token_name, -2)

  let valid_mint = validate_token_mint(transaction.mint, expected_mint)

  valid_mint
}

validator forwards(token_name: ByteArray, collateral_validator: ByteArray) {
  spend(
    datum: Option<ForwardsDatum>,
    redeemer: ForwardsRedeemer,
    _0: Data,
    transaction: Transaction,
  ) {
    when redeemer is {
      AcceptForwardsContract(obligee_info) ->
        accept_forwards_contract_valid(
          datum,
          transaction,
          collateral_validator,
          obligee_info,
        )

      CancelForwardsContract ->
        cancel_forwards_contract_valid(datum, transaction)
    }
  }

  mint(rdmr: MintRedeemer, policy_id: PolicyId, transaction: Transaction) {
    when rdmr is {
      CreateForwardMint ->
        create_forward_mint_valid(transaction, policy_id, token_name)
      EnterForwardMint ->
        enter_forward_mint_valid(
          transaction,
          policy_id,
          token_name,
          collateral_validator,
        )
      SingleBurn -> single_burn_valid(transaction, policy_id, token_name)
      LiquidateBurn -> liquidate_burn_valid(transaction, policy_id, token_name)
    }
  }

  else(_) {
    fail
  }
}
