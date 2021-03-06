// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol";
import "@rawrshak/rawr-content/contracts/resolver/IAddressResolver.sol";

abstract contract ManagerBase is OwnableUpgradeable, ERC165StorageUpgradeable {
    /***************** Stored Variables *****************/
    IAddressResolver internal resolver;

    /******************** Public API ********************/
    function __ManagerBase_init_unchained(address _resolver) internal onlyInitializing {
        require(_resolver != address(0), "resolver passed.");
        resolver = IAddressResolver(_resolver);
    }

    uint256[50] private __gap;
}