// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TwabController } from "../lib/pt-v5-vault/lib/pt-v5-twab-controller/src/TwabController.sol";
import { PrizePool } from "../lib/pt-v5-vault/lib/pt-v5-prize-pool/src/PrizePool.sol";
import { Ownable } from "../lib/pt-v5-vault/lib/owner-manager-contracts/contracts/Ownable.sol";
import { Claimable } from "../lib/pt-v5-vault/src/abstract/Claimable.sol";
import { ERC4626, ERC20, Math, IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeCast } from "../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import { IWorldIdAddressBook } from "./interfaces/IWorldIdAddressBook.sol";

/// @title World ID Verified Prize Vault for PoolTogether
/// @notice Staking prize vault that only allows World ID verified wallets to receive
/// vault shares and enforces a deposit limit on all accounts.
/// @author G9 Software Inc.
/// @dev This vault has no yield and always mints and redeems shares at a 1:1 ratio
/// with assets.
/// @dev Assets sent directly through this vault without the use of the `deposit` or
/// `mint` functions will be lost forever.
contract WorldIdVerifiedPrizeVault is Ownable, ERC4626, Claimable {
    using SafeCast for uint256;

    ////////////////////////////////////////////////////////////////////////////////
    // Public Constants and Variables
    ////////////////////////////////////////////////////////////////////////////////
    
    /// @notice The account deposit limit in assets
    uint256 public accountDepositLimit;

    /// @notice World ID address book
    IWorldIdAddressBook public immutable worldIdAddressBook;

    /// @notice Address of the TwabController used to keep track of balances.
    TwabController public immutable twabController;

    ////////////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the account deposit limit is set
    /// @param accountDepositLimit The new account deposit limit
    event SetAccountDepositLimit(uint256 accountDepositLimit);

    ////////////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when a transfer exceeds the receiving account deposit limit
    /// @param account The account receiving the transfer
    /// @param amount The balance being transferred
    /// @param remainingDepositLimit The account's remaining deposit limit
    error TransferLimitExceeded(
        address account,
        uint256 amount,
        uint256 remainingDepositLimit
    );

    ////////////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////////////
    
    /// @notice Constructor
    /// @dev Asserts that `worldIdAddressBook_` is not the zero address
    /// @param name_ The prize vault name
    /// @param symbol_ The prize vault symbol
    /// @param prizePool_ The prize pool this vault is participating in
    /// @param worldIdAddressBook_ The world ID address book to use for verifying addresses
    /// @param claimer_ The initial claimer for the prize vault
    /// @param owner_ The initial owner for the prize vault
    /// @param accountDepositLimit_ The initial account deposit limit in assets
    constructor(
        string memory name_,
        string memory symbol_,
        PrizePool prizePool_,
        IWorldIdAddressBook worldIdAddressBook_,
        address claimer_,
        address owner_,
        uint256 accountDepositLimit_
    ) ERC20(name_, symbol_) ERC4626(IERC20(address(prizePool_.prizeToken()))) Ownable(owner_) Claimable(prizePool_, claimer_) {
        assert(address(worldIdAddressBook_) != address(0));
        twabController = prizePool_.twabController();
        worldIdAddressBook = worldIdAddressBook_;
        accountDepositLimit = accountDepositLimit_;
        emit SetAccountDepositLimit(accountDepositLimit_);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Owner Functions
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Sets a new account deposit limit
    /// @dev Only Owner
    /// @param _accountDepositLimit The new account deposit limit to set
    function setAccountDepositLimit(uint256 _accountDepositLimit) external onlyOwner {
        accountDepositLimit = _accountDepositLimit;
        emit SetAccountDepositLimit(_accountDepositLimit);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ERC4626 Overrides
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ERC4626
    function _convertToAssets(uint256 shares, Math.Rounding /*rounding*/) internal view virtual override returns (uint256) {
        return shares;
    }

    /// @inheritdoc ERC4626
    function _convertToShares(uint256 assets, Math.Rounding /*rounding*/) internal view virtual override returns (uint256) {
        return assets;
    }

    /// @inheritdoc ERC4626
    /// @dev limited by the per-account limiter and world ID verification
    function maxDeposit(address _receiver) public view override returns (uint256) {
        if (worldIdAddressBook.addressVerifiedUntil(_receiver) < block.timestamp) {
            return 0;
        } else {
            uint256 _receiverBalance = balanceOf(_receiver);
            return _receiverBalance >= accountDepositLimit ? 0 : accountDepositLimit - _receiverBalance;
        }
    }

    /// @inheritdoc ERC4626
    /// @dev limited by the per-account limiter and world ID verification
    function maxMint(address _receiver) public view override returns (uint256) {
        return maxDeposit(_receiver);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ERC20 Overrides
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ERC20
    function balanceOf(
        address _account
    ) public view virtual override(IERC20, ERC20) returns (uint256) {
        return twabController.balanceOf(address(this), _account);
    }

    /// @inheritdoc ERC20
    function totalSupply() public view virtual override(IERC20, ERC20) returns (uint256) {
        return twabController.totalSupply(address(this));
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Internal ERC20 Overrides
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Override for ERC20 token transfer logic
    /// @dev Deposit limit is already handled for mint case since the ERC4626 contract enforces
    /// this on deposit and mint calls.
    /// @dev Deposit limit is not enforced on burn since no balances are being increased.
    /// @dev Deposit limit is enforced on transfer in this function when the recipient is
    /// different from the sender.
    function _update(address _from, address _to, uint256 _value) internal virtual override {
        if (_from == address(0)) {
            twabController.mint(_to, SafeCast.toUint96(_value));
        } else if (_to == address(0)) {
            twabController.burn(_from, SafeCast.toUint96(_value));
        } else {
            if (_from != _to && _value > maxDeposit(_to)) {
                revert TransferLimitExceeded(_to, _value, maxDeposit(_to));
            }
            twabController.transfer(_from, _to, SafeCast.toUint96(_value));
        }
        emit Transfer(_from, _to, _value);
    }

}
