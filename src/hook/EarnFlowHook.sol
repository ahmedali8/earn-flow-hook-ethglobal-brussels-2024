// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {BaseTestHooks} from "v4-core/src/test/BaseTestHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

import {BondingCurve} from "../bondingCurve/BondingCurve.sol";

// focuses on Hook Swap Fees
contract EarnFlowHook is BaseHook, BondingCurve {
    using Hooks for IHooks;
    using CurrencySettler for Currency;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    IPoolManager immutable manager;

    uint256 public hookFee = 100e18; // 0.01%

    constructor(
        IPoolManager _manager,
        address owner_,
        address beneficiary_,
        address bondedToken_,
        uint32 reserveRatio_,
        uint256 reservePercentage_,
        uint256 dividendPercentage_
    )
        BaseHook(poolManager)
        BondingCurve(owner_, beneficiary_, bondedToken_, reserveRatio_, reservePercentage_, dividendPercentage_)
    {
        manager = _manager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true, // Override how swaps are done
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true, // Allow afterSwap to return a custom delta
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // fee will be in the unspecified token of the swap
        bool isCurrency0Specified = (params.amountSpecified < 0 == params.zeroForOne);

        (Currency currencyUnspecified, int128 amountUnspecified) =
            (isCurrency0Specified) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        // if exactOutput swap, get the absolute output amount
        if (amountUnspecified < 0) amountUnspecified = -amountUnspecified;

        uint256 feeAmount = uint256(int256(amountUnspecified)) * hookFee / 100000e18;

        manager.take(currencyUnspecified, address(this), feeAmount);

        return (BaseHook.afterSwap.selector, feeAmount.toInt128());
    }

    function setHookFee(uint256 fee) external onlyOwner {
        hookFee = fee;
    }
}
