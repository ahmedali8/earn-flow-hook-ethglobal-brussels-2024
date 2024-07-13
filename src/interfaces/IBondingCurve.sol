// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title  IBondingCurve - Partial bonding curve interface that is backed by ether.
interface IBondingCurve {
    /// @dev                Get the price in collateralTokens to mint bondedTokens
    /// @param numTokens    The number of tokens to calculate price for
    function priceToBuy(uint256 numTokens) external view returns (uint256);

    /// @dev                Get the reward in collateralTokens to burn bondedTokens
    /// @param numTokens    The number of tokens to calculate reward for
    function rewardForSell(uint256 numTokens) external view returns (uint256);

    /// @dev                Sell a given number of bondedTokens for a number of collateralTokens determined by the current rate from the sell curve.
    /// @param numTokens    The number of bondedTokens to sell
    /// @param minPrice     Minimum total price allowable to receive in collateralTokens
    /// @param recipient    Address to send the new bondedTokens to
    function sell(uint256 numTokens, uint256 minPrice, address recipient)
        external
        returns (uint256 collateralReceived);

    /// @dev                Buy a given number of bondedTokens with a number of ether determined by the current rate from the buy curve.
    /// @param numTokens    The number of bondedTokens to buy
    /// @param maxPrice     Maximum total price allowable to pay in ether
    /// @param recipient    Address to send the new bondedTokens to
    function buy(uint256 numTokens, uint256 maxPrice, address recipient)
        external
        payable
        returns (uint256 collateralSent);

    /// @dev                Pay tokens to the DAO. This method ensures the dividend holders get a distribution before the DAO gets the funds
    /// @param numTokens    The number of ERC20 tokens you want to pay to the contract
    function pay(uint256 numTokens) external payable;
}
