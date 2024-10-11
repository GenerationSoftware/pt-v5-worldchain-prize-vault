// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { WorldIdVerifiedPrizeVaultWrapper, WorldIdVerifiedPrizeVault } from "../contracts/WorldIdVerifiedPrizeVaultWrapper.sol";
import { ERC4626 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";
import { PrizePool, ConstructorParams, IERC20 as PrizePoolIERC20 } from "pt-v5-prize-pool/PrizePool.sol";
import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { MockWorldIdAddressBook, IWorldIdAddressBook } from "../contracts/MockWorldIdAddressBook.sol";
import { CommonBase } from "forge-std/Base.sol";

contract WorldIdVerifiedPrizeVaultHarness is StdCheats, StdUtils, CommonBase {

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

    /* ============ Time Warp Helpers ============ */

    modifier useCurrentTime() {
        vm.warp(currentTime);
        _;
    }

    function setCurrentTime(uint256 newTime) internal {
        currentTime = newTime;
        vm.warp(currentTime);
    }

    /* ============ Actor Helpers ============ */

    function _actor(uint256 actorIndexSeed) internal view returns(address) {
        return actors[_bound(actorIndexSeed, 0, actors.length - 1)];
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actor(actorIndexSeed);
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /* ============ Constructor ============ */

    constructor() {
        setCurrentTime(1); // non-zero start time

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        nonVerifiedAddress = makeAddr("nonVerifiedAddress");
        claimer = makeAddr("claimer");
        owner = makeAddr("owner");

        actors = new address[](5);
        actors[0] = owner;
        actors[1] = claimer;
        actors[2] = alice;
        actors[3] = bob;
        actors[4] = nonVerifiedAddress;

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
    }

    function sendAssetsToVaultDirectly(uint256 amount) public useCurrentTime {
        amount = _bound(amount, 0, type(uint128).max);
        prizeToken.mint(address(worldVault), amount);
    }

    function timePasses(uint48 sec) public useCurrentTime {
        setCurrentTime(block.timestamp + sec);
    }

    function addressVerification(uint256 actorIndexSeed, uint48 secInFuture) public useCurrentTime useActor(actorIndexSeed) {
        if(currentActor != nonVerifiedAddress) {
            worldIdAddressBook.setAccountVerification(block.timestamp + secInFuture);
        }
    }

    function mintTokensToAddress(uint256 actorIndexSeed, uint256 amount) public useCurrentTime useActor(actorIndexSeed) {
        amount = _bound(amount, 0, type(uint128).max);
        prizeToken.mint(currentActor, amount);
    }

    function deposit(uint256 actorIndexSeed, uint256 amount) public useCurrentTime useActor(actorIndexSeed) {
        amount = _bound(amount, 0, prizeToken.balanceOf(currentActor));
        prizeToken.approve(address(worldVault), amount);
        worldVault.deposit(amount, currentActor);
    }

    function mint(uint256 actorIndexSeed, uint256 amount) public useCurrentTime useActor(actorIndexSeed) {
        amount = _bound(amount, 0, prizeToken.balanceOf(currentActor));
        prizeToken.approve(address(worldVault), amount);
        worldVault.mint(amount, currentActor);
    }

    function withdraw(uint256 actorIndexSeed, uint256 recipientSeed, uint256 amount) public useCurrentTime useActor(actorIndexSeed) {
        amount = _bound(amount, 0, worldVault.balanceOf(currentActor));
        worldVault.withdraw(amount, currentActor, _actor(recipientSeed));
    }

    function redeem(uint256 actorIndexSeed, uint256 recipientSeed, uint256 amount) public useCurrentTime useActor(actorIndexSeed) {
        amount = _bound(amount, 0, worldVault.balanceOf(currentActor));
        worldVault.redeem(amount, currentActor, _actor(recipientSeed));
    }

    function transfer(uint256 actorIndexSeed, uint256 recipientSeed, uint256 amount) public useCurrentTime useActor(actorIndexSeed) {
        amount = _bound(amount, 0, worldVault.balanceOf(currentActor));
        worldVault.transfer(_actor(recipientSeed), amount);
    }

    function setDepositLimit(uint256 depositLimit) public useCurrentTime useActor(0) {
        worldVault.setAccountDepositLimit(depositLimit);
    }

}