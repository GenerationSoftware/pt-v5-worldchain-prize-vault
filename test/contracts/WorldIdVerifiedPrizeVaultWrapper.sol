// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { WorldIdVerifiedPrizeVault, PrizePool, IWorldIdAddressBook } from "../../src/WorldIdVerifiedPrizeVault.sol";

contract WorldIdVerifiedPrizeVaultWrapper is WorldIdVerifiedPrizeVault {

    constructor(
        string memory name_,
        string memory symbol_,
        PrizePool prizePool_,
        IWorldIdAddressBook worldIdAddressBook_,
        address claimer_,
        address owner_,
        uint256 accountDepositLimit_
    ) WorldIdVerifiedPrizeVault(
        name_,
        symbol_,
        prizePool_,
        worldIdAddressBook_,
        claimer_,
        owner_,
        accountDepositLimit_
    ) {}

    function mint(address _receiver, uint256 _amount) public {
        _mint(_receiver, _amount);
    }

    function burn(address _owner, uint256 _amount) public {
        _burn(_owner, _amount);
    }

}