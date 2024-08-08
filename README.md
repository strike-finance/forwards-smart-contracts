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
  - [Consume Collateral](#consume-collateral)
  - [Exercise Forward](#exercise-forward)
- [Links](#links)
- [Future Features](#future-features)

## Introduction
This repository contains the smart contracts for forwards trading on Strike Finance. Forwards contracts are inherently peer-to-peer (p2p).

## What Are Forwards
A forward contract is a binding agreement between two parties to exchange specific assets on a future date at a predetermined price. Unlike options contracts, where the holder has the right but not the obligation to exchange assets, both parties in a forward contract must exchange assets on the specified date. A stablecoin will always be on at least one side of the exchange.

To enter a forward contract on Strike Finance, both parties must first deposit collateral assets. They can then deposit the required assets specified in the contract before the deadline.

If one party doesn't deposit the asset specified in the contract, the other party that has deposited the required asset can claim the collateral.

Key terms:
- Issuer: The party who creates the contract.
- Obligee: The party who enters the contract agreement.
- Long forwards: Allows the obligee to buy assets.
- Short forwards: Allows the obligee to sell assets.

Example: A long forward contract that swaps 1 iBTC for 20,000 USDM one month from today, with a collateral of 1,000 USDM. The issuer needs to deposit 1 iBTC, and the obligee needs to deposit 20,000 USDM. To enter the agreement, both sides initially need to deposit 1,000 USDM as collateral. If by the exercise date, one party has not deposited the required asset, the other party can claim the 1,000 USDM collateral.

## Technical High-Level Overview
The smart contract code is written in Aiken and consists of three separate validators:

1. Forwards validator: Handles open forward contract offer UTxOs, entering a forward contract, and cancelling forward contract offers. It is parameterized by the collateral validator.

2. Collateral validator: Manages collateral UTxOs, depositing required assets, and consuming the other party's collateral if they fail to deposit. It is parameterized by the exercise validator.

3. Exercise validator: Handles exercising the forward contract and distributing assets to each party.

No assets are minted or burned in any interaction with the contract. Creating a forward contract, entering a forward contract, etc., requires sending UTxOs to different validator addresses with valid datum values.

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
  exercise_contract_date: POSIXTime,
}
```
The Strike Finance platform will ignore malicious UTxOs. A valid forwards offer UTxO will contain the amount specified in `collateral_asset_amount` and the asset specified in `collateral_asset` locked in the UTxO.

### Cancel Forward
Forward issuers can cancel the forward offer and reclaim the collateral asset.

**Validation Logic**
* The transaction must be signed by the issuer.

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
  collateral_asset_amount: Int,
  exercise_contract_date: POSIXTime,
}
```

**Validation Logic**
* The obligee must send the specified `collateral_asset_amount` and `collateral_asset` to the collateral script address.
* The issuer's collateral asset is not consumed and is also sent to the collateral script address in the same UTxO.
* The datum values specifying the issuer, obligee, required deposit assets, collateral assets, and deadline remain unchanged.

### Deposit Asset
Each party can deposit the required asset anytime before the `exercise_contract_date`. The depositing party can reclaim their collateral and update either `issuer_has_deposited_asset` or `obligee_has_deposited_asset` to true.

If one party has already deposited, the second party will send two UTxOs to the exercise script address, each containing the following datum:
```
pub type AgreementDatum {
  utxo_owner_address_hash: AddressHash,
  issuer_deposit_asset: AssetClass,
  issuer_deposit_asset_amount: Int,
  obligee_deposit_asset: AssetClass,
  obligee_deposit_asset_amount: Int,
  collateral_asset: AssetClass,
  collateral_asset_amount: Int,
  exercise_contract_date: POSIXTime,
}
```

**Validation Logic**
If no one has deposited yet:
* The exercise contract date has not passed.
* The other party's collateral is not consumed.
* The datum fields specifying the parties, required deposit assets and amounts, and collateral asset and amount are not corrupted.

If one party has already deposited:
* The exercise contract date has not passed.
* Two UTxOs are being sent to the exercise contract: one containing the asset the issuer will receive, the other containing the asset the obligee will receive.
* The datum fields specifying the parties, required deposit assets and amounts, and collateral asset and amount are not corrupted.

### Consume Collateral
If one party has deposited the required asset and the other has not, the depositing party can claim the other party's collateral.

**Validation Logic**
* The exercise date has passed.
* The party has deposited the required assets.
* The other party has not deposited the required assets.

### Exercise Forward
When the parties exercise the forward contract, they can receive their assets.

**Validation Logic**
* The exercise date has passed.
* The transaction is signed by the owner specified in `utxo_owner_address_hash`.

## Links
- [Website](https://www.strikefinance.org/forwards)
- [Documentation](https://docs.strikefinance.org/)
- [Platform Walkthrough](https://youtu.be/l7Qaizf4NtI)

## Future Features

1. Automatic asset distribution to each party by an off-chain bot on the exercise contract date.
2. Automatic collateral liquidation distribution to the depositing party by an off-chain bot if one party has not deposited the asset before the exercise contract date.
