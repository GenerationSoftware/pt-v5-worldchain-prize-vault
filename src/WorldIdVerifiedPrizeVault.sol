// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TwabController } from "../lib/pt-v5-vault/src/TwabERC20.sol";
import { PrizePool } from "../lib/pt-v5-vault/lib/pt-v5-prize-pool/src/PrizePool.sol";
import { Ownable } from "../lib/pt-v5-vault/lib/owner-manager-contracts/contracts/Ownable.sol";
import { Claimable } from "../lib/pt-v5-vault/src/abstract/Claimable.sol";
import { ERC4626, ERC20, IERC20 } from "../lib/pt-v5-vault/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import { IWorldIdAddressBook } from "./interfaces/IWorldIdAddressBook.sol";

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
    // Errors
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown if the TwabController address is the zero address.
    error TwabControllerZeroAddress();

    ////////////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the account deposit limit is set
    /// @param accountDepositLimit The new account deposit limit
    event SetAccountDepositLimit(uint256 accountDepositLimit);

    ////////////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////////////

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
    ) ERC20(name_, symbol_) ERC4626(IERC20(prizePool_.prizeToken())) Ownable(owner_) Claimable(prizePool_, claimer_) {
        assert(address(worldIdAddressBook_) != address(0));
        twabController = prizePool_.twabController();
        if (address(0) == address(twabController)) revert TwabControllerZeroAddress();
        worldIdAddressBook = worldIdAddressBook_;
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

    /// @notice Sets a new account deposit limit
    /// @dev Only Owner
    /// @param _accountDepositLimit The new account deposit limit to set
    function setAccountDepositLimit(uint256 _accountDepositLimit) external onlyOwner {
        _setAccountDepositLimit(_accountDepositLimit);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // IERC4626 Overrides
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc ERC4626
    /// @dev limited by the per-account limiter and world ID verification
    function maxDeposit(address _receiver) public view override returns (uint256) {
        if (!_isAccountVerified(_receiver)) {
            return 0;
        } else {
            uint256 _receiverBalance = balanceOf(_receiver);
            return _receiverBalance >= accountDepositLimit ? 0 : accountDepositLimit - _receiverBalance;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////
    // IERC20 Overrides
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

    /// @notice Mints tokens to `_receiver` and increases the total supply.
    /// @dev Emits a {Transfer} event with `from` set to the zero address.
    /// @dev `_receiver` cannot be the zero address.
    /// @param _receiver Address that will receive the minted tokens
    /// @param _amount Tokens to mint
    function _mint(address _receiver, uint256 _amount) internal virtual override {
        _checkMint(_receiver, _amount);
        twabController.mint(_receiver, SafeCast.toUint96(_amount));
        emit Transfer(address(0), _receiver, _amount);
    }

    /// @notice Destroys tokens from `_owner` and reduces the total supply.
    /// @dev Emits a {Transfer} event with `to` set to the zero address.
    /// @dev `_owner` cannot be the zero address.
    /// @dev `_owner` must have at least `_amount` tokens.
    /// @param _owner The owner of the tokens
    /// @param _amount The amount of tokens to burn
    function _burn(address _owner, uint256 _amount) internal virtual override {
        twabController.burn(_owner, SafeCast.toUint96(_amount));
        emit Transfer(_owner, address(0), _amount);
    }

    /// @notice Transfers tokens from one account to another.
    /// @dev Emits a {Transfer} event.
    /// @dev `_from` cannot be the zero address.
    /// @dev `_to` cannot be the zero address.
    /// @dev `_from` must have a balance of at least `_amount`.
    /// @param _from Address to transfer from
    /// @param _to Address to transfer to
    /// @param _amount The amount of tokens to transfer
    function _transfer(address _from, address _to, uint256 _amount) internal virtual override {
        _checkMint(_to, _amount);
        twabController.transfer(_from, _to, SafeCast.toUint96(_amount));
        emit Transfer(_from, _to, _amount);
    }

    function _checkMint(address _to, uint256 _amount) internal virtual {
        if (worldIdAddressBook.addressVerifiedUntil(_to) < block.timestamp) {
            revert AccountNotVerifiedWithWorldId(_to);
        }
        if (_amount > maxDeposit(_to)) {
            revert DepositLimitExceeded(_to, balanceOf(_to), _amount, accountDepositLimit);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////////////

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
