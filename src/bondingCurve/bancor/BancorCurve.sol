// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../interfaces/ICurveLogic.sol";
import "../bancor/BancorFormula.sol";

/**
 * @title Bancor Curve Logic
 * @dev Curve that returns price per token according to bancor formula and specified reserve ratio
 */
contract BancorCurve is ICurveLogic, BancorFormula {
    uint256 public initialMintPrice;

    /*
    * @dev reserve ratio, represented in ppm, 1-1000000
    * 1/3 corresponds to y= multiple * x^2
    * 1/2 corresponds to y= multiple * x
    * 2/3 corresponds to y= multiple * x^1/2
    * multiple will depends on contract initialization,
    * specifically totalAmount and poolBalance parameters
    * we might want to add an 'initialize' function that will allow
    * the owner to send ether to the contract and mint a given amount of tokens
    */

    uint32 internal _reserveRatio;

    /// @param reserveRatio_     The number of curve tokens to mint
    constructor(uint32 reserveRatio_) {
        _reserveRatio = reserveRatio_;
    }

    /// @dev                    Get the price to mint tokens
    /// @param totalSupply      The existing number of curve tokens
    /// @param amount           The number of curve tokens to mint
    function calcMintPrice(uint256 totalSupply, uint256 reserveBalance, uint256 amount) public view returns (uint256) {
        return totalSupply == 0 || reserveBalance == 0
            ? initialMintPrice
            : calculatePurchaseReturn(totalSupply, reserveBalance, _reserveRatio, amount);
    }

    /// @dev                    Get the reward to burn tokens
    /// @param totalSupply      The existing number of curve tokens
    /// @param amount           The number of curve tokens to burn
    function calcBurnReward(uint256 totalSupply, uint256 reserveBalance, uint256 amount)
        public
        view
        returns (uint256)
    {
        return calculateSaleReturn(totalSupply, reserveBalance, _reserveRatio, amount);
    }

    /// @notice Get reserve ratio
    function reserveRatio() public view returns (uint32) {
        return _reserveRatio;
    }
}
