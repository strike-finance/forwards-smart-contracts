use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/address.{Credential, Inline, StakeCredential, VerificationKey}
use cardano/assets.{AssetName, PolicyId}

// all random temp value
pub const burn_address: ScriptHash =
  #"3d960f7ce468aa238665abd8327f2916926f33350b45b2b1dbac3c03"

pub const stake_key_credential: Credential =
  VerificationKey(#"1aabcb52a9ea7db46dfcfc63a71ab87937512bd130b50d62ea443594")

pub const stake_key = Inline(stake_key_credential)

pub const strike_stake_credential: StakeCredential = stake_key

pub const strike_consume_address_hash: VerificationKeyHash =
  #"d48838fee1e840857dab28a04dd88193aec8c297b85d8150c0a1f5cc"

pub const asset_name: AssetName = #"535452494b45"

pub const strike_policy_id: PolicyId =
  #"f13ac4d66b3ee19a6aa0f2a22298737bd907cc95121662fc971b5275"

pub const strike_asset_name: AssetName = #"535452494b45"
