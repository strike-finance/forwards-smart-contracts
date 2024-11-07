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
    datum: Option<AgreementDatum>,
    _redeemer: Int,
    _o: Data,
    self: Transaction,
  ) {
    expect Some(datum) = datum

    let must_be_signed_by_owner =
      list.has(self.extra_signatories, datum.utxo_owner_address_hash)

    let expected_mint =
      (
        datum.associated_forwards_datum.mint_asset.policy_id,
        datum.associated_forwards_datum.mint_asset.asset_name,
        -1,
      )

    let expiration_date_passed: Bool =
      datum.associated_forwards_datum.exercise_contract_date < get_lower_bound(
        self.validity_range,
      )

    let valid_mint: Bool = validate_token_mint(self.mint, expected_mint)

    let all_validators_inputs = get_validators_inputs(self)
    let only_one_validator_input = list.length(all_validators_inputs) == 1

    expiration_date_passed && valid_mint && must_be_signed_by_owner && only_one_validator_input
  }

  else(_) {
    fail
  }
}
