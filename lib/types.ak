use aiken/crypto.{Blake2b_224, Hash, VerificationKey}
use cardano/assets.{AssetName, PolicyId}

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
  issuer_deposit_asset: AssetClass,
  issuer_deposit_asset_amount: Int,
  obligee_deposit_asset: AssetClass,
  obligee_deposit_asset_amount: Int,
  collateral_asset: AssetClass,
  collateral_asset_amount: Int,
  strike_collateral_asset: AssetClass,
  each_party_strike_collateral_asset_amount: Int,
  exercise_contract_date: POSIXTime,
}

pub type CollateralDatum {
  issuer_address_hash: AddressHash,
  issuer_has_deposited_asset: Bool,
  issuer_deposit_asset: AssetClass,
  issuer_deposit_asset_amount: Int,
  obligee_address_hash: AddressHash,
  obligee_has_deposited_asset: Bool,
  obligee_deposit_asset: AssetClass,
  obligee_deposit_asset_amount: Int,
  collateral_asset: AssetClass,
  each_party_collateral_asset_amount: Int,
  strike_collateral_asset: AssetClass,
  each_party_strike_collateral_asset_amount: Int,
  exercise_contract_date: POSIXTime,
}

pub type AgreementDatum {
  issuer_address_hash: AddressHash,
  utxo_owner_address_hash: AddressHash,
  issuer_deposit_asset: AssetClass,
  issuer_deposit_asset_amount: Int,
  obligee_deposit_asset: AssetClass,
  obligee_deposit_asset_amount: Int,
  collateral_asset: AssetClass,
  collateral_asset_amount: Int,
  exercise_contract_date: POSIXTime,
}

pub type ObligeeInfo {
  obligee_address_hash: AddressHash,
}

// 0 = issuer, 1 = obligee
pub type CollateralRedeemerAction {
  OneSideDepositAgreement(Int)
  BothSidesDepositAgreement
  LiquidateCollateral(Int)
}

pub type ForwardsRedeemer {
  AcceptForwardsContract(ObligeeInfo)
  CancelForwardsContract
}

pub type MintRedeemer {
  CreateForwardMint
  EnterForwardMint
  CancelBurn
}
