// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// These files are imported so that the compilation generates the correct artifacts for tests
import "@rawrshak/rawr-content/contracts/resolver/AddressResolver.sol";
import "@rawrshak/rawr-content/contracts/testContracts/token/MockToken.sol";
import "@rawrshak/rawr-content/contracts/content/AccessControlManager.sol";
import "@rawrshak/rawr-content/contracts/content/ContentStorage.sol";
import "@rawrshak/rawr-content/contracts/content/Content.sol";
import "@rawrshak/rawr-content/contracts/content/ContentManager.sol";
import "@rawrshak/rawr-content/contracts/content/factory/ContentFactory.sol";
import "@rawrshak/rawr-content/contracts/testContracts/staking/MockStaking.sol";