use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use aiken/interval.{Finite}
use cardano/address.{Address, Credential, Script}
use cardano/assets.{PolicyId, Value, flatten, tokens}
use cardano/transaction.{Input, Output, Transaction, ValidityRange}
use types.{AssetClass, CollateralDatum, ForwardsDatum, Issuer, Party}

pub fn get_script_hash(address: Address) -> ScriptHash {
  when address.payment_credential is {
    Script(validator_hash) -> validator_hash
    _ -> fail
  }
}

pub fn is_script_credential(credential: Credential) -> Bool {
  when credential is {
    Script(_validator_hash) -> True
    _ -> False
  }
}

pub fn get_validators_inputs(transaction: Transaction) -> List<Input> {
  list.filter(
    transaction.inputs,
    fn(input) { is_script_credential(input.output.address.payment_credential) },
  )
}

pub fn get_lower_bound(range: ValidityRange) -> Int {
  expect Finite(lower_bound) = range.lower_bound.bound_type
  lower_bound
}

pub fn get_upper_bound(range: ValidityRange) -> Int {
  expect Finite(upper_bound) = range.upper_bound.bound_type
  upper_bound
}

pub fn get_datum_based_on_party(
  datum: CollateralDatum,
  deposit_party: Party,
) -> CollateralDatum {
  if deposit_party == Issuer {
    let expected_new_datum =
      CollateralDatum {
        issuer_has_deposited_asset: True,
        obligee_address_hash: datum.obligee_address_hash,
        obligee_has_deposited_asset: False,
        associated_forwards_datum: datum.associated_forwards_datum,
      }

    expected_new_datum
  } else {
    let expected_new_datum =
      CollateralDatum {
        issuer_has_deposited_asset: False,
        obligee_address_hash: datum.obligee_address_hash,
        obligee_has_deposited_asset: True,
        associated_forwards_datum: datum.associated_forwards_datum,
      }

    expected_new_datum
  }
}

pub fn get_asset_and_amount_locked_based_on_party(
  deposit_party: Party,
  issuer_deposit_asset: AssetClass,
  issuer_deposit_asset_amount: Int,
  obligee_deposit_asset: AssetClass,
  obligee_deposit_asset_amount: Int,
) -> (AssetClass, Int) {
  if deposit_party == Issuer {
    (issuer_deposit_asset, issuer_deposit_asset_amount)
  } else {
    (obligee_deposit_asset, obligee_deposit_asset_amount)
  }
}

pub fn get_address_hash_based_on_party(
  deposit_party: Party,
  issuer_address_hash: VerificationKeyHash,
  obligee_address_hash: VerificationKeyHash,
) -> VerificationKeyHash {
  if deposit_party == Issuer {
    issuer_address_hash
  } else {
    obligee_address_hash
  }
}

pub fn get_party_has_deposited_asset(
  datum: CollateralDatum,
  deposit_party: Party,
) -> Bool {
  if deposit_party == Issuer {
    datum.issuer_has_deposited_asset
  } else {
    datum.obligee_has_deposited_asset
  }
}

pub fn validate_token_mint(
  mints: Value,
  expected_minting: (ByteArray, ByteArray, Int),
) -> Bool {
  when list.find(flatten(mints), fn(mint) { mint == expected_minting }) is {
    Some(_) -> only_one_token_in_policy_minted(mints, expected_minting)
    None -> False
  }
}

// Make sure only one token is minted from the asset tuple
fn only_one_token_in_policy_minted(mints, expected_minting) {
  let (policy_id, _, _) = expected_minting
  let policy_id: PolicyId = policy_id
  // Check for the policy mints
  list.length(dict.keys(tokens(mints, policy_id))) == 1
  // Total count of minted unique tokens with policy is 1
}

pub fn signed_by_party(
  transaction: Transaction,
  party: Party,
  datum: CollateralDatum,
) -> Bool {
  if party == Issuer {
    list.has(
      transaction.extra_signatories,
      datum.associated_forwards_datum.issuer_address_hash,
    )
  } else {
    list.has(transaction.extra_signatories, datum.obligee_address_hash)
  }
}
