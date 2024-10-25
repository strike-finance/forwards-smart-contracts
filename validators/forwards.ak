use aiken/collection/list
use cardano/address.{StakeCredential}
use cardano/assets.{PolicyId, Value, match, quantity_of}
use cardano/transaction.{InlineDatum, Output, Transaction, find_script_outputs}
use constants.{min_lovelace_amount}
use types.{
  AcceptForwardsContract, CancelForwardsContract, CollateralDatum,
  CreateForwardMint, EnterForwardMint, ForwardsDatum, ForwardsRedeemer,
  LiquidateBurn, MintRedeemer, ObligeeInfo, ScriptHash, SingleBurn,
}
use utils.{get_script_hash, get_validators_inputs, validate_token_mint}

fn accept_forwards_contract_valid(
  datum: Option<ForwardsDatum>,
  transaction: Transaction,
  collateral_validator: ByteArray,
  obligee_info: ObligeeInfo,
  strike_stake_credential: StakeCredential,
) {
  expect Some(datum) = datum

  let all_inputs_from_script = get_validators_inputs(transaction)
  let only_one_validator_input: Bool = list.length(all_inputs_from_script) == 1

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

  expect Some(output_to_collateral_utxo) =
    list.find(
      outputs_to_collateral_validator,
      fn(output) {
        expect InlineDatum(output_datum) = output.datum
        expect output_datum_typed: CollateralDatum = output_datum
        output_datum_typed == expected_collateral_datum
      },
    )

  let expected_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(
          datum.collateral_asset.policy_id,
          datum.collateral_asset.asset_name,
          datum.collateral_asset_amount * 2,
        )
      |> assets.add(datum.mint_asset.policy_id, datum.mint_asset.asset_name, 2)

  expect Some(output_to_collateral_stake_credential) =
    output_to_collateral_utxo.address.stake_credential

  let stake_credential_is_valid: Bool =
    output_to_collateral_stake_credential == strike_stake_credential

  let default_case: Bool =
    only_one_validator_input && only_one_output_to_collateral_validator && stake_credential_is_valid

  let strike_is_used_as_collateral: Bool =
    expected_collateral_datum.each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let expected_asset_locked_with_strike: Value =
      expected_assets_locked
        |> assets.add(
            expected_collateral_datum.strike_collateral_asset.policy_id,
            expected_collateral_datum.strike_collateral_asset.asset_name,
            expected_collateral_datum.each_party_strike_collateral_asset_amount * 2,
          )

    let assets_match: Bool =
      match(
        output_to_collateral_utxo.value,
        expected_asset_locked_with_strike,
        >=,
      )

    default_case && assets_match
  } else {
    let assets_match: Bool =
      match(output_to_collateral_utxo.value, expected_assets_locked, >=)

    default_case && assets_match
  }
}

// asset is burnt and signed by issuer
fn cancel_forwards_contract_valid(
  datum: Option<ForwardsDatum>,
  transaction: Transaction,
  asset_name: ByteArray,
) {
  expect Some(datum) = datum

  let all_validators_inputs = get_validators_inputs(transaction)
  let only_one_validator_input = list.length(all_validators_inputs) == 1

  let must_be_signed_by_issuer =
    list.has(transaction.extra_signatories, datum.issuer_address_hash)

  let expected_mint = (datum.mint_asset.policy_id, asset_name, -1)
  let valid_mint = validate_token_mint(transaction.mint, expected_mint)
  must_be_signed_by_issuer && valid_mint && only_one_validator_input
}

fn create_forward_mint_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  asset_name: ByteArray,
  strike_stake_credential: StakeCredential,
) -> Bool {
  let expected_mint = (policy_id, asset_name, 1)

  let valid_mint: Bool = validate_token_mint(transaction.mint, expected_mint)

  let outputs: List<Output> = transaction.outputs

  expect Some(output_to_forward_contract) =
    list.find(
      outputs,
      fn(output) {
        let minted_asset_quantity =
          quantity_of(output.value, policy_id, asset_name)

        minted_asset_quantity == 1
      },
    )

  expect InlineDatum(output_datum) = output_to_forward_contract.datum
  expect output_datum_typed: ForwardsDatum = output_datum

  let output_script_hash: ScriptHash =
    get_script_hash(output_to_forward_contract.address)

  let output_is_to_forward_validator: Bool = output_script_hash == policy_id

  expect Some(output_to_collateral_stake_credential) =
    output_to_forward_contract.address.stake_credential

  let stake_credential_is_valid: Bool =
    output_to_collateral_stake_credential == strike_stake_credential

  let expected_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(
          output_datum_typed.collateral_asset.policy_id,
          output_datum_typed.collateral_asset.asset_name,
          output_datum_typed.collateral_asset_amount,
        )
      |> assets.add(policy_id, asset_name, 1)

  let default_case: Bool =
    valid_mint && output_is_to_forward_validator && stake_credential_is_valid

  let strike_is_used_as_collateral: Bool =
    output_datum_typed.each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let expected_assets_locked_with_strike: Value =
      expected_assets_locked
        |> assets.add(
            output_datum_typed.strike_collateral_asset.policy_id,
            output_datum_typed.strike_collateral_asset.asset_name,
            output_datum_typed.each_party_strike_collateral_asset_amount,
          )

    let assets_match =
      match(
        output_to_forward_contract.value,
        expected_assets_locked_with_strike,
        >=,
      )

    default_case && assets_match
  } else {
    let assets_match =
      match(output_to_forward_contract.value, expected_assets_locked, >=)

    default_case && assets_match
  }
}

fn enter_forward_mint_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  asset_name: ByteArray,
) -> Bool {
  let all_inputs_from_script = get_validators_inputs(transaction)

  let only_one_validator_input: Bool = list.length(all_inputs_from_script) == 1

  expect Some(input) = list.head(all_inputs_from_script)

  let input_is_from_forward_validator: Bool =
    get_script_hash(input.output.address) == policy_id

  let expected_mint = (policy_id, asset_name, 1)
  let valid_mint = validate_token_mint(transaction.mint, expected_mint)

  valid_mint && only_one_validator_input && input_is_from_forward_validator
}

fn single_burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  asset_name: ByteArray,
) -> Bool {
  let expected_mint = (policy_id, asset_name, -1)

  let valid_mint = validate_token_mint(transaction.mint, expected_mint)

  valid_mint
}

fn liquidate_burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  asset_name: ByteArray,
) -> Bool {
  let expected_mint = (policy_id, asset_name, -2)

  let valid_mint = validate_token_mint(transaction.mint, expected_mint)

  valid_mint
}

validator forwards(
  asset_name: ByteArray,
  collateral_validator: ByteArray,
  strike_stake_credential: StakeCredential,
) {
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
          strike_stake_credential,
        )

      CancelForwardsContract ->
        cancel_forwards_contract_valid(datum, transaction, asset_name)
    }
  }

  mint(rdmr: MintRedeemer, policy_id: PolicyId, transaction: Transaction) {
    when rdmr is {
      CreateForwardMint ->
        create_forward_mint_valid(
          transaction,
          policy_id,
          asset_name,
          strike_stake_credential,
        )
      EnterForwardMint ->
        enter_forward_mint_valid(transaction, policy_id, asset_name)

      SingleBurn -> single_burn_valid(transaction, policy_id, asset_name)
      LiquidateBurn -> liquidate_burn_valid(transaction, policy_id, asset_name)
    }
  }

  else(_) {
    fail
  }
}
