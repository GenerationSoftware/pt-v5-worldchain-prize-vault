// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC4626Test, IMockERC20 } from "erc4626-tests/ERC4626.test.sol";

import { WorldIdVerifiedPrizeVaultWrapper, WorldIdVerifiedPrizeVault } from "./contracts/WorldIdVerifiedPrizeVaultWrapper.sol";
import { ERC4626, IERC4626, IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";
import { PrizePool, ConstructorParams, IERC20 as PrizePoolIERC20 } from "pt-v5-prize-pool/PrizePool.sol";
import { ERC20Mock } from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { MockWorldIdAddressBook, IWorldIdAddressBook } from "./contracts/MockWorldIdAddressBook.sol";
import { Strings } from "openzeppelin/utils/Strings.sol";

contract ERC4626FuzzTest is ERC4626Test {

    uint256 public currentTime;
    address public currentActor;
    address[] public actors;

    WorldIdVerifiedPrizeVaultWrapper public worldVault;

    MockWorldIdAddressBook public worldIdAddressBook;
    TwabController public twabController;
    PrizePool public prizePool;
    ERC20Mock public prizeToken;

    uint32 periodLength = 1 days;
    uint32 periodOffset = 0;

    uint256 public accountDepositLimit = 100e18;

    address public alice;
    address public bob;
    address public nonVerifiedAddress;
    address public claimer;
    address public owner;

    function setUp() public virtual override {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        nonVerifiedAddress = makeAddr("nonVerifiedAddress");
        claimer = makeAddr("claimer");
        owner = makeAddr("owner");

        worldIdAddressBook = new MockWorldIdAddressBook();
        vm.startPrank(alice);
        worldIdAddressBook.setAccountVerification(block.timestamp + 91 days);
        vm.stopPrank();
        vm.startPrank(bob);
        worldIdAddressBook.setAccountVerification(block.timestamp + 91 days);
        vm.stopPrank();

        prizeToken = new ERC20Mock();
        twabController = new TwabController(periodLength, periodOffset);
        prizePool = new PrizePool(
            ConstructorParams(
                PrizePoolIERC20(address(prizeToken)),
                twabController,
                address(this),
                0.5e18,
                1 days,
                uint48((block.timestamp / periodLength + 1) * periodLength),
                91,
                4,
                100,
                4,
                30,
                60
            )
        );
        worldVault = new WorldIdVerifiedPrizeVaultWrapper(
            "World Vault",
            "przWLD",
            prizePool,
            worldIdAddressBook,
            claimer,
            owner,
            accountDepositLimit
        );

        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = false;
        _underlying_ = worldVault.asset();
        _vault_ = address(worldVault);
    }

    /* ============ Override setup ============ */

    function setUpVault(Init memory init) public virtual override {
        for (uint256 i = 0; i < N; i++) {
            init.user[i] = makeAddr(Strings.toString(i));
            address user = init.user[i];

            vm.assume(_isEOA(user));
            uint256 shares = bound(init.share[i], 0, type(uint96).max);
            if (shares % 2 == 0) {
                // verify roughly half of accounts
                vm.prank(user);
                worldIdAddressBook.setAccountVerification(block.timestamp + 91 days);
                try IMockERC20(_underlying_).mint(user, shares) {} catch {
                    vm.assume(false);
                }

                _approve(_underlying_, user, _vault_, shares);

                vm.prank(user);
                try IERC4626(_vault_).deposit(shares, user) {} catch {
                    vm.assume(false);
                }
            } else {
                shares = 0;
            }

            uint256 assets = bound(init.asset[i], 0, type(uint256).max);
            try IMockERC20(_underlying_).mint(user, assets) {} catch {
                vm.assume(false);
            }
        }

        setUpYield(init);
    }

    // No yield
    function setUpYield(Init memory init) public virtual override { }

    function _max_deposit(address from) internal virtual override returns (uint256) {
        if (_unlimitedAmount) return type(uint96).max;
        return bound(IERC20(_underlying_).balanceOf(from), 0, IERC4626(_vault_).maxDeposit(from) * 2);
    }

    function _max_mint(address from) internal virtual override returns (uint256) {
        if (_unlimitedAmount) return type(uint96).max;
        return bound(vault_convertToShares(IERC20(_underlying_).balanceOf(from)), 0, IERC4626(_vault_).maxMint(from) * 2);
    }

    function _max_withdraw(address from) internal virtual override returns (uint256) {
        if (_unlimitedAmount) return type(uint96).max;
        return vault_convertToAssets(IERC20(_vault_).balanceOf(from));
    }

    function _max_redeem(address from) internal virtual override returns (uint256) {
        if (_unlimitedAmount) return type(uint96).max;
        return IERC20(_vault_).balanceOf(from);
    }
}