// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@rawrshak/rawr-content/contracts/escrow/EscrowBase.sol";
import "@rawrshak/rawr-content/contracts/utils/EnumerableMapsExtension.sol";
import "./interfaces/IErc20Escrow.sol";

contract Erc20Escrow is IErc20Escrow, EscrowBase {
    /******************** Constants ********************/
    /*
     * IErc20Escrow == 0xfeb2d5c7
     * IEscrowBase: 0x7965db0b
     * IAccessControlUpgradeable: 0x7965db0b
     */

    using EnumerableSetUpgradeable for *;
    using EnumerableMapsExtension for *;
    
    /***************** Stored Variables *****************/
    EnumerableSetUpgradeable.AddressSet supportedTokens;

    struct EscrowedAmount {
        address token;
        uint256 amount;
    }
    mapping(uint256 => EscrowedAmount) escrowedByOrder;
    mapping(address => EnumerableMapsExtension.AddressToUintMap) claimableByOwner;

    /******************** Public API ********************/
    function initialize() public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __EscrowBase_init_unchained();
        __Erc20Escrow_init_unchained();
    }

    function __Erc20Escrow_init_unchained() internal onlyInitializing {
        _registerInterface(type(IErc20Escrow).interfaceId);
    }

    function addSupportedTokens(address token) external override onlyRole(MANAGER_ROLE) {
        // no need to check for input as we are the only ones to call it and we will always only
        // add an ERC20 token
        supportedTokens.add(token);

        emit AddedTokenSupport(token);
    }

    function deposit(
        address _token,
        uint256 _orderId,
        address _sender,
        uint256 _amount
    ) external override onlyRole(MANAGER_ROLE) {
        // No need to do checks. The exchange contracts will do the checks.
        escrowedByOrder[_orderId].token = _token;

        // There are partial order fills so the amounts are added
        escrowedByOrder[_orderId].amount = escrowedByOrder[_orderId].amount + _amount;
        
        // Send the Token Amount to the Escrow
        IERC20Upgradeable(_token).transferFrom(_sender, address(this), _amount);
    }

    function depositBatch(
        address _token,
        uint256[] calldata _orderIds,
        address _sender,
        uint256[] calldata _amounts
    ) external override onlyRole(MANAGER_ROLE) {
        uint256 total;
        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_amounts[i] > 0) {    
                // Update escrowedByOrder for each order
                escrowedByOrder[_orderIds[i]].token = _token;
                escrowedByOrder[_orderIds[i]].amount = escrowedByOrder[_orderIds[i]].amount + _amounts[i];
                // add to total
                total += _amounts[i];
            }
        }
        // Send the total amount of tokens to the Escrow
        IERC20Upgradeable(_token).transferFrom(_sender, address(this), total);
    }

    function withdraw(
        uint256 _orderId,
        address _receiver,
        uint256 _amount
    ) external override onlyRole(MANAGER_ROLE) {
        require(escrowedByOrder[_orderId].amount >= _amount, "Invalid amount");

        escrowedByOrder[_orderId].amount = escrowedByOrder[_orderId].amount - _amount;
        IERC20Upgradeable(escrowedByOrder[_orderId].token).transfer(_receiver, _amount);
        if (escrowedByOrder[_orderId].amount == 0) {
            delete escrowedByOrder[_orderId].token;
        }
    }

    function withdrawBatch(
        uint256[] calldata _orderIds,
        address _receiver,
        uint256[] calldata _amounts
    ) external override onlyRole(MANAGER_ROLE) {
        uint256 total;
        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_amounts[i] > 0) {
                // Update escrowedByOrder for each order
                require(escrowedByOrder[_orderIds[i]].amount >= _amounts[i], "Invalid amount");
                escrowedByOrder[_orderIds[i]].amount -= _amounts[i];
                // add to total
                total += _amounts[i];
            }
        }
        // Withdraw the total amount of tokens from Escrow
        IERC20Upgradeable(escrowedByOrder[_orderIds[0]].token).transfer(_receiver, total);
    }
    
    // Deposit Creator Royalties from user to escrow
    function transferRoyalty(
        address _token,
        address _sender,
        address _owner,
        uint256 _amount
    ) external override onlyRole(MANAGER_ROLE) {
        // No need to do checks. The exchange contracts will do the checks.
        if (!claimableByOwner[_owner].contains(_token)) {
            claimableByOwner[_owner].set(_token, _amount);
        } else {
            claimableByOwner[_owner].set(_token, claimableByOwner[_owner].get(_token) + _amount);
        }
        IERC20Upgradeable(_token).transferFrom(_sender, address(this), _amount);
    }

    // Transfer Creator Royalty from escrowed buy order (multiple ids) to escrow
    function transferRoyalties(
        uint256[] calldata _orderIds,
        address _owner,
        uint256[] calldata _amounts
    ) external override onlyRole(MANAGER_ROLE) {        
        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_amounts[i] > 0) {
                transferRoyalty(_orderIds[i], _owner, _amounts[i]);
            }
        }
    }

    // Transfer Creator Royalty from escrowed buy order (single id) to escrow
    function transferRoyalty(
        uint256 _orderId,
        address _owner,
        uint256 _amount
    ) public override onlyRole(MANAGER_ROLE) {        
        require(escrowedByOrder[_orderId].amount >= _amount, "Invalid royalty amount");

        // No need to do checks. The exchange contracts will do the checks.
        address token = escrowedByOrder[_orderId].token;
        escrowedByOrder[_orderId].amount = escrowedByOrder[_orderId].amount - _amount;

        if (!claimableByOwner[_owner].contains(token)) {
            claimableByOwner[_owner].set(token, _amount);
        } else {
            claimableByOwner[_owner].set(token, claimableByOwner[_owner].get(token) + _amount);
        }
    }

    // Deposit platform fees from buyer to escrow
    function transferPlatformFee(address _token, address _sender, address _feesEscrow, uint256 _amount) external override onlyRole(MANAGER_ROLE) {
        // No need to do checks. The exchange contracts will do the checks.
        IERC20Upgradeable(_token).transferFrom(_sender, _feesEscrow, _amount);
    }

    // Transfer Platform fees from escrowed by order (multiple ids) to escrow
    function transferPlatformFees(
        uint256[] calldata _orderIds, 
        address _feesEscrow, 
        uint256[] calldata _platformFees, 
        uint256 _totalFee
    ) external override onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < _orderIds.length; i++) {
            // No need to do checks. The exchange contracts will do the checks.
            escrowedByOrder[_orderIds[i]].amount -= _platformFees[i];
        }
        IERC20Upgradeable(escrowedByOrder[_orderIds[0]].token).transfer(_feesEscrow, _totalFee);
    }

    // Transfer Platform fees from escrowed by order (single id) to escrow
    function transferPlatformFee(uint256 _orderId, address _feesEscrow, uint256 _amount) external override onlyRole(MANAGER_ROLE) {
        // No need to do checks. The exchange contracts will do the checks.
        escrowedByOrder[_orderId].amount = escrowedByOrder[_orderId].amount - _amount;
        IERC20Upgradeable(escrowedByOrder[_orderId].token).transfer(_feesEscrow, _amount);
    }

    function claimRoyalties(address _owner) external override onlyRole(MANAGER_ROLE) {
        // Check should be done above this
        uint256 numOfTokens = _getClaimableTokensLength(_owner);
        uint256 counter = 0;
        address[] memory tokens = new address[](numOfTokens);
        uint256[] memory amounts = new uint256[](numOfTokens);
        for (uint256 i = 0; i < claimableByOwner[_owner].length(); i++) {
            (address token, uint256 amount) = claimableByOwner[_owner].at(i);
            if (amount > 0) {
                // Note: we're not removing the entry because we expect that it will be used
                // again eventually.
                claimableByOwner[_owner].set(token, 0);
                IERC20Upgradeable(token).transfer(_owner, amount);
                tokens[counter] = token;
                amounts[counter] = amount;
                counter++;
            }
        }

        emit ClaimedRoyalties(_owner, tokens, amounts);
    }

    function isTokenSupported(address token) public override view returns(bool) {
        return supportedTokens.contains(token);
    }

    function escrowedTokensByOrder(uint256 _orderId) external override view returns(uint256) {
        return escrowedByOrder[_orderId].amount;
    }
    
    function claimableTokensByOwner(address _owner) external override view returns(address[] memory tokens, uint256[] memory amounts) {
        // Check should be done above this
        // Count how much memory to allocate
        uint256 numOfTokens = _getClaimableTokensLength(_owner);
        tokens = new address[](numOfTokens);
        amounts = new uint256[](numOfTokens);
        uint256 counter = 0;
        for (uint256 i = 0; i < claimableByOwner[_owner].length(); i++) {
            (address token, uint256 amount) = claimableByOwner[_owner].at(i);
            if (amount > 0) {
                tokens[counter] = token;
                amounts[counter] = amount;
                counter++;
            }
        }
    }

    /**************** Internal Functions ****************/
    function _getClaimableTokensLength(address _owner) internal view returns(uint256) {
        uint256 counter = 0;
        for (uint256 i = 0; i < claimableByOwner[_owner].length(); i++) {
            (, uint256 amount) = claimableByOwner[_owner].at(i);
            if (amount > 0) {
                counter++;
            }
        }
        return counter;
    }

    uint256[50] private __gap;
}