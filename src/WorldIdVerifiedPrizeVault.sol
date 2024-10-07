// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TwabERC20, TwabController } from "../lib/pt-v5-vault/src/TwabERC20.sol";
import { PrizePool } from "../lib/pt-v5-vault/lib/pt-v5-prize-pool/src/PrizePool.sol";
import { Ownable } from "../lib/pt-v5-vault/lib/owner-manager-contracts/contracts/Ownable.sol";
import { Claimable } from "../lib/pt-v5-vault/src/abstract/Claimable.sol";
import { IERC4626 } from "../lib/pt-v5-vault/lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../lib/pt-v5-vault/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWorldIdAddressBook } from "./interfaces/IWorldIdAddressBook.sol";

contract WorldIdVerifiedPrizeVault is TwabERC20, Ownable, IERC4626, Claimable {
    using SafeERC20 for IERC20;

    ////////////////////////////////////////////////////////////////////////////////
    // Public Constants and Variables
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice The account deposit limit in assets
    uint256 public accountDepositLimit;

    /// @notice World ID address book
    IWorldIdAddressBook public immutable worldIdAddressBook;

    /// @notice Address of the underlying deposit asset
    address public immutable asset;

    ////////////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the account deposit limit is set
    /// @param accountDepositLimit The new account deposit limit
    event SetAccountDepositLimit(uint256 accountDepositLimit);

    ////////////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when a deposit exceeds the account deposit limit
    /// @param account The account receiving the deposit
    /// @param currentBalance The current account balance
    /// @param newBalance The new balance addition
    /// @param accountDepositLimit The account deposit limit
    error DepositLimitExceeded(
        address account,
        uint256 currentBalance,
        uint256 newBalance,
        uint256 accountDepositLimit
    );

    /// @notice Thrown when a deposit is made with zero assets
    error DepositZeroAssets();

    /// @notice Thrown when a withdrawal is made with zero assets
    error WithdrawZeroAssets();

    ////////////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Enforces the deposit limit when increasing a deposit's balance
    /// @param _account The account that is being enforced
    /// @param _depositAmount The new incoming deposit for the account
    modifier enforceDepositLimit(address _account, uint256 _depositAmount) {
        if (_depositAmount > maxDeposit(_account)) revert DepositLimitExceeded(_account, balanceOf(_account), _depositAmount, accountDepositLimit);
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////////////
    
    /// @notice Constructor
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
    ) TwabERC20(name_, symbol_, prizePool_.twabController()) Claimable(prizePool_, claimer_) Ownable(owner_) {
        assert(address(worldIdAddressBook_) != address(0));
        asset = address(prizePool_.prizeToken());
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
    // TwabERC20 Overrides
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc TwabERC20
    /// @dev Prevents the recipient's deposit limit from being exceeded
    function _mint(address _receiver, uint256 _amount) internal virtual override enforceDepositLimit(_receiver, _amount) {
        TwabERC20._mint(_receiver, _amount);
    }

    /// @inheritdoc TwabERC20
    /// @dev Prevents the recipient's deposit limit from being exceeded
    function _transfer(address _from, address _to, uint256 _amount) internal virtual override enforceDepositLimit(_to, _amount) {
        TwabERC20._transfer(_from, _to, _amount);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // IERC4626 Implementation
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IERC4626
    function totalAssets() external view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 _assets) external view returns (uint256) {
        return _assets;
    }

    /// @inheritdoc IERC4626
    function convertToAssets(uint256 _shares) external view returns (uint256) {
        return _shares;
    }

    /// @inheritdoc IERC4626
    /// @dev limited by the per-account limiter and world ID verification
    function maxDeposit(address _receiver) public view returns (uint256) {
        if (worldIdAddressBook.addressVerifiedUntil(_receiver) < block.timestamp) {
            return 0;
        } else {
            uint256 _receiverBalance = balanceOf(_receiver);
            return _receiverBalance >= accountDepositLimit ? 0 : accountDepositLimit - _receiverBalance;
        }
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 _assets) external view returns (uint256) {
        return _assets;
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 _assets, address _receiver) public returns (uint256) {
        if (_assets == 0) revert DepositZeroAssets()
        IERC20(asset).safeTransferFrom(msg.sender, address(this), _assets);
        _mint(_receiver, _assets);
        emit IERC4626.Deposit(msg.sender, _receiver, _assets, _assets);
        return _assets;
    }

    /// @inheritdoc IERC4626
    /// @dev limited by the per-account limiter and world ID verification
    function maxMint(address _receiver) external view returns (uint256) {
        return maxDeposit(_receiver);
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 _shares) external view returns (uint256) {
        return _shares;
    }

    /// @inheritdoc IERC4626
    function mint(uint256 _shares, address _receiver) external returns (uint256) {
        return deposit(_shares, _receiver);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address _owner) external view returns (uint256) {
        return balanceOf(_owner);
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 _assets) external view returns (uint256) {
        return _assets;
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 _assets, address _receiver, address _owner) public returns (uint256) {
        if (_assets == 0) revert WithdrawZeroAssets();
        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, _assets);
        _burn(_owner, _assets);
        IERC20(asset).safeTransfer(_receiver, _assets);
        emit Withdraw(msg.sender, _receiver, _owner, _assets, _assets);
        return _assets;
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address _owner) external view returns (uint256) {
        return balanceOf(_owner);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 _shares) external view returns (uint256) {
        return _shares;
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256) {
        return withdraw(_shares, _receiver, _owner);
    }

}
