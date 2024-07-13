// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console2} from "forge-std/console2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../token/BondedToken.sol";
import "../interfaces/IBondingCurve.sol";
import "./bancor/BancorCurve.sol";

/// @title A bonding curve implementation for buying a selling bonding curve tokens.
/// @notice Uses a defined ERC20 token as reserve currency
contract BondingCurve is IBondingCurve, Ownable, BancorCurve {
    BondedToken internal _bondedToken;

    address internal _beneficiary;

    uint256 internal _reserveBalance;
    uint256 internal _reservePercentage;
    uint256 internal _dividendPercentage;

    uint256 internal constant MAX_PERCENTAGE = 100;
    uint256 internal constant MICRO_PAYMENT_THRESHOLD = 100;

    string internal constant TRANSFER_FROM_FAILED = "Transfer of collateralTokens from sender failed";
    string internal constant TOKEN_MINTING_FAILED = "bondedToken minting failed";
    string internal constant TRANSFER_TO_BENEFICIARY_FAILED = "Tranfer of collateralTokens to beneficiary failed";
    string internal constant INSUFFICENT_TOKENS = "Insufficent tokens";
    string internal constant MAX_PRICE_EXCEEDED = "Current price exceedes maximum specified";
    string internal constant PRICE_BELOW_MIN = "Current price is below minimum specified";
    string internal constant REQUIRE_NON_ZERO_NUM_TOKENS = "Must specify a non-zero amount of bondedTokens";
    string internal constant SELL_CURVE_LARGER = "Buy curve value must be greater than Sell curve value";
    string internal constant SPLIT_ON_PAY_INVALID = "dividendPercentage must be a valid percentage";
    string internal constant SPLIT_ON_BUY_INVALID = "reservePercentage must be a valid percentage";
    string internal constant SPLIT_ON_PAY_MATH_ERROR =
        "dividendPercentage splits returned a greater token value than input value";
    string internal constant NO_MICRO_PAYMENTS =
        "Payment amount must be greater than 100 'units' for calculations to work correctly";
    string internal constant TOKEN_BURN_FAILED = "bondedToken burn failed";
    string internal constant TRANSFER_TO_RECIPIENT_FAILED = "Transfer to recipient failed";

    string internal constant INSUFFICIENT_ETHER = "Insufficient Ether";
    string internal constant INCORRECT_ETHER_SENT = "Incorrect Ether value sent";
    string internal constant MATH_ERROR_SPLITTING_COLLATERAL = "Calculated Split Invalid";

    event BeneficiarySet(address beneficiary);
    event DividendPercentageSet(uint256 dividendPercentage);
    event ReservePercentageSet(uint256 reservePercentage);

    event Buy(
        address indexed buyer,
        address indexed recipient,
        uint256 amount,
        uint256 price,
        uint256 reserveAmount,
        uint256 beneficiaryAmount
    );
    event Sell(address indexed seller, address indexed recipient, uint256 amount, uint256 reward);
    event Pay(
        address indexed from, address indexed token, uint256 amount, uint256 beneficiaryAmount, uint256 dividendAmount
    );

    /// @param owner_ Contract owner, can conduct administrative functions.
    /// @param beneficiary_ Recieves a proportion of incoming tokens on buy() and pay() operations.
    /// @param bondedToken_ Token native to the curve. The bondingCurve contract has exclusive rights to mint and burn tokens.
    /// @param reservePercentage_ Percentage of incoming collateralTokens distributed to beneficiary on buys. (The remainder is sent to reserve for sells)
    /// @param dividendPercentage_ Percentage of incoming collateralTokens distributed to beneficiary on payments. The remainder being distributed among current bondedToken holders. Divided by precision value.
    constructor(
        address owner_,
        address beneficiary_,
        address bondedToken_,
        uint32 reserveRatio_,
        uint256 reservePercentage_,
        uint256 dividendPercentage_
    ) Ownable(owner_) BancorCurve(reserveRatio_) {
        _isValidDividendPercentage(reservePercentage_);
        _isValidReservePercentage(dividendPercentage_);

        _beneficiary = beneficiary_;

        _bondedToken = BondedToken(bondedToken_);

        _reservePercentage = reservePercentage_;
        _dividendPercentage = dividendPercentage_;

        emit BeneficiarySet(_beneficiary);
        emit ReservePercentageSet(_reservePercentage);
        emit DividendPercentageSet(_dividendPercentage);
    }

    function _isValidReservePercentage(uint256 reservePercentage_) internal pure {
        require(reservePercentage_ <= MAX_PERCENTAGE, SPLIT_ON_BUY_INVALID);
    }

    function _isValidDividendPercentage(uint256 dividendPercentage_) internal pure {
        require(dividendPercentage_ <= MAX_PERCENTAGE, SPLIT_ON_PAY_INVALID);
    }

    /// @notice             Get the price in ether to mint tokens
    /// @param numTokens    The number of tokens to calculate price for
    function priceToBuy(uint256 numTokens) public view returns (uint256) {
        return calcMintPrice(_bondedToken.totalSupply(), _reserveBalance, numTokens);
    }

    /// @notice             Get the reward in ether to burn tokens
    /// @param numTokens    The number of tokens to calculate reward for
    function rewardForSell(uint256 numTokens) public view returns (uint256) {
        uint256 buyPrice = priceToBuy(numTokens);
        return (buyPrice * _reservePercentage) / MAX_PERCENTAGE;
    }

    /*
        Abstract Functions
    */

    /*
        Internal Functions
    */

    function _preBuy(uint256 amount, uint256 maxPrice)
        internal
        view
        returns (uint256 buyPrice, uint256 toReserve, uint256 toBeneficiary)
    {
        require(amount > 0, REQUIRE_NON_ZERO_NUM_TOKENS);

        buyPrice = priceToBuy(amount);

        if (maxPrice != 0) {
            require(buyPrice <= maxPrice, MAX_PRICE_EXCEEDED);
        }

        toReserve = rewardForSell(amount);
        toBeneficiary = buyPrice - toReserve;
    }

    function _postBuy(
        address buyer,
        address recipient,
        uint256 amount,
        uint256 buyPrice,
        uint256 toReserve,
        uint256 toBeneficiary
    ) internal {
        _reserveBalance = _reserveBalance + toReserve;
        _bondedToken.mint(recipient, amount);

        emit Buy(buyer, recipient, amount, buyPrice, toReserve, toBeneficiary);
    }

    /*
        Admin Functions
    */

    /// @notice Set beneficiary to a new address
    /// @param beneficiary_       New beneficiary
    function setBeneficiary(address beneficiary_) public onlyOwner {
        _beneficiary = beneficiary_;
        emit BeneficiarySet(_beneficiary);
    }

    /// @notice Set split on buy to new value
    /// @param reservePercentage_   New split on buy value
    function setReservePercentage(uint256 reservePercentage_) public onlyOwner {
        _isValidReservePercentage(reservePercentage_);
        _reservePercentage = reservePercentage_;
        emit ReservePercentageSet(_reservePercentage);
    }

    /// @notice Set split on pay to new value
    /// @param dividendPercentage_       New split on pay value
    function setDividendPercentage(uint256 dividendPercentage_) public onlyOwner {
        _isValidDividendPercentage(dividendPercentage_);
        _dividendPercentage = dividendPercentage_;
        emit DividendPercentageSet(_dividendPercentage);
    }

    /*
        Getter Functions
    */

    /// @notice Get bonded token contract
    function bondedToken() public view returns (BondedToken) {
        return _bondedToken;
    }

    /// @notice Get beneficiary
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /// @notice Get reserve balance
    function reserveBalance() public view returns (uint256) {
        return _reserveBalance;
    }

    /// @notice Get split on buy parameter
    function reservePercentage() public view returns (uint256) {
        return _reservePercentage;
    }

    /// @notice Get split on pay parameter
    function dividendPercentage() public view returns (uint256) {
        return _dividendPercentage;
    }

    /// @notice Get minimum value accepted for payments
    function getPaymentThreshold() public pure returns (uint256) {
        return MICRO_PAYMENT_THRESHOLD;
    }

    function buy(uint256 amount, uint256 maxPrice, address recipient) public payable returns (uint256 collateralSent) {
        require(maxPrice != 0 && msg.value == maxPrice, INCORRECT_ETHER_SENT);

        (uint256 buyPrice, uint256 toReserve, uint256 toBeneficiary) = _preBuy(amount, maxPrice);

        console2.log("buyPrice: ", buyPrice);
        console2.log("toReserve: ", toReserve);
        console2.log("toBeneficiary: ", toBeneficiary);

        payable(_beneficiary).transfer(toBeneficiary);

        uint256 refund = maxPrice - toReserve - toBeneficiary;

        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }

        _postBuy(msg.sender, recipient, amount, buyPrice, toReserve, toBeneficiary);
        return buyPrice;
    }

    /// @dev                Sell a given number of bondedTokens for a number of collateralTokens determined by the current rate from the sell curve.
    /// @param amount    The number of bondedTokens to sell
    /// @param minReturn     Minimum total price allowable to receive in collateralTokens
    /// @param recipient    Address to send the new bondedTokens to
    function sell(uint256 amount, uint256 minReturn, address recipient) public returns (uint256 collateralReceived) {
        require(amount > 0, REQUIRE_NON_ZERO_NUM_TOKENS);
        require(_bondedToken.balanceOf(msg.sender) >= amount, INSUFFICENT_TOKENS);

        uint256 burnReward = rewardForSell(amount);
        require(burnReward >= minReturn, PRICE_BELOW_MIN);

        _reserveBalance = _reserveBalance - burnReward;
        payable(recipient).transfer(burnReward);

        _bondedToken.burn(msg.sender, amount);

        emit Sell(msg.sender, recipient, amount, burnReward);
        return burnReward;
    }

    function pay(uint256 amount) public payable {
        require(amount > MICRO_PAYMENT_THRESHOLD, NO_MICRO_PAYMENTS);
        require(msg.value == amount, INCORRECT_ETHER_SENT);

        uint256 amountToDividendHolders = (amount * _dividendPercentage) / MAX_PERCENTAGE;
        uint256 amountToBeneficiary = amount - amountToDividendHolders;

        // outgoing funds to Beneficiary

        payable(_beneficiary).transfer(amountToBeneficiary);

        // outgoing funds to token holders as dividends (stored by BondedToken)
        _bondedToken.distribute(address(this), amountToDividendHolders);

        emit Pay(msg.sender, address(0), amount, amountToBeneficiary, amountToDividendHolders);
    }

    function setInitialMintPrice(uint256 _initialMintPrice) public onlyOwner {
        initialMintPrice = _initialMintPrice;
    }
}
