// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../dividend/RewardsDistributor.sol";

/**
 * @title Dividend Token
 * @dev A standard ERC20, using Detailed & Mintable features. Accepts a single minter, which should be the BondingCurve. The minter also has exclusive burning rights.
 */
contract BondedToken is Ownable, ERC20 {
    IERC20 _dividendToken;

    RewardsDistributor _rewardsDistributor;

    address public minter;

    modifier onlyMinter() {
        require(msg.sender == minter, "Only minter can call this function");
        _;
    }

    /// @param _name ERC20 token name
    /// @param _symbol ERC20 token symbol
    /// @param _owner owner of the contract
    /// @param rewardsDistributor_ Instance for managing dividend accounting.
    /// @param dividendToken_ Instance of ERC20 in which dividends are paid.
    constructor(
        string memory _name,
        string memory _symbol,
        address _owner,
        RewardsDistributor rewardsDistributor_,
        IERC20 dividendToken_
    ) Ownable(_owner) ERC20(_name, _symbol) {
        _dividendToken = dividendToken_;
        _rewardsDistributor = rewardsDistributor_;
    }

    function _validateComponentAddresses() internal view returns (bool) {
        if (address(_rewardsDistributor) == address(0)) {
            return false;
        }

        if (address(_dividendToken) == address(0)) {
            return false;
        }

        return true;
    }

    /**
     * @dev Withdraw accumulated reward for the sender address.
     */
    function withdrawReward() public returns (uint256) {
        if (!_validateComponentAddresses()) {
            return 0;
        }
        address payable _staker = payable(msg.sender);
        uint256 _amount = _rewardsDistributor.withdrawReward(_staker);
        _dividendToken.transfer(_staker, _amount);
        return _amount;
    }

    /**
     * Claim and allocate provided dividend tokens to all balances greater than ELIGIBLE_UNIT.
     */
    function distribute(address from, uint256 value) public returns (bool) {
        if (!_validateComponentAddresses()) {
            return false;
        }

        if (value == 0) {
            return false;
        }

        require(_dividendToken.transferFrom(from, address(this), value), "Dividend TransferFrom Failed.");

        _rewardsDistributor.distribute(from, value);

        return true;
    }

    /**
     * @dev Burns a specific amount of tokens.
     * @param value The amount of token to be burned.
     */
    function burn(address from, uint256 value) public onlyMinter {
        _burn(from, value);

        // if (address(_rewardsDistributor) != address(0)) {
        //     _rewardsDistributor.withdrawStake(from, value);
        // }
    }

    /**
     * @dev Function to mint tokens
     * @param to The address that will receive the minted tokens.
     * @param value The amount of tokens to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(address to, uint256 value) public returns (bool) {
        require(msg.sender == owner() || msg.sender == minter, "Only owner or minter");

        _mint(to, value);

        if (address(_rewardsDistributor) != address(0)) {
            _rewardsDistributor.deposit(to, value);
        }
        return true;
    }

    /**
     * @dev Transfer token for a specified addresses
     * @param from The address to transfer from.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     */
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        // if (address(_rewardsDistributor) != address(0)) {
        //     _rewardsDistributor.withdrawStake(from, value);
        //     _rewardsDistributor.deposit(to, value);
        // }
    }

    /**
     * @dev Reads current accumulated reward for address.
     * @param staker The address to query the reward balance for.
     */
    function getReward(address staker) public view returns (uint256 tokens) {
        if (address(_rewardsDistributor) == address(0)) {
            return 0;
        }
        return _rewardsDistributor.getReward(staker);
    }

    // owner sets minter
    function setMinter(address _minter) public onlyOwner {
        minter = _minter;
    }
}
