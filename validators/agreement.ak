use aiken/collection/list
use cardano/transaction.{Transaction}
use types.{AgreementDatum}
use utils.{get_lower_bound, validate_token_mint}

validator agreement {
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
      (datum.mint_asset.policy_id, datum.mint_asset.asset_name, -1)

    let expiration_date_passed: Bool =
      datum.exercise_contract_date < get_lower_bound(self.validity_range)

    let valid_mint: Bool = validate_token_mint(self.mint, expected_mint)
    expiration_date_passed && valid_mint && must_be_signed_by_owner
  }

  else(_) {
    fail
  }
}
