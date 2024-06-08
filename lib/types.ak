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

pub type FuturesDatum {
  issuer_address_hash: AddressHash,
  issuer_bech32_address: ByteArray,
  locked_asset: AssetClass,
  locked_asset_amount: Int,
  to_asset: AssetClass,
  to_asset_amount: Int,
  exercise_contract_date: POSIXTime,
  cancellation_fee: Int,
}

pub type ConsumeFuturesDatum {
  owner_address_hash: AddressHash,
  owner_bech32_address: ByteArray,
  asset: AssetClass,
  asset_amount: Int,
  exercise_contract_date: POSIXTime,
}

pub type ObligeeInfo {
  obligee_address_hash: AddressHash,
  obligee_bech32_address: ByteArray,
}
