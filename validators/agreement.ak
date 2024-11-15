use aiken/collection/list
use cardano/assets
use cardano/transaction.{Transaction}
use types.{AgreementDatum, ForwardsDatum}
use utils.{get_lower_bound, get_validators_inputs}

validator agreement {
  spend(
    maybe_datum: Option<AgreementDatum>,
    _redeemer: Int,
    _o: Data,
    transaction: Transaction,
  ) {
    let Transaction { mint, validity_range, extra_signatories, .. } =
      transaction

    expect Some(datum) = maybe_datum

    let ForwardsDatum { mint_asset, exercise_contract_date, .. } =
      datum.associated_forwards_datum

    let AgreementDatum { utxo_owner_address_hash, .. } = datum

    let must_be_signed_by_owner =
      list.has(extra_signatories, utxo_owner_address_hash)

    let expected_mint_value =
      [(mint_asset.policy_id, mint_asset.asset_name, -1)]

    let valid_mint: Bool = expected_mint_value == assets.flatten(mint)

    let expiration_date_passed: Bool =
      exercise_contract_date < get_lower_bound(validity_range)

    let only_one_validator_input =
      list.length(get_validators_inputs(transaction)) == 1

    expiration_date_passed && valid_mint && must_be_signed_by_owner && only_one_validator_input
  }

  else(_) {
    fail
  }
}
