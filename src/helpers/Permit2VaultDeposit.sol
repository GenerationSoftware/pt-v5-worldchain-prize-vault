// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPermit2 } from "../interfaces/IPermit2.sol";
import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20, SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Permit2 Vault Deposit
/// @author G9 Software Inc.
/// @notice Acts as a proxy deposit contract for deposits using Permit2 signature transfer
/// instead of a direct approval.
contract Permit2VaultDeposit {
  using SafeERC20 for IERC20;

  IPermit2 public immutable permit2;

  constructor(address permit2_) {
    permit2 = IPermit2(permit2_);
  }

  /// @notice Uses a Permit2 signature transfer to pull assets from the caller and deposit
  /// them into the specified vault on their behalf.
  /// @param vault The vault to deposit into
  /// @param amount The amount of assets to deposit
  /// @param nonce The nonce used for the Permit2 signature
  /// @param deadline The dealine used for the Permit2 signature
  /// @param signature The Permit2 signature
  /// @return uint256 The amount of vault shares minted to the depositor
  function permitDeposit(
    address vault,
    uint256 amount,
    uint256 nonce,
    uint256 deadline,
    bytes calldata signature
  ) external returns (uint256) {
    address asset = IERC4626(vault).asset();
    permit2.permitTransferFrom(
      IPermit2.PermitTransferFrom(
        IPermit2.TokenPermissions(asset, amount),
        nonce,
        deadline
      ),
      IPermit2.SignatureTransferDetails(
        address(this),
        amount
      ),
      msg.sender,
      signature
    );
    IERC20(asset).forceApprove(vault, amount);
    return IERC4626(vault).deposit(amount, msg.sender);
  }

}