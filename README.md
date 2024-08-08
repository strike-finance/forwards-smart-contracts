# Strike Finance Options Smart Contract

## Table of Contents
- [Introduction](#introduction)
- [What Are Forwards](#what-are-forwards)
- [Technical High-Level Overview](#technical-high-level-overview)
- [Smart Contract Implementation](#smart-contract-implementation)
  - [Create Forwards](#create-forwards)
  - [Cancel Forwards](#cancel-forwards)
  - [Enter Forwards](#enter-forwards)
  - [Deposit Asset](#deposit-assets)
  - [Consume Collateral](#consume-collateral)
  - [Exercise Forwards](#exercise-forwards)
- [Links](#links)
- [Future Features](#future-features)


## Introduction
This repos contains the smart contracts for forwards trading on Strike Finance. This is p2p. Forwards contracts are inheriently p2p. 

## What Are Forwards
A forward contract is a binding agreement in which two parties agree to exchange specific assets on a future date at a price established when forming the contract. Unlike an options contract, where the holder holds the rights but not the obligation to exchange assets, the two parties in the contract must exchange assets on the specified date. 

To enter a forwards contract, both party must deposit the collateral asserts first. Forwards contract on strike finance has a collateral elements to it. The two parties doesn't need to deposit the assets immediatly. They can deposit the collateral first and desposit the required asset specified in the contract before the deadline.

If one party doesnt deposit the asset specified in the contract, the other party that has deposited the required asset can consume the collateral. 

## Technical High-Level Overview
The smart contract code is written in Aiken.

There are three seperate validators. 

A forwards validator, where all open forwards contract offer UTxOs are locked. This contract handles the logic of entering a forwards contract by both parties depositing collateral and cancelling forwards contract offer. The forwards validator is parameterized by the collateral validator.

A collateral validator, where all collateral UTxOs are locked. This validator handles the logic of depositing the required assets of the contract and consuming the other parties collateral if they failed to deposit the required assets of the contract. The collateral validator is parameterized by the exercise validator.

A exercise validator, where all exercise UTxOs are locked. This validator handles the logic of exercising the forwards contract and each party getting their assets.

No assets are minted or burned in any interaction with the contract. To create a forwards contract, enter a forwards contract etc.. requires sending UTxOs to different validator address with a valid datum value. 

## Smart Contract Implementation

### Creating Forwards Contract
This is the datum of a forwards offer UTxO
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
Since there is no way to enforce UTxOs being sent to the script address has a valid datum field, the Strike Finance platform will simply ignore malicious UTxOs. The `collateral_asset` determines what the issuer of the forward contract locks up in the UTxO. The issuer does not need to desposit the asset in `issuer_deposit_asset` immediatley. Just before the `exercise_contract_date`. A valid forwards offer UTxO will contain the amount specified in `collateral_asset_amount` and the asset specified in `collateral_asset` locked up in the UTxO. 

### Cancel Forward
Forward issuers can cancel the forward offer and get the collateral asset back 

**Validation Logic**
The transaction must be signed by the issuer 

### Enter Forward 

### Deposit Asset

### Consume Collateral

### Exercise Forward 

## Links
- [Website](https://www.strikefinance.org/forwards)
- [Documentation](https://docs.strikefinance.org/)
- [Platform Walkthrough](https://youtu.be/l7Qaizf4NtI)

## Future Features

1. On the exercise contract date the assets should automatically be send to each party by an off-chain bot.
2. If one party has not deposited the asset before the exercise contract date, the collateral should automatically be send to the other party by an off-chain bot.

