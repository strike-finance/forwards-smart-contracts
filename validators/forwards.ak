use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/address.{Script}
use cardano/assets.{PolicyId, flatten, quantity_of}
use cardano/transaction.{InlineDatum, Output, Transaction}
use constants.{
  asset_name, strike_asset_name, strike_policy_id, strike_stake_credential,
}
use types.{
  AcceptForwardsContract, CancelForwardBurn, CancelForwardsContract,
  CollateralDatum, ConsumeAgreementBurn, CreateForwardMint, EnterForwardMint,
  ForwardsDatum, ForwardsRedeemer, LiquidateBurn, MintRedeemer,
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
      AcceptForwardsContract(obligee_address_hash, output_index) ->
        accept_forwards_contract_valid(
          datum,
          transaction,
          collateral_validator,
          obligee_address_hash,
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
      EnterForwardMint(obligee_address_hash, input_index) ->
        enter_forward_mint_valid(
          transaction,
          policy_id,
          input_index,
          obligee_address_hash,
        )
      CancelForwardBurn(issuer_address_hash) ->
        cancel_forward_burn_valid(transaction, policy_id, issuer_address_hash)
      LiquidateBurn(issuer_address_hash, obligee_address_hash) ->
        liquidate_burn_valid(
          transaction,
          policy_id,
          issuer_address_hash,
          obligee_address_hash,
        )
      ConsumeAgreementBurn(address_hash) ->
        consume_agreement_burn_valid(transaction, policy_id, address_hash)
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
  obligee_address_hash: VerificationKeyHash,
  output_index: Int,
) {
  let Transaction { outputs, validity_range, mint, .. } = transaction

  expect Some(datum) = maybe_datum

  let ForwardsDatum {
    collateral_asset,
    each_party_collateral_asset_amount,
    exercise_contract_date,
    mint_asset_policy_id,
    issuer_address_hash,
    each_party_strike_collateral_asset_amount,
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
      obligee_address_hash,
      obligee_has_deposited_asset: False,
      associated_forwards_datum: datum,
    }

  let datum_as_data: Data = expected_collateral_datum

  expect InlineDatum(output_datum) = output_to_collateral_utxo.datum

  let expected_collateral_datum_match: Bool = output_datum == datum_as_data

  expect Some(output_to_collateral_stake_credential) =
    output_to_collateral_utxo.address.stake_credential

  let stake_credential_is_valid: Bool =
    output_to_collateral_stake_credential == strike_stake_credential

  let deadline_not_passed =
    exercise_contract_date > get_upper_bound(validity_range)

  let ref_script_empty = output_to_collateral_utxo.reference_script == None

  let expected_mint =
    [
      (mint_asset_policy_id, asset_name, -1),
      (mint_asset_policy_id, obligee_address_hash, 1),
    ]

  let mint_valid: Bool = expected_mint == flatten(mint)

  expect
    only_one_validator_input && stake_credential_is_valid && deadline_not_passed && ref_script_empty && expected_collateral_datum_match && output_is_to_collateral_validator && mint_valid

  expect
    quantity_of(
      output_to_collateral_utxo.value,
      collateral_asset.policy_id,
      collateral_asset.asset_name,
    ) >= each_party_collateral_asset_amount * 2

  expect
    quantity_of(
      output_to_collateral_utxo.value,
      mint_asset_policy_id,
      obligee_address_hash,
    ) == 1

  expect
    quantity_of(
      output_to_collateral_utxo.value,
      mint_asset_policy_id,
      issuer_address_hash,
    ) == 1

  if each_party_strike_collateral_asset_amount > 0 {
    quantity_of(
      output_to_collateral_utxo.value,
      strike_policy_id,
      strike_asset_name,
    ) >= each_party_strike_collateral_asset_amount * 2
  } else {
    True
  }
}

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

  let expected_mint =
    [
      (mint_asset_policy_id, asset_name, -1),
      (mint_asset_policy_id, issuer_address_hash, -1),
    ]
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

  let expected_mint =
    [(policy_id, asset_name, 1), (policy_id, issuer_address_hash, 1)]

  let valid_mint: Bool = expected_mint == flatten(mint)

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

  expect
    quantity_of(
      output_to_forward_contract_value,
      collateral_asset.policy_id,
      collateral_asset.asset_name,
    ) >= each_party_collateral_asset_amount

  expect
    quantity_of(
      output_to_forward_contract_value,
      mint_asset_policy_id,
      asset_name,
    ) == 1

  expect
    quantity_of(
      output_to_forward_contract_value,
      mint_asset_policy_id,
      issuer_address_hash,
    ) == 1

  if each_party_strike_collateral_asset_amount > 0 {
    quantity_of(
      output_to_forward_contract_value,
      strike_policy_id,
      strike_asset_name,
    ) >= each_party_strike_collateral_asset_amount
  } else {
    True
  }
}

fn enter_forward_mint_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  input_index: Int,
  obligee_address_hash: VerificationKeyHash,
) -> Bool {
  let Transaction { mint, .. } = transaction

  let all_inputs_from_script = get_validators_inputs(transaction)

  let only_one_validator_input: Bool = list.length(all_inputs_from_script) == 1

  expect Some(input) = list.at(all_inputs_from_script, input_index)

  let input_is_from_forward_validator: Bool =
    get_script_hash(input.output.address) == policy_id

  let expected_mint =
    [(policy_id, asset_name, -1), (policy_id, obligee_address_hash, 1)]
  let valid_mint = expected_mint == flatten(mint)

  only_one_validator_input && input_is_from_forward_validator && valid_mint
}

fn cancel_forward_burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  issuer_address_hash: VerificationKeyHash,
) -> Bool {
  let expected_burnt =
    [(policy_id, asset_name, -1), (policy_id, issuer_address_hash, -1)]

  expected_burnt == flatten(transaction.mint)
}

fn liquidate_burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  issuer_address_hash: VerificationKeyHash,
  obligee_address_hash: VerificationKeyHash,
) -> Bool {
  let expected_burnt =
    [
      (policy_id, issuer_address_hash, -1),
      (policy_id, obligee_address_hash, -1),
    ]

  expected_burnt == flatten(transaction.mint)
}

fn consume_agreement_burn_valid(
  transaction: Transaction,
  policy_id: PolicyId,
  address_hash: VerificationKeyHash,
) -> Bool {
  let expected_burnt = [(policy_id, address_hash, -1)]

  expected_burnt == flatten(transaction.mint)
}
