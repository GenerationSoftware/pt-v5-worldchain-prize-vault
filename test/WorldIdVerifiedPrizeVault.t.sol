// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, stdError } from "forge-std/Test.sol";

import { WorldIdVerifiedPrizeVaultWrapper, WorldIdVerifiedPrizeVault } from "./contracts/WorldIdVerifiedPrizeVaultWrapper.sol";
import { ERC4626 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";
import { PrizePool, ConstructorParams, IERC20 as PrizePoolIERC20 } from "pt-v5-prize-pool/PrizePool.sol";
import { ERC20Mock } from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { MockWorldIdAddressBook, IWorldIdAddressBook } from "./contracts/MockWorldIdAddressBook.sol";

contract WorldIdVerifiedPrizeVaultTest is Test {

    // Events
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event SetAccountDepositLimit(uint256 accountDepositLimit);

    WorldIdVerifiedPrizeVaultWrapper public worldVault;

    MockWorldIdAddressBook public worldIdAddressBook;
    TwabController public twabController;
    PrizePool public prizePool;
    ERC20Mock public prizeToken;

    uint32 periodLength = 1 days;
    uint32 periodOffset = 0;

    address alice;
    address bob;
    address nonVerifiedAddress;
    address claimer;
    address owner;

    function setUp() public {
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
            100e18 // account deposit limit
        );
    }

    /* ============ Constructor ============ */

    function testConstructor_twabControllerSet() public view {
        assertEq(address(worldVault.twabController()), address(twabController));
    }

    function testConstructor_worldIdAddressBookSet() public view {
        assertEq(address(worldVault.worldIdAddressBook()), address(worldIdAddressBook));
    }

    function testConstructor_worldIdAddressBookNotZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(WorldIdVerifiedPrizeVault.WorldIdAddressBookZeroAddress.selector));
        worldVault = new WorldIdVerifiedPrizeVaultWrapper(
            "World Vault",
            "przWLD",
            prizePool,
            IWorldIdAddressBook(address(0)), // address book
            claimer,
            owner,
            101e18 // account deposit limit
        );
    }

    function testConstructor_accountDepositLimitSet() public {
        vm.expectEmit();
        emit SetAccountDepositLimit(101e18);
        worldVault = new WorldIdVerifiedPrizeVaultWrapper(
            "World Vault",
            "przWLD",
            prizePool,
            worldIdAddressBook,
            claimer,
            owner,
            101e18 // account deposit limit
        );
        assertEq(worldVault.accountDepositLimit(), uint256(101e18));
    }

    function testConstructor_nameSet() public view {
        assertEq(worldVault.name(), "World Vault");
    }

    function testConstructor_symbolSet() public view {
        assertEq(worldVault.symbol(), "przWLD");
    }

    function testConstructor_ownerSet() public view {
        assertEq(worldVault.owner(), owner);
    }

    function testConstructor_claimerSet() public view {
        assertEq(worldVault.claimer(), claimer);
    }

    function testConstructor_assetSet() public view {
        assertEq(worldVault.asset(), address(prizeToken));
    }

    /* ============ balanceOf ============ */

    function testBalanceOf_startingBalanceZero() public view {
        assertEq(worldVault.balanceOf(address(this)), 0);
    }

    /* ============ totalSupply ============ */

    function testBalanceOf_startingSupplyZero() public view {
        assertEq(worldVault.totalSupply(), 0);
    }

    /* ============ mint ============ */

    function testMint_updatesBalance() public {
        assertEq(worldVault.balanceOf(alice), 0);
        worldVault.mint(alice, 1e18);
        assertEq(worldVault.balanceOf(alice), 1e18);
        worldVault.mint(alice, 2e18 + 1);
        assertEq(worldVault.balanceOf(alice), 3e18 + 1);
    }

    function testMint_updatesSupply() public {
        assertEq(worldVault.totalSupply(), 0);
        worldVault.mint(alice, 1e18);
        assertEq(worldVault.totalSupply(), 1e18);
        worldVault.mint(bob, 1);
        assertEq(worldVault.totalSupply(), 1e18 + 1);
    }

    function testMint_emitsTransfer() public {
        vm.expectEmit();
        emit Transfer(address(0), alice, 1);
        worldVault.mint(alice, 1);
    }

    /* ============ burn ============ */

    function testBurn_updatesBalance() public {
        assertEq(worldVault.balanceOf(alice), 0);
        worldVault.mint(alice, 1e18);
        assertEq(worldVault.balanceOf(alice), 1e18);
        worldVault.burn(alice, 1);
        assertEq(worldVault.balanceOf(alice), 1e18 - 1);
    }

    function testBurn_updatesSupply() public {
        assertEq(worldVault.totalSupply(), 0);
        worldVault.mint(alice, 1e18);
        worldVault.mint(bob, 1e18);
        assertEq(worldVault.totalSupply(), 2e18);
        worldVault.burn(bob, 1e18 - 1);
        assertEq(worldVault.totalSupply(), 1e18 + 1);
    }

    function testBurn_emitsTransfer() public {
        worldVault.mint(alice, 1);
        vm.expectEmit();
        emit Transfer(alice, address(0), 1);
        worldVault.burn(alice, 1);
    }

    /* ============ transfer ============ */

    function testTransfer_updatesBalances() public {
        worldVault.mint(alice, 1e18);
        assertEq(worldVault.balanceOf(alice), 1e18);
        assertEq(worldVault.balanceOf(bob), 0);
        vm.startPrank(alice);
        worldVault.transfer(bob, 4e17);
        vm.stopPrank();
        assertEq(worldVault.balanceOf(alice), 6e17);
        assertEq(worldVault.balanceOf(bob), 4e17);
    }

    function testTransfer_noChangeToSupply() public {
        worldVault.mint(alice, 1e18);
        worldVault.mint(bob, 1e18);
        assertEq(worldVault.totalSupply(), 2e18);
        vm.startPrank(alice);
        worldVault.transfer(bob, 5e17);
        vm.stopPrank();
        assertEq(worldVault.totalSupply(), 2e18);
    }

    function testTransfer_emitsTransfer() public {
        worldVault.mint(alice, 1);
        vm.expectEmit();
        emit Transfer(alice, bob, 1);
        vm.startPrank(alice);
        worldVault.transfer(bob, 1);
        vm.stopPrank();
    }

    /* ============ uint96 limiter ============ */

    function testLimitUint96() public {
        vm.startPrank(owner);
        worldVault.setAccountDepositLimit(type(uint256).max);
        vm.stopPrank();

        assertEq(worldVault.balanceOf(alice), 0);
        assertEq(worldVault.totalSupply(), 0);

        worldVault.mint(alice, type(uint96).max);
        
        assertEq(worldVault.balanceOf(alice), type(uint96).max);
        assertEq(worldVault.totalSupply(), type(uint96).max);

        vm.expectRevert(stdError.arithmeticError);
        worldVault.mint(alice, 1);

        vm.startPrank(alice);
        worldVault.transfer(bob, type(uint96).max);
        vm.stopPrank();

        assertEq(worldVault.balanceOf(alice), 0);
        assertEq(worldVault.balanceOf(bob), type(uint96).max);
        assertEq(worldVault.totalSupply(), type(uint96).max);

        vm.startPrank(bob);
        worldVault.transfer(alice, type(uint96).max / 2);
        vm.stopPrank();

        assertEq(worldVault.balanceOf(alice), type(uint96).max / 2);
        assertEq(worldVault.balanceOf(bob), type(uint96).max / 2 + 1);
        assertEq(worldVault.totalSupply(), type(uint96).max);

        worldVault.burn(alice, type(uint96).max / 2);
        worldVault.burn(bob, type(uint96).max / 2 + 1);

        assertEq(worldVault.balanceOf(alice), 0);
        assertEq(worldVault.balanceOf(bob), 0);
        assertEq(worldVault.totalSupply(), 0);
    }

    /* ============ verified wallet deposit limit ============ */

    function testDepositLimit_depositNonVerified() public {
        vm.startPrank(nonVerifiedAddress);
        prizeToken.mint(nonVerifiedAddress, 1e18);
        prizeToken.approve(address(worldVault), 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxDeposit.selector,
                nonVerifiedAddress,
                1e18,
                0
            )
        );
        worldVault.deposit(1e18, nonVerifiedAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxMint.selector,
                nonVerifiedAddress,
                1e18,
                0
            )
        );
        worldVault.mint(1e18, nonVerifiedAddress);

        vm.stopPrank();
    }

    function testDepositLimit_transferToNonVerified() public {
        vm.startPrank(alice);
        prizeToken.mint(alice, 1e18);
        prizeToken.approve(address(worldVault), 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxDeposit.selector,
                nonVerifiedAddress,
                1e18,
                0
            )
        );
        worldVault.deposit(1e18, nonVerifiedAddress); // transfer to non-verified

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxMint.selector,
                nonVerifiedAddress,
                1e18,
                0
            )
        );
        worldVault.mint(1e18, nonVerifiedAddress); // transfer to non-verified

        worldVault.deposit(1e18, alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                WorldIdVerifiedPrizeVault.TransferLimitExceeded.selector,
                nonVerifiedAddress,
                1e18,
                0
            )
        );
        worldVault.transfer(nonVerifiedAddress, 1e18);

        worldVault.approve(address(this), 1e18);
        vm.stopPrank();
        vm.expectRevert(
            abi.encodeWithSelector(
                WorldIdVerifiedPrizeVault.TransferLimitExceeded.selector,
                nonVerifiedAddress,
                1e18,
                0
            )
        );
        worldVault.transferFrom(alice, nonVerifiedAddress, 1e18);
    }

    function testDepositLimit_previouslyVerifiedAccount() public {
        vm.startPrank(alice);
        prizeToken.mint(alice, 100e18);
        prizeToken.approve(address(worldVault), 100e18);
        worldVault.deposit(1e18, alice);

        vm.warp(worldIdAddressBook.addressVerifiedUntil(alice) + 1);

        // alice cannot make new deposits or mints
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxDeposit.selector,
                alice,
                1e18,
                0
            )
        );
        worldVault.deposit(1e18, alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxMint.selector,
                alice,
                1e18,
                0
            )
        );
        worldVault.mint(1e18, alice);

        // others cannot transfer shares to alice
        vm.startPrank(bob);
        worldIdAddressBook.setAccountVerification(block.timestamp);
        prizeToken.mint(bob, 100e18);
        prizeToken.approve(address(worldVault), 100e18);
        worldVault.deposit(1e18, bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                WorldIdVerifiedPrizeVault.TransferLimitExceeded.selector,
                alice,
                1e18,
                0
            )
        );
        worldVault.transfer(alice, 1e18);

        // alice can still transfer shares to other verified wallets
        vm.startPrank(alice);
        assertEq(worldVault.balanceOf(alice), 1e18);
        worldVault.transfer(bob, 0.5e18);
        assertEq(worldVault.balanceOf(alice), 0.5e18);
        assertEq(worldVault.balanceOf(bob), 1.5e18);

        // alice cannot transfer shares to a non-verified wallet
        vm.expectRevert(
            abi.encodeWithSelector(
                WorldIdVerifiedPrizeVault.TransferLimitExceeded.selector,
                nonVerifiedAddress,
                0.1e18,
                0
            )
        );
        worldVault.transfer(nonVerifiedAddress, 0.1e18);

        // alice can still withdraw or redeem her shares
        assertEq(worldVault.balanceOf(alice), 0.5e18);
        assertEq(prizeToken.balanceOf(alice), 99e18);
        worldVault.withdraw(0.25e18, alice, alice);
        assertEq(worldVault.balanceOf(alice), 0.25e18);
        assertEq(prizeToken.balanceOf(alice), 99.25e18);
        worldVault.redeem(0.25e18, alice, alice);
        assertEq(worldVault.balanceOf(alice), 0);
        assertEq(prizeToken.balanceOf(alice), 99.5e18);

        vm.stopPrank();
    }

    function testDepositLimit_previouslyAccountWithMoreThanCurrentLimit() public {
        vm.startPrank(alice);
        prizeToken.mint(alice, 200e18);
        prizeToken.approve(address(worldVault), 200e18);
        worldVault.deposit(100e18, alice);

        // new limit is set to lower than before
        vm.startPrank(owner);
        worldVault.setAccountDepositLimit(10e18);

        // alice cannot make new deposits or mints
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxDeposit.selector,
                alice,
                1e18,
                0
            )
        );
        worldVault.deposit(1e18, alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxMint.selector,
                alice,
                1e18,
                0
            )
        );
        worldVault.mint(1e18, alice);

        // others cannot transfer shares to alice
        vm.startPrank(bob);
        prizeToken.mint(bob, 100e18);
        prizeToken.approve(address(worldVault), 100e18);
        worldVault.deposit(1e18, bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                WorldIdVerifiedPrizeVault.TransferLimitExceeded.selector,
                alice,
                1e18,
                0
            )
        );
        worldVault.transfer(alice, 1e18);

        // alice can still transfer shares to other verified wallets
        vm.startPrank(alice);
        assertEq(worldVault.balanceOf(alice), 100e18);
        worldVault.transfer(bob, 0.5e18);
        assertEq(worldVault.balanceOf(alice), 99.5e18);
        assertEq(worldVault.balanceOf(bob), 1.5e18);

        // alice cannot transfer shares to a non-verified wallet
        vm.expectRevert(
            abi.encodeWithSelector(
                WorldIdVerifiedPrizeVault.TransferLimitExceeded.selector,
                nonVerifiedAddress,
                0.1e18,
                0
            )
        );
        worldVault.transfer(nonVerifiedAddress, 0.1e18);

        // alice can still withdraw or redeem her shares
        assertEq(worldVault.balanceOf(alice), 99.5e18);
        assertEq(prizeToken.balanceOf(alice), 100e18);
        worldVault.withdraw(0.5e18, alice, alice);
        assertEq(worldVault.balanceOf(alice), 99e18);
        assertEq(prizeToken.balanceOf(alice), 100.5e18);
        worldVault.redeem(99e18, alice, alice);
        assertEq(worldVault.balanceOf(alice), 0);
        assertEq(prizeToken.balanceOf(alice), 199.5e18);

        // alice can make new deposits since she is now under the limit
        assertEq(worldVault.maxDeposit(alice), 10e18);
        assertEq(worldVault.maxMint(alice), 10e18);

        vm.stopPrank();
    }

    function testSetDepositLimit_notOwner() public {
        vm.expectRevert();
        worldVault.setAccountDepositLimit(10e18);
    }

    function testSetDepositLimit_isOwner() public {
        vm.startPrank(owner);
        assertEq(worldVault.accountDepositLimit(), 100e18);

        vm.expectEmit();
        emit SetAccountDepositLimit(10e18);
        worldVault.setAccountDepositLimit(10e18);
        assertEq(worldVault.accountDepositLimit(), 10e18);

        vm.expectEmit();
        emit SetAccountDepositLimit(200e18);
        worldVault.setAccountDepositLimit(200e18);
        assertEq(worldVault.accountDepositLimit(), 200e18);

        vm.stopPrank();
    }

}