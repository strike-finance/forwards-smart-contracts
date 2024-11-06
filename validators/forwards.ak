use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Script}
use cardano/assets.{PolicyId, Value, flatten, match, policies, tokens}
use cardano/transaction.{InlineDatum, Output, Transaction}
use constants.{
  min_lovelace_amount, strike_asset_name, strike_policy_id,
  strike_stake_credential,
}
use types.{
  AcceptForwardsContract, Burn, CancelForwardsContract, CollateralDatum,
  CreateForwardMint, EnterForwardMint, ForwardsDatum, ForwardsRedeemer,
  MintRedeemer, ObligeeInfo,
}
use utils.{get_script_hash, get_upper_bound, get_validators_inputs}

validator forwards(collateral_validator: ByteArray) {
  spend(
    datum: Option<ForwardsDatum>,
    redeemer: ForwardsRedeemer,
    _0: Data,
    transaction: Transaction,
  ) {
    when redeemer is {
      AcceptForwardsContract(obligee_info, output_index) ->
        accept_forwards_contract_valid(
          datum,
          transaction,
          collateral_validator,
          obligee_info,
          output_index,
        )

      CancelForwardsContract ->
        cancel_forwards_contract_valid(datum, transaction)
    }
  }

  mint(rdmr: MintRedeemer, policy_id: PolicyId, transaction: Transaction) {
    when rdmr is {
      CreateForwardMint(output_index) ->
        create_forward_mint_valid(transaction, policy_id, output_index)
      EnterForwardMint(output_index) ->
        enter_forward_mint_valid(transaction, policy_id, output_index)
      Burn(burnt_amount) -> burn_valid(transaction, policy_id, burnt_amount)
    }
  }

  else(_) {
    fail
  }
}

fn accept_forwards_contract_valid(
  maybe_datum: Option<ForwardsDatum>,
  transaction: Transaction,
  collateral_validator: ByteArray,
  obligee_info: ObligeeInfo,
  output_index: Int,
) {
  let Transaction { outputs, mint, validity_range, .. } = transaction

  expect Some(datum) = maybe_datum

  let ForwardsDatum {
    collateral_asset,
    each_party_collateral_asset_amount,
    each_party_strike_collateral_asset_amount,
    exercise_contract_date,
    mint_asset_policy_id,
    ..
  } = datum

  let only_one_validator_input: Bool =
    list.length(get_validators_inputs(transaction)) == 1

  expect Some(output_to_collateral_utxo) = list.at(outputs, output_index)

  expect Script(output_to_collateral_hash) =
    output_to_collateral_utxo.address.payment_credential

  let output_is_to_collateral_validator: Bool =
    output_to_collateral_hash == collateral_validator

  let expected_collateral_datum =
    CollateralDatum {
      issuer_has_deposited_asset: False,
      obligee_address_hash: obligee_info.obligee_address_hash,
      obligee_has_deposited_asset: False,
      associated_forwards_datum: datum,
    }

  let datum_as_data: Data = expected_collateral_datum

  expect InlineDatum(output_datum) = output_to_collateral_utxo.datum

  let expected_collateral_datum_match: Bool = output_datum == datum_as_data

  let expected_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(
          collateral_asset.policy_id,
          collateral_asset.asset_name,
          each_party_collateral_asset_amount * 2,
        )
      |> assets.add(mint_asset_policy_id, datum.issuer_address_hash, 1)
      |> assets.add(mint_asset_policy_id, obligee_info.obligee_address_hash, 1)

  let expected_mint_value =
    [(mint_asset_policy_id, obligee_info.obligee_address_hash, 1)]

  let valid_mint: Bool = expected_mint_value == flatten(mint)

  expect Some(output_to_collateral_stake_credential) =
    output_to_collateral_utxo.address.stake_credential

  let stake_credential_is_valid: Bool =
    output_to_collateral_stake_credential == strike_stake_credential

  let deadline_not_passed =
    exercise_contract_date > get_upper_bound(validity_range)

  let ref_script_empty = output_to_collateral_utxo.reference_script == None

  expect
    only_one_validator_input && stake_credential_is_valid && valid_mint && deadline_not_passed && ref_script_empty && expected_collateral_datum_match && output_is_to_collateral_validator

  let strike_is_used_as_collateral: Bool =
    each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let expected_asset_locked_with_strike: Value =
      expected_assets_locked
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            each_party_strike_collateral_asset_amount * 2,
          )

    let assets_match: Bool =
      match(
        output_to_collateral_utxo.value,
        expected_asset_locked_with_strike,
        >=,
      )

    assets_match
  } else {
    let assets_match: Bool =
      match(output_to_collateral_utxo.value, expected_assets_locked, >=)

    assets_match
  }
}

