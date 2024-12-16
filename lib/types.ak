use aiken/crypto.{VerificationKeyHash}
use cardano/assets.{AssetName, PolicyId}

pub type AssetClass {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type POSIXTime =
  Int

pub type ForwardsDatum {
  issuer_address_hash: VerificationKeyHash,
  issuer_deposit_asset: AssetClass,
  issuer_deposit_asset_amount: Int,
  obligee_deposit_asset: AssetClass,
  obligee_deposit_asset_amount: Int,
  collateral_asset: AssetClass,
  each_party_collateral_asset_amount: Int,
  exercise_contract_date: POSIXTime,
  mint_asset: AssetClass,
}

pub type CollateralDatum {
  issuer_has_deposited_asset: Bool,
  obligee_address_hash: VerificationKeyHash,
  obligee_has_deposited_asset: Bool,
  associated_forwards_datum: ForwardsDatum,
}

pub type AgreementDatum {
  utxo_owner_address_hash: VerificationKeyHash,
  associated_forwards_datum: ForwardsDatum,
}

pub type Party {
  Issuer
  Obligee
}

// 0 = issuer, 1 = obligee
pub type CollateralRedeemerAction {
  OneSideDepositAgreement(Party, Int)
  BothSidesDepositAgreement(Party)
  LiquidateCollateral(Party)
  LiquidateBothParties(Int)
}

pub type ForwardsRedeemer {
  AcceptForwardsContract(VerificationKeyHash, Int)
  CancelForwardsContract
}

pub type MintRedeemer {
  CreateForwardMint(Int)
  EnterForwardMint(Int)
  SingleBurn
  LiquidateBurn
}
