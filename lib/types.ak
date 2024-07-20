use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction/credential.{VerificationKey}
use aiken/transaction/value.{AssetName, PolicyId}

pub type AssetClass {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type AddressHash =
  Hash<Blake2b_224, VerificationKey>

pub type POSIXTime =
  Int

pub type ForwardsDatum {
  issuer_address_hash: AddressHash,
  from_asset: AssetClass,
  from_asset_amount: Int,
  to_asset: AssetClass,
  to_asset_amount: Int,
  exercise_contract_date: POSIXTime,
}

pub type AgreementDatum {
  issuer_address_hash: AddressHash,
  owner_address_hash: AddressHash,
  from_asset: AssetClass,
  from_asset_amount: Int,
  to_asset: AssetClass,
  to_asset_amount: Int,
  exercise_contract_date: POSIXTime,
}

pub type ObligeeInfo {
  obligee_address_hash: AddressHash,
}
