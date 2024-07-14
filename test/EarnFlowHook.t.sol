// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {EarnFlowHook} from "src/hook/EarnFlowHook.sol";

import {DividendToken} from "src/dividend/DividendToken.sol";
import {RewardsDistributor} from "src/dividend/RewardsDistributor.sol";
import {BondedToken} from "src/token/BondedToken.sol";

import "forge-std/console2.sol";

contract EarnFlowHookTest is Test, Deployers {
    using SafeCast for *;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using FixedPointMathLib for uint256;

    EarnFlowHook hook; // aka the bonding curve
    PoolId poolId;

    DividendToken dividendToken;
    RewardsDistributor rewardsDistributor;
    BondedToken bondedToken;

    address owner;
    address beneficiary;
    address payable buyer;

    uint256 reserveRatio;
    uint256 reservePercentage;
    uint256 dividendPercentage;

    uint256 userBalances = 100000000;
    uint256 approvalAmount = 100000000;
    uint256 numTokens = 100_000 ether;
    uint256 tokenRatioPrecision = 1000000;

    // The two currencies from the pool
    Currency _currency0 = CurrencyLibrary.NATIVE; // ETH
    Currency _currency1; // Bonded Token

    function setUp() public {
        owner = address(this);
        beneficiary = address(0x123);

        // deploy dividend token
        uint256 dividendTokenInitialBalance = 60_000 ether;
        dividendToken = new DividendToken({_owner: owner, _name: "DividendToken", _symbol: "DTKN"});

        // mint initial balance to owner
        dividendToken.mint(owner, dividendTokenInitialBalance);

        // deploy rewards distributor
        rewardsDistributor = new RewardsDistributor({_owner: owner});

        // deploy bonded token
        bondedToken = new BondedToken({
            _name: "BondedToken",
            _symbol: "BTKN",
            _owner: owner,
            rewardsDistributor_: rewardsDistributor,
            dividendToken_: dividendToken
        });

        // deploy the bonding curve aka HOOK
        reserveRatio = 1000;
        reservePercentage = 10;
        dividendPercentage = 50;

        // creates the pool manager, utility routers, and test tokens
        Deployers.deployFreshManagerAndRouters();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG) | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        deployCodeTo(
            "EarnFlowHook.sol:EarnFlowHook",
            abi.encode(
                manager,
                owner,
                beneficiary,
                address(bondedToken),
                uint32(reserveRatio),
                reservePercentage,
                dividendPercentage
            ),
            flags
        );
        hook = EarnFlowHook(flags);

        // set initial mint price for testing
        hook.setInitialMintPrice(1e20);

        // mint initial balance to hook
        dividendToken.mint(address(hook), dividendTokenInitialBalance);

        // set bonding curve as the minter of the bonded token
        bondedToken.setMinter(address(hook));

        // transfer ownership of the reward distributor to the bonded token
        rewardsDistributor.transferOwnership(address(bondedToken));

        // mint some bonded tokens to the owner
        bondedToken.mint(owner, 100_000 ether);
        bondedToken.mint(address(hook), 100_000 ether);
        bondedToken.mint(address(this), 100_000 ether);
        bondedToken.mint(msg.sender, 100_000 ether);

        assertEq(address(bondedToken.owner()), owner);
        assertEq(address(bondedToken.minter()), address(hook));
        assertEq(address(rewardsDistributor.owner()), address(bondedToken));

        // Create the pool //

        _currency1 = Currency.wrap(address(bondedToken));

        address[8] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor())
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            bondedToken.approve(toApprove[i], Constants.MAX_UINT256);
        }

        key = PoolKey({
            currency0: _currency0,
            currency1: _currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);

        // Provide liquidity to the pool //

        // Provide 10e18 worth of liquidity on the range of [-60, 60]
        BalanceDelta result = modifyLiquidityRouter.modifyLiquidity{value: 200 ether}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 100 ether,
                salt: 0
            }),
            ZERO_BYTES
        );

        assertEq(result.amount0(), -99999999999999999995); // 99.9 ether
        assertEq(result.amount1(), -99999999999999999995);

        vm.stopPrank();
    }

    function testHookAsBondingCurve() public {
        /// BUY / SELL ///

        buyer = payable(makeAddr("buyer"));
        vm.deal({account: buyer, newBalance: 100 ether});

        uint256 expectedBuyPrice = numTokens * reserveRatio / tokenRatioPrecision;
        // uint256 expectedSellReward = expectedBuyPrice * reservePercentage / 100;

        // BUY //

        vm.startPrank({msgSender: owner});
        dividendToken.mint(address(hook), userBalances);
        dividendToken.mint(owner, userBalances);
        dividendToken.mint(buyer, userBalances);
        vm.stopPrank();

        vm.prank({msgSender: owner});
        dividendToken.approve(address(hook), approvalAmount);

        vm.prank({msgSender: buyer});
        dividendToken.approve(address(hook), approvalAmount);

        uint256 maxBuyPrice = 100 ether;
        // uint256 minSellPrice = 0;

        uint256 mintPrice = hook.priceToBuy(numTokens);
        assertEq(mintPrice, expectedBuyPrice);

        uint256 beneficiaryBalBefore = address(beneficiary).balance;
        uint256 reserveBalBefore = hook.reserveBalance();
        uint256 bondingCurveBalBefore = address(hook).balance;

        // buyer buys
        vm.prank({msgSender: buyer});
        hook.buy{value: maxBuyPrice}({amount: numTokens, maxPrice: maxBuyPrice, recipient: buyer});

        uint256 expectedToReserve = 10 ether;
        uint256 expectedToBeneficiary = 90 ether;

        // beneficiary got the ether
        uint256 beneficiaryBalAfter = address(beneficiary).balance;
        assertEq(beneficiaryBalAfter - beneficiaryBalBefore, expectedToBeneficiary);

        // buyer got the bonded tokens
        assertEq(bondedToken.balanceOf(buyer), numTokens);

        uint256 reserveBalAfter = hook.reserveBalance();
        uint256 bondingCurveBalAfter = address(hook).balance;

        assertEq(reserveBalAfter - reserveBalBefore, expectedToReserve);
        assertEq(bondingCurveBalAfter - bondingCurveBalBefore, expectedToReserve);

        /// PROVIDE THE RESERVE AMOUNT AS LIQUIDITY TO THE POOL ///

        BalanceDelta result = modifyLiquidityRouter.modifyLiquidity{value: expectedToReserve}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 1 ether,
                salt: 0
            }),
            ZERO_BYTES
        );

        assertEq(result.amount0(), -1e18);
        assertEq(result.amount1(), -1e18);

        // hook bal before
        uint256 hookBalBefore = bondedToken.balanceOf(address(hook));

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -0.5e18; // negative number indicates exact input swap!
        Deployers.swapNativeInput({
            _key: key,
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            hookData: ZERO_BYTES,
            msgValue: 0.5 ether
        });
        // ------------------- //

        // hook is holding the fee as a balance
        assertApproxEqAbs(
            bondedToken.balanceOf(address(hook)),
            hookBalBefore + 496051665788164, // 4.96e14
            0.000001e18
        );
    }
}
