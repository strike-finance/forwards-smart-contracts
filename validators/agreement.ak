use cardano/address.{Address, from_verification_key}
use cardano/transaction.{Transaction}
use types.{AgreementDatum}
use utils.{get_asset_to_address, get_lower_bound}

validator agreement {
  spend(
    datum: Option<AgreementDatum>,
    _redeemer: Int,
    _o: Data,
    self: Transaction,
  ) {
    expect Some(datum) = datum
    let current_owner_address: Address =
      from_verification_key(datum.utxo_owner_address_hash)

    if datum.issuer_address_hash == datum.utxo_owner_address_hash {
      let amount_to_issuer: Int =
        get_asset_to_address(
          self.outputs,
          current_owner_address,
          datum.issuer_deposit_asset.policy_id,
          datum.issuer_deposit_asset.asset_name,
        )

      let expiration_date_passed =
        datum.exercise_contract_date < get_lower_bound(self.validity_range)

      let amount_to_issuer_valid =
        datum.issuer_deposit_asset_amount == amount_to_issuer

      expiration_date_passed && amount_to_issuer_valid
    } else {
      let amount_to_obligee: Int =
        get_asset_to_address(
          self.outputs,
          current_owner_address,
          datum.obligee_deposit_asset.policy_id,
          datum.obligee_deposit_asset.asset_name,
        )

      let amount_to_obligee_valid =
        datum.obligee_deposit_asset_amount == amount_to_obligee

      let expiration_date_passed =
        datum.exercise_contract_date < get_lower_bound(self.validity_range)
      expiration_date_passed && amount_to_obligee_valid
    }
  }

  else(_) {
    fail
  }
}
