// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { WorldIdVerifiedPrizeVaultHarness, WorldIdVerifiedPrizeVaultWrapper, ERC20Mock } from "./contracts/WorldIdVerifiedPrizeVaultHarness.sol";

/// @dev This contract runs tests in a scenario where the yield vault can never lose funds (strictly increasing).
contract PrizeVaultInvariant is Test {
    WorldIdVerifiedPrizeVaultHarness public vaultHarness;

    modifier useCurrentTime() {
        vm.warp(vaultHarness.currentTime());
        _;
    }

    function setUp() external virtual {
        vaultHarness = new WorldIdVerifiedPrizeVaultHarness();
        targetContract(address(vaultHarness));
    }

    function invariantTotalSupplyLessThanOrEqualToTotalAssets() external useCurrentTime {
        uint256 totalAssets = vaultHarness.worldVault().totalAssets();
        uint256 totalSupply = vaultHarness.worldVault().totalSupply();
        assertLe(totalSupply, totalAssets);
    }

    function invariantNonVerifiedWalletCantDeposit() external useCurrentTime {
        address nonVerifiedAddress = vaultHarness.nonVerifiedAddress();
        WorldIdVerifiedPrizeVaultWrapper worldVault = vaultHarness.worldVault();
        ERC20Mock prizeToken = vaultHarness.prizeToken();
        uint256 balance = prizeToken.balanceOf(nonVerifiedAddress);
        if (balance > 0) {
            vm.startPrank(nonVerifiedAddress);
            prizeToken.approve(address(worldVault), balance);
            vm.expectRevert();
            worldVault.deposit(
                balance,
                nonVerifiedAddress
            );
            vm.stopPrank();
        }
    }

    function invariantCantDepositMoreThanMax() external useCurrentTime {
        address alice = vaultHarness.alice();
        WorldIdVerifiedPrizeVaultWrapper worldVault = vaultHarness.worldVault();
        if (vaultHarness.worldIdAddressBook().addressVerifiedUntil(alice) > block.timestamp) {
            uint256 balance = worldVault.balanceOf(alice);
            uint256 maxDepositLimit = worldVault.accountDepositLimit();
            if (balance >= maxDepositLimit) {
                assertEq(worldVault.maxDeposit(alice), 0);
                assertEq(worldVault.maxMint(alice), 0);
            } else {
                assertEq(worldVault.maxDeposit(alice), maxDepositLimit - balance);
                assertEq(worldVault.maxMint(alice), maxDepositLimit - balance);
            }
        } else {
            assertEq(worldVault.maxDeposit(alice), 0);
            assertEq(worldVault.maxMint(alice), 0);
        }
    }

}