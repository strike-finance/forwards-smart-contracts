use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/address.{Credential, Inline, StakeCredential, VerificationKey}
use cardano/assets.{AssetName}

// all random temp value
pub const burn_address: ScriptHash =
  #"3d960f7ce468aa238665abd8327f2916926f33350b45b2b1dbac3c03"

pub const stake_key_credential: Credential =
  VerificationKey(#"725011d2c296eb3341e159b6c5c6991de11e81062b95108c9aa024ad")

pub const stake_key = Inline(stake_key_credential)

pub const strike_stake_credential: StakeCredential = stake_key

pub const strike_consume_address_hash: VerificationKeyHash =
  #"d48838fee1e840857dab28a04dd88193aec8c297b85d8150c0a1f5cc"

pub const asset_name: AssetName = #"535452494b45"