// asset is burnt and signed by issuer
fn cancel_forwards_contract_valid(
  maybe_datum: Option<ForwardsDatum>,
  transaction: Transaction,
) {
  expect Some(datum) = maybe_datum

  let Transaction { extra_signatories, mint, .. } = transaction

  let ForwardsDatum { issuer_address_hash, mint_asset_policy_id, .. } = datum

  let only_one_validator_input =
    list.length(get_validators_inputs(transaction)) == 1

  let must_be_signed_by_issuer =
    list.has(extra_signatories, issuer_address_hash)

  let expected_mint = [(mint_asset_policy_id, issuer_address_hash, -1)]
  let valid_mint = expected_mint == flatten(mint)
  must_be_signed_by_issuer && valid_mint && only_one_validator_input
}

fn create_forward_mint_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  output_index: Int,
) -> Bool {
  let Transaction { mint, outputs, validity_range, .. } = transaction

  expect Some(Output {
    value: output_to_forward_contract_value,
    datum: InlineDatum(output_datum),
    address: output_to_contract_address,
    reference_script,
  }) = list.at(outputs, output_index)

  expect output_datum_typed: ForwardsDatum = output_datum

  let ForwardsDatum {
    collateral_asset,
    each_party_collateral_asset_amount,
    exercise_contract_date,
    issuer_deposit_asset,
    obligee_deposit_asset,
    issuer_deposit_asset_amount,
    obligee_deposit_asset_amount,
    mint_asset_policy_id,
    issuer_address_hash,
    each_party_strike_collateral_asset_amount,
  } = output_datum_typed

  let output_script_hash: ScriptHash =
    get_script_hash(output_to_contract_address)

  let output_is_to_forward_validator: Bool = output_script_hash == policy_id

  expect Some(output_to_collateral_stake_credential) =
    output_to_contract_address.stake_credential

  let stake_credential_is_valid: Bool =
    output_to_collateral_stake_credential == strike_stake_credential

  let expected_mint = [(policy_id, issuer_address_hash, 1)]

  let valid_mint: Bool = expected_mint == flatten(mint)

  let expected_assets_locked: Value =
    assets.from_lovelace(min_lovelace_amount)
      |> assets.add(
          collateral_asset.policy_id,
          collateral_asset.asset_name,
          each_party_collateral_asset_amount,
        )
      |> assets.add(policy_id, issuer_address_hash, 1)

  let ref_script_empty = reference_script == None

  let deadline_not_passed =
    exercise_contract_date > get_upper_bound(validity_range)

  let issuer_and_obligee_asset_different: Bool =
    issuer_deposit_asset != obligee_deposit_asset

  let issuer_asset_positive: Bool = issuer_deposit_asset_amount > 0

  let obligee_asset_positive: Bool = obligee_deposit_asset_amount > 0

  let mint_asset_valid = mint_asset_policy_id == policy_id

  expect
    valid_mint && output_is_to_forward_validator && stake_credential_is_valid && ref_script_empty && deadline_not_passed && issuer_and_obligee_asset_different && issuer_asset_positive && obligee_asset_positive && mint_asset_valid

  let strike_is_used_as_collateral: Bool =
    each_party_strike_collateral_asset_amount > 0

  if strike_is_used_as_collateral {
    let expected_assets_locked_with_strike: Value =
      expected_assets_locked
        |> assets.add(
            strike_policy_id,
            strike_asset_name,
            output_datum_typed.each_party_strike_collateral_asset_amount,
          )

    let assets_match =
      match(
        output_to_forward_contract_value,
        expected_assets_locked_with_strike,
        >=,
      )

    assets_match
  } else {
    let assets_match =
      match(output_to_forward_contract_value, expected_assets_locked, >=)

    assets_match
  }
}

fn enter_forward_mint_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  output_index: Int,
) -> Bool {
  let Transaction { mint, .. } = transaction

  let all_inputs_from_script = get_validators_inputs(transaction)

  let only_one_validator_input: Bool = list.length(all_inputs_from_script) == 1

  expect Some(input) = list.at(all_inputs_from_script, output_index)

  let input_is_from_forward_validator: Bool =
    get_script_hash(input.output.address) == policy_id

  let policies_mint = policies(mint)
  let only_one_mint_policy = list.length(policies_mint) == 1

  let tokens = tokens(mint, policy_id)
  let tokens_minted = dict.size(tokens)
  let only_one_minted_amount = tokens_minted == 1

  only_one_minted_amount && only_one_validator_input && input_is_from_forward_validator && only_one_mint_policy
}

fn burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  burnt_amount: Int,
) -> Bool {
  let Transaction { mint, .. } = transaction

  let policies_mint = policies(mint)
  let only_one_mint_policy = list.length(policies_mint) == 1

  let tokens = tokens(mint, policy_id)
  let tokens_burnt = dict.size(tokens)

  tokens_burnt == burnt_amount && only_one_mint_policy
}
