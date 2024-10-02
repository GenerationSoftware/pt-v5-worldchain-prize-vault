// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TwabERC20, TwabController, ERC20 } from "../lib/pt-v5-vault/src/TwabERC20.sol";
import { PrizePool } from "../lib/pt-v5-vault/lib/pt-v5-prize-pool/src/PrizePool.sol";
import { Ownable } from "../lib/pt-v5-vault/lib/owner-manager-contracts/contracts/Ownable.sol";
import { IClaimable } from "../lib/pt-v5-vault/lib/pt-v5-claimable-interface/src/interfaces/IClaimable.sol";
import { IERC4626 } from "../lib/pt-v5-vault/lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../lib/pt-v5-vault/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWorldIdAddressBook } from "./interfaces/IWorldIdAddressBook.sol";

contract WorldIdVerifiedPrizeVault is TwabERC20, Ownable, IERC4626, IClaimable {
    using SafeERC20 for IERC20;

    ////////////////////////////////////////////////////////////////////////////////
    // Public Constants and Variables
    ////////////////////////////////////////////////////////////////////////////////
    
    /// @notice Address of the claimer
    address public claimer;

    /// @notice Address that will receive any excess prize value due to an account's
    /// TWAB exceeding the `accountDepositLimit` at the time of winning a prize.
    address public prizeExcessRecipient;

    /// @notice The account deposit limit in assets
    uint256 public accountDepositLimit;

    /// @notice The prize pool this vault is participating in
    PrizePool public immutable prizePool;

    /// @notice World ID address book
    IWorldIdAddressBook public immutable worldIdAddressBook;

    /// @notice Address of the underlying deposit asset
    address public immutable asset;

    ////////////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the claimer is set
    /// @param claimer The new claimer address
    event SetClaimer(address indexed claimer);

    /// @notice Emitted when the prize excess recipient is set
    /// @param prizeExcessRecipient The new prize excess recipient
    event SetPrizeExcessRecipient(address indexed prizeExcessRecipient);

    /// @notice Emitted when the account deposit limit is set
    /// @param accountDepositLimit The new account deposit limit
    event SetAccountDepositLimit(uint256 accountDepositLimit);

    ////////////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown if the caller of `claimPrize` is not the `claimer`
    /// @param caller The caller of the function
    /// @param claimer The permitted claimer
    error CallerNotClaimer(address caller, address claimer);

    /// @notice Thrown when an account requires World ID verification
    /// @param account The account that is not verified
    error AccountNotVerifiedWithWorldId(address account);

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

    /// @notice Throws if the account is not currently verified with a world ID.
    /// @param _account The account to check
    modifier onlyVerifiedWorldId(address _account) {
        if (worldIdAddressBook.addressVerifiedUntil(_account) < block.timestamp) {
            revert AccountNotVerifiedWithWorldId(_account);
        }
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
    /// @param prizeExcessRecipient_ The initial prize excess recipient
    /// @param accountDepositLimit_ The initial account deposit limit in assets
    constructor(
        string memory name_,
        string memory symbol_,
        PrizePool prizePool_,
        IWorldIdAddressBook worldIdAddressBook_,
        address claimer_,
        address owner_,
        address prizeExcessRecipient_,
        uint256 accountDepositLimit_
    ) TwabERC20(name_, symbol_, prizePool_.twabController()) Ownable(owner_) {
        assert(address(worldIdAddressBook_) != address(0));
        prizePool = prizePool_;
        asset = address(prizePool_.prizeToken());
        worldIdAddressBook = worldIdAddressBook_;
        _setClaimer(claimer_);
        _setPrizeExcessRecipient(prizeExcessRecipient_);
        _setAccountDepositLimit(accountDepositLimit_);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Owner Functions
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Sets a new claimer
    /// @dev Only Owner
    /// @param _claimer The new claimer to set
    function setClaimer(address _claimer) external onlyOwner {
        _setClaimer(_claimer);
    }

    /// @notice Sets a new prize excess recipient
    /// @dev Only Owner
    /// @param _prizeExcessRecipient The new prize excess recipient to set
    function setPrizeExcessRecipient(address _prizeExcessRecipient) external onlyOwner {
        _setPrizeExcessRecipient(_prizeExcessRecipient);
    }

    /// @notice Sets a new account deposit limit
    /// @dev Only Owner
    /// @param _accountDepositLimit The new account deposit limit to set
    function setAccountDepositLimit(uint256 _accountDepositLimit) external onlyOwner {
        _setAccountDepositLimit(_accountDepositLimit);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // IClaimable Implementation
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IClaimable
    function claimPrize(
        address _winner,
        uint8 _tier,
        uint32 _prizeIndex,
        uint96 _claimReward,
        address _claimRewardRecipient
    ) external onlyVerifiedWorldId(_winner) returns (uint256) {
        if (msg.sender != claimer) revert CallerNotClaimer(msg.sender, claimer);
        uint24 _lastAwardedDrawId = prizePool.getLastAwardedDrawId();
        uint256 _startTimestamp = prizePool.drawOpensAt(
            prizePool.computeRangeStartDrawIdInclusive(
                _lastAwardedDrawId,
                prizePool.getTierAccrualDurationInDraws(_tier)
            )
        );
        uint256 _endTimestamp = prizePool.drawClosesAt(_lastAwardedDrawId);
        uint256 _winnerTwabForPrizeTier = twabController.getTwabBetween(address(this), _winner, _startTimestamp, _endTimestamp);
        uint256 _totalPrizeValue = prizePool.claimPrize(
            _winner,
            _tier,
            _prizeIndex,
            address(this),
            _claimReward,
            _claimRewardRecipient
        );
        uint256 _prizeAmountWon = _totalPrizeValue - _claimReward;
        if (_winnerTwabForPrizeTier > accountDepositLimit) {
            // Limit the prize amount won proportionally based on how much the winner's TWAB exceeds the deposit limit
            _prizeAmountWon = (_prizeAmountWon * accountDepositLimit) / _winnerTwabForPrizeTier;

            // Send the excess to the prize excess recipient
            IERC20(asset).safeTransfer(prizeExcessRecipient, _totalPrizeValue - _prizeAmountWon - _claimReward);
        }
        if (_prizeAmountWon > 0) {
            // Mint shares up to the winner's deposit limit and transfer the rest as assets if any
            uint256 _winnerDepositLimit = maxDeposit(_winner);
            if (_prizeAmountWon > _winnerDepositLimit) {
                _mint(_winner, _winnerDepositLimit);
                IERC20(asset).safeTransfer(_winner, _prizeAmountWon - _winnerDepositLimit);
            } else {
                _mint(_winner, _prizeAmountWon);
            }
        }
        return _totalPrizeValue;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // IERC20 Overrides
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ERC20
    /// @dev Prevents share token transfers if they would exceed the deposit limit of the recipient
    function _beforeTokenTransfer(address /*_from*/, address _to, uint256 _amount) internal virtual override onlyVerifiedWorldId(_to) {
        if (_amount > maxDeposit(_to)) {
            revert DepositLimitExceeded(_to, balanceOf(_to), _amount, accountDepositLimit);
        }
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
        if (!_isAccountVerified(_receiver)) {
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
        if (_assets == 0) {
            revert DepositZeroAssets();
        }
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
        if (_assets == 0) {
            revert WithdrawZeroAssets();
        }
        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, _assets);
        }
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

    ////////////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Sets the claimer address
    /// @dev Will revert if `_claimer` is address zero
    /// @param _claimer The new claimer address
    function _setClaimer(address _claimer) internal {
        assert(_claimer != address(0));
        claimer = _claimer;
        emit SetClaimer(_claimer);
    }

    /// @notice Sets the prize excess recipient
    /// @dev Will revert if `_prizeExcessRecipient` is address zero
    /// @param _prizeExcessRecipient The new prize excess recipient address
    function _setPrizeExcessRecipient(address _prizeExcessRecipient) internal {
        assert(_prizeExcessRecipient != address(0));
        prizeExcessRecipient = _prizeExcessRecipient;
        emit SetPrizeExcessRecipient(_prizeExcessRecipient);
    }

    /// @notice Sets a new account deposit limit
    /// @param _accountDepositLimit The new account deposit limit
    function _setAccountDepositLimit(uint256 _accountDepositLimit) internal {
        accountDepositLimit = _accountDepositLimit;
        emit SetAccountDepositLimit(_accountDepositLimit);
    }

    /// @notice Returns true if the account is actively verified with the World ID address book
    /// @param _account The account to check
    function _isAccountVerified(address _account) internal view returns (bool) {
        return worldIdAddressBook.addressVerifiedUntil(_account) >= block.timestamp;
    }

}
