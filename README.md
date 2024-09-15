# Strike Finance Forwards Smart Contract

## Table of Contents

- [Introduction](#introduction)
- [What Are Forwards](#what-are-forwards)
- [Technical High-Level Overview](#technical-high-level-overview)
- [Smart Contract Implementation](#smart-contract-implementation)
  - [Create Forward](#create-forward)
  - [Cancel Forward](#cancel-forward)
  - [Enter Forward Agreement](#enter-forward-agreement)
  - [Deposit Asset](#deposit-asset)
  - [Liquidate Collateral](#liquidate-collateral)
  - [Exercise Forward](#exercise-forward)
- [Links](#links)
- [Future Features](#future-features)

## Introduction

This repository contains the smart contracts for forwards trading on Strike Finance. Forwards contracts are inherently peer-to-peer (p2p).

## What Are Forwards

A forward contract is a binding agreement between two parties to exchange specific assets on a future date at a predetermined price. Unlike options contracts, where the holder has the right but not the obligation to exchange assets, both parties in a forward contract must exchange assets on the specified date. A stablecoin will always be on at least one side of the exchange. A collateral will be locked up, until the two parties deposit the required asset.

There will be one party that creates a open forward. To create a open forward UTxOs the issuer must deposit the required collateral asset.

To enter a forward contract on Strike Finance, the obligee must deposit the required collateral assets. They can then deposit the required assets specified in the contract before the deadline.

If one party doesn't deposit the asset specified in the contract, the other party that has deposited the required asset can claim the collateral locked up.

Key terms:

- Issuer: The party who creates the contract.
- Obligee: The party who enters the contract agreement.
- Long forwards: Allows the obligee to buy assets.
- Short forwards: Allows the obligee to sell assets.

Example: A long forward contract that swaps 1 iBTC for 20,000 USDM one month from today, with a collateral of 1,000 USDM. The issuer needs to deposit 1 iBTC, and the obligee needs to deposit 20,000 USDM. To enter the agreement, both sides just need to deposit 1,000 USDM as collateral first. If by the exercise date, one party has not deposited the required asset, the other party can claim the 1,000 USDM collateral. STRIKE token can also be locked up as an additional collateral, not the sole collateral. Only USDM can be the sole collateral. When the collateral gets liquidated, the USDM will be consumed by the other party, and the STRIKE will be locked up in a always_fail validator. When people use STRIKE as an additional collateral they get discounted trading fees on our platform.

## Technical High-Level Overview

The smart contract code is written in Aiken and consists of three separate validators and one minting script:

1. Minting Policy: Validates that the forwards was created correctly. For example, it contains the correct amount of collateral being locked up.

2. Forwards validator: Handles open forward contract offer UTxOs, entering a forward contract, and cancelling forward contract offers. It is parameterized by the collateral validator.

3. Collateral validator: Manages collateral UTxOs, depositing required assets, and consuming the other party's collateral if they fail to deposit. It is parameterized by the exercise validator.

4. Exercise validator: Handles exercising the forward contract and distributing assets to each party.

To create a forward a UTxO will be locked up at the forwards validator containing an asset validating that the forward is valid. When an obligee enters the forward contract, they will also mint a token and consume the UTxO sitting at the forwards validator. Then they will send a UTxO to be locked up in the collateral validator. The collateral validator will contains both parties collateral. The first person that deposits the asset will consume their collateral in the collateral UTxO, then send back the UTxO back to the collateral validator with the other parties collateral and his required asset. The second party that deposits the asset will consume their collateral in the collateral UTxO and send 2 UTxOs to the agreement validator. Each UTxO will contain the assets that each party will be able to consume once the exercise contract date has passed. The token minted will always be in each UTxO. 1 in the forward UTxO, 2 in the collateral UTxO, and 1 in the agreement UTxO. When the agreement UTxO is consumed, the minted asset will be burnt

## Smart Contract Implementation

### Creating Forwards Contract

The datum of a forwards offer UTxO:

```
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
  mint_asset: AssetClass,
}
```

**Validation Logic**

- Only 1 asset is being minted
- The asset is being sent to the forward validator
- Contains correct amount of collateral asset and strike collateral specified in datum

Preprod TxId: 6022c510bf28ae1218b2b64535418a924253eb663abd55a91cfa809bd9984542

### Cancel Forward

Forward issuers can cancel the forward offer and reclaim the collateral asset.

**Validation Logic**

- The transaction must be signed by the issuer.
- The minted asset must be burnt

Preprod TxId: cf1dfe6a91edea320feb47c77d3ef6198b712cdfe1538a7069cdce9e159927ce

### Enter Forward Agreement

To enter a forward contract agreement, the obligee must consume the forward UTxO and send it to the collateral validator address. The UTxO in the collateral validator address needs to contain both parties collateral. The collateral UTxO datum:

```
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
  mint_asset: AssetClass,
}
```

**Validation Logic**

- The obligee must send the specified `each_party_strike_collateral_asset_amount` and `collateral_asset` to the collateral script address.
- The issuer's collateral asset is not consumed and is also sent to the collateral script address in the same UTxO.
- The datum values specifying the issuer, obligee, required deposit assets, collateral assets, strike collateral assets, and deadline remain unchanged.
- Two minted assets are sent to the UTxO

Preprod TxId: 3c571015c8948fe5a77cad2cc74cada91a18864ab85b41288856831fb10220ae

### Deposit Asset

Each party can deposit the required asset anytime before the `exercise_contract_date`. The depositing party can reclaim their collateral and update either `issuer_has_deposited_asset` or `obligee_has_deposited_asset` to true.

If one party has already deposited, the second party will send two UTxOs to the exercise script address, each containing the following datum:

```
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
  mint_asset: AssetClass,
}
```

**Validation Logic**
If no one has deposited yet:

- The exercise contract date has not passed.
- The other party's collateral and STRIKE collateral is not consumed.
- The datum fields specifying the parties, required deposit assets and amounts, and collateral asset and amount are not corrupted.

Preprod TxId: 50c8d5a50f7fb5aa4da3934e69aa03189bc7e63b97b2b8bdbd1d38c429a96098

If one party has already deposited:

- The exercise contract date has not passed.
- Two UTxOs are being sent to the exercise contract: one containing the asset the issuer will receive, the other containing the asset the obligee will receive. Each UTxOs will contain the minted asset.
- The datum fields specifying the parties, required deposit assets and amounts, and collateral asset and amount are not corrupted.

Preprod TxId: 85ea0c08bc9f851cf8e61f0259120e0020abc5d60be0bdc1cb83def741d9d626

### Liquidate Collateral

If one party has deposited the required asset and the other has not, the depositing party can claim the other party's collateral.

**Validation Logic**

- The exercise date has passed.
- The party has deposited the required assets.
- The other party has not deposited the required assets.
- The two minted assets are burnt
- If STRIKE was used as additional collateral, STRIKE will be locked up in the always_fail validator

Preprod TxId: 5fb6378909e820ba09594a0d517fcdc38dd89ec5d7eac95b65b4c46590c847b9

### Exercise Forward

When the parties exercise the forward contract, they can receive their assets.

**Validation Logic**

- The exercise date has passed.
- The transaction is signed by the owner specified in `utxo_owner_address_hash`.
- The minted asset is burnt

Preprod TxId: 9fddb469cfc9430c217b992c08e042d5bfd7722ac1f45c8ec5e80f6482f81fef

## Links

- [Website](https://www.strikefinance.org/forwards)
- [Documentation](https://docs.strikefinance.org/)
- [Platform Walkthrough](https://youtu.be/l7Qaizf4NtI)
