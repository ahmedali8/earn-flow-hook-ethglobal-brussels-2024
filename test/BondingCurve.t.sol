// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {DividendToken} from "src/dividend/DividendToken.sol";
import {RewardsDistributor} from "src/dividend/RewardsDistributor.sol";
import {BondedToken} from "src/token/BondedToken.sol";
import {BondingCurve} from "src/bondingCurve/BondingCurve.sol";

contract BondingCurveTest is Test {
    DividendToken dividendToken;
    RewardsDistributor rewardsDistributor;
    BondedToken bondedToken;
    BondingCurve bondingCurve;

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

    function setUp() public {
        owner = msg.sender;
        beneficiary = address(0x123);

        vm.startPrank({msgSender: owner});

        // deploy dividend token
        uint256 dividendTokenInitialBalance = 60_000 ether;
        dividendToken = new DividendToken({_owner: msg.sender, _name: "DividendToken", _symbol: "DTKN"});

        // mint initial balance to owner
        dividendToken.mint(owner, dividendTokenInitialBalance);

        // deploy rewards distributor
        rewardsDistributor = new RewardsDistributor({_owner: msg.sender});

        // deploy bonded token
        bondedToken = new BondedToken({
            _name: "BondedToken",
            _symbol: "BTKN",
            _owner: msg.sender,
            rewardsDistributor_: rewardsDistributor,
            dividendToken_: dividendToken
        });

        // deploy bonding curve
        reserveRatio = 1000;
        reservePercentage = 10;
        dividendPercentage = 50;
        bondingCurve = new BondingCurve({
            owner_: msg.sender,
            beneficiary_: beneficiary,
            bondedToken_: address(bondedToken),
            reserveRatio_: uint32(reserveRatio),
            reservePercentage_: reservePercentage,
            dividendPercentage_: dividendPercentage
        });

        // set initial mint price for testing
        bondingCurve.setInitialMintPrice(1e20);

        // mint initial balance to bondingCurve
        dividendToken.mint(address(bondingCurve), dividendTokenInitialBalance);

        // set bonding curve as the minter of the bonded token
        bondedToken.setMinter(address(bondingCurve));

        // transfer ownership of the reward distributor to the bonded token
        rewardsDistributor.transferOwnership(address(bondedToken));

        // mint some bonded tokens to the owner
        bondedToken.mint(owner, 100_000 ether);

        assertEq(address(bondedToken.owner()), owner);
        assertEq(address(bondedToken.minter()), address(bondingCurve));
        assertEq(address(rewardsDistributor.owner()), address(bondedToken));

        vm.stopPrank();
    }

    function testBondingCurve() public {
        /// BUY / SELL ///

        buyer = payable(makeAddr("buyer"));
        vm.deal({account: buyer, newBalance: 100 ether});

        uint256 expectedBuyPrice = numTokens * reserveRatio / tokenRatioPrecision;
        // uint256 expectedSellReward = expectedBuyPrice * reservePercentage / 100;

        // BUY //

        vm.startPrank({msgSender: owner});
        dividendToken.mint(address(bondingCurve), userBalances);
        dividendToken.mint(owner, userBalances);
        dividendToken.mint(buyer, userBalances);
        vm.stopPrank();

        vm.prank({msgSender: owner});
        dividendToken.approve(address(bondingCurve), approvalAmount);

        vm.prank({msgSender: buyer});
        dividendToken.approve(address(bondingCurve), approvalAmount);

        uint256 maxBuyPrice = 100 ether;
        // uint256 minSellPrice = 0;

        uint256 mintPrice = bondingCurve.priceToBuy(numTokens);
        assertEq(mintPrice, expectedBuyPrice);

        uint256 beneficiaryBalBefore = address(beneficiary).balance;
        uint256 reserveBalBefore = bondingCurve.reserveBalance();
        uint256 bondingCurveBalBefore = address(bondingCurve).balance;

        // buyer buys
        vm.prank({msgSender: buyer});
        bondingCurve.buy{value: maxBuyPrice}({amount: numTokens, maxPrice: maxBuyPrice, recipient: buyer});

        uint256 expectedToReserve = 10 ether;
        uint256 expectedToBeneficiary = 90 ether;

        // beneficiary got the ether
        uint256 beneficiaryBalAfter = address(beneficiary).balance;
        assertEq(beneficiaryBalAfter - beneficiaryBalBefore, expectedToBeneficiary);

        // buyer got the bonded tokens
        assertEq(bondedToken.balanceOf(buyer), numTokens);

        uint256 reserveBalAfter = bondingCurve.reserveBalance();
        uint256 bondingCurveBalAfter = address(bondingCurve).balance;

        assertEq(reserveBalAfter - reserveBalBefore, expectedToReserve);
        assertEq(bondingCurveBalAfter - bondingCurveBalBefore, expectedToReserve);
    }
}
