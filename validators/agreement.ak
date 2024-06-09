use aiken/list
use aiken/transaction.{ScriptContext}
use types.{AgreementDatum}
use utils.{get_lower_bound}

validator {
  fn spend(datum: AgreementDatum, _redeemer: Int, ctx: ScriptContext) -> Bool {
    let must_be_signed_by_issuer =
      list.has(ctx.transaction.extra_signatories, datum.owner_address_hash)

    let expiration_date_passed =
      datum.exercise_contract_date > get_lower_bound(
        ctx.transaction.validity_range,
      )

    must_be_signed_by_issuer && expiration_date_passed
  }
}
