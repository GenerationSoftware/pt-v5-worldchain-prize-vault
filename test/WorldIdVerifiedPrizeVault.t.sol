// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, stdError } from "forge-std/Test.sol";

import { WorldIdVerifiedPrizeVaultWrapper } from "./contracts/WorldIdVerifiedPrizeVaultWrapper.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";
import { PrizePool, ConstructorParams } from "pt-v5-prize-pool/PrizePool.sol";
import { ERC20Mock } from "../lib/pt-v5-vault/lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import { MockWorldIdAddressBook } from "./contracts/MockWorldIdAddressBook.sol";

contract WorldIdVerifiedPrizeVaultTest is Test {

    // Events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    WorldIdVerifiedPrizeVaultWrapper public worldVault;

    MockWorldIdAddressBook public worldIdAddressBook;
    TwabController public twabController;
    PrizePool public prizePool;
    ERC20Mock public prizeToken;

    uint32 periodLength = 1 days;
    uint32 periodOffset = 0;

    address alice;
    address bob;
    address claimer;
    address owner;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
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
                prizeToken,
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

    function testConstructor_twabControllerSet() public {
        assertEq(address(worldVault.twabController()), address(twabController));
    }

    function testConstructor_nameSet() public {
        assertEq(worldVault.name(), "World Vault");
    }

    function testConstructor_symbolSet() public {
        assertEq(worldVault.symbol(), "przWLD");
    }

    /* ============ balanceOf ============ */

    function testBalanceOf_startingBalanceZero() public {
        assertEq(worldVault.balanceOf(address(this)), 0);
    }

    /* ============ totalSupply ============ */

    function testBalanceOf_startingSupplyZero() public {
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

}