use aiken/collection/list
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Transaction}
use types.{AgreementDatum}
use utils.{get_lower_bound, get_validators_inputs, validate_token_mint}

validator agreement(
  _underlying_policy_id: PolicyId,
  _underlying_asset_name: AssetName,
) {
  spend(
    maybe_datum: Option<AgreementDatum>,
    _redeemer: Int,
    _o: Data,
    self: Transaction,
  ) {
    let Transaction { mint, validity_range, extra_signatories, .. } = self

    expect Some(datum) = maybe_datum

    let AgreementDatum {
      utxo_owner_address_hash,
      mint_asset,
      exercise_contract_date,
      ..
    } = datum

    let must_be_signed_by_owner =
      list.has(extra_signatories, utxo_owner_address_hash)

    let expected_mint = (mint_asset.policy_id, mint_asset.asset_name, -1)

    let expiration_date_passed: Bool =
      exercise_contract_date < get_lower_bound(validity_range)

    let valid_mint: Bool = validate_token_mint(mint, expected_mint)

    let only_one_validator_input = list.length(get_validators_inputs(self)) == 1

    expiration_date_passed && valid_mint && must_be_signed_by_owner && only_one_validator_input
  }

  else(_) {
    fail
  }
}
