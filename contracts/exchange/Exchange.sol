// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../libraries/LibOrder.sol";
import "./interfaces/IRoyaltyManager.sol";
import "./interfaces/IOrderbook.sol";
import "./interfaces/IExecutionManager.sol";
import "./interfaces/IExchange.sol";

contract Exchange is IExchange, ContextUpgradeable, OwnableUpgradeable, ERC165StorageUpgradeable {    
    /******************** Interfaces ********************/
    /*
     * IExchange == 0xdf858c9f
     */

    /***************** Stored Variables *****************/
    IRoyaltyManager royaltyManager;
    IOrderbook orderbook;
    IExecutionManager executionManager;

    /******************** Public API ********************/
    function initialize(address _royaltyManager, address _orderbook, address _executionManager) public initializer {
        // We don't run the interface checks because we're the only one who will deploy this so
        // we know that the addresses are correct
        __Context_init_unchained();
        __Ownable_init_unchained();
        __Exchange_init_unchained(_royaltyManager, _orderbook, _executionManager);
    }

    function __Exchange_init_unchained(address _royaltyManager, address _orderbook, address _executionManager) internal onlyInitializing {
        _registerInterface(type(IExchange).interfaceId);
          
        royaltyManager = IRoyaltyManager(_royaltyManager);
        orderbook = IOrderbook(_orderbook);
        executionManager = IExecutionManager(_executionManager);
    }

    // exchange functions
    function placeOrder(LibOrder.OrderInput memory _order) external override {        
        LibOrder.verifyOrderInput(_order, _msgSender());
        require(executionManager.verifyToken(_order.token), "Token is not supported.");

        // Note: not checking for token id validity. If Id doesn't exist and the user places 
        // a buy order, it will escrow the tokens until the user cancels the order. If the user
        // creates a sell order for an invalid id, the transaction will fail due to invalid 
        // asset transfer to escrow. The UI should not allow either, but if someone interacts
        // with the smart contract, these two outcomes are fine.
        
        // place order in orderbook
        uint256 id = orderbook.placeOrder(_order);

        if (_order.isBuyOrder) {
            // if it's a buy order, move tokens to ERC20 escrow.
            uint256 tokenAmount = _order.amount * _order.price;
            executionManager.placeBuyOrder(id, _order.token, _msgSender(), tokenAmount);
        } else {
            // if it's a sell order, move NFT to escrow
            executionManager.placeSellOrder(id, _msgSender(), _order.asset, _order.amount);            
        }

        emit OrderPlaced(_msgSender(), id, _order);
    }

    function fillOrder(
        uint256 _orderId,
        uint256 amountToFill
    ) external override {
        // Verify order exists
        require(orderbook.exists(_orderId), "Non-existent order");
        
        // get the order data
        LibOrder.Order memory order = orderbook.getOrder(_orderId);

        // Get order amounts and payment
        uint256 orderAmount = (order.amountOrdered - order.amountFilled);
        if (amountToFill < orderAmount) {
            orderAmount = amountToFill;
        }
        require(orderAmount > 0, "Invalid order amount");

        uint256 volume = (order.price * orderAmount);

        // Orderbook -> fill order
        orderbook.fillOrder(_orderId, orderAmount);

        // Calculate and deduct royalties
        (address receiver,
        uint256 royaltyFee,
        uint256 remaining) = royaltyManager.payableRoyalties(order.asset, volume);

        if (order.isBuyOrder) {
            // update the royalty table and pay platform fees
            royaltyManager.transferRoyalty(_orderId, receiver, royaltyFee);
            royaltyManager.transferPlatformFee(order.token, _orderId, volume);

            // Update Escrow records for the orders - will revert if the user doesn't have enough assets
            executionManager.executeBuyOrder(_msgSender(), _orderId, remaining, orderAmount, order.asset);
        } else {
            // update the royalty table and pay creator royalties and platform fees
            royaltyManager.transferRoyalty(_msgSender(), order.token, receiver, royaltyFee);
            royaltyManager.transferPlatformFee(_msgSender(), order.token, volume);

            // Execute trade - will revert if buyer doesn't have enough funds
            executionManager.executeSellOrder(_msgSender(), _orderId, remaining, orderAmount, order.token);
        }

        emit OrderFilled(_msgSender(), _orderId, orderAmount, order.asset, order.token, volume);
    }

    function fillOrderBatch(
        uint256[] memory _orderIds,
        uint256 amountToFill,
        uint256 maxSpend
    ) external override {
        require(_orderIds.length > 0, "Invalid order length");

        // Verify orders exist
        require(orderbook.verifyOrdersExist(_orderIds), "Non-existent order");

        // Verify all orders are of the same asset and the same token payment
        require(orderbook.verifyAllOrdersData(_orderIds), "Invalid order data");

        // Get order amounts that are still available
        (uint256[] memory orderAmounts, uint256 assetsFilled) = orderbook.getOrderAmounts(_orderIds, amountToFill, maxSpend);

        // Get Total Payment
        (uint256 volume, uint256[] memory amountPerOrder) = orderbook.getPaymentTotals(_orderIds, orderAmounts);
        
        // get the order data
        LibOrder.Order memory order = orderbook.getOrder(_orderIds[0]);

        // Orderbook -> fill order
        orderbook.fillOrders(_orderIds, orderAmounts);

        if (order.isBuyOrder) {
            // Calculate and deduct royalties from escrow per order
            (address receiver,
            uint256[] memory royaltyFees,
            uint256[] memory platformFees,
            uint256[] memory remaining) = royaltyManager.buyOrderRoyalties(order.asset, amountPerOrder);

            // update the royalty table from each orderId and pay platform fees
            royaltyManager.transferRoyalties(_orderIds, receiver, royaltyFees);
            royaltyManager.transferPlatformFees(order.token, _orderIds, platformFees);

            // Update Escrow records for the orders - will revert if the user doesn't have enough assets
            executionManager.executeBuyOrderBatch(_msgSender(), _orderIds, remaining, orderAmounts, order.asset);
        } else {
            // Calculate and deduct royalties
            (address receiver,
            uint256 royaltyFee,
            uint256[] memory remaining) = royaltyManager.sellOrderRoyalties(order.asset, amountPerOrder);

            // update the royalty table and pay creator royalties and platform fees
            royaltyManager.transferRoyalty(_msgSender(), order.token, receiver, royaltyFee);
            royaltyManager.transferPlatformFee(_msgSender(), order.token, volume);

            // Execute trade - will revert if buyer doesn't have enough funds
            executionManager.executeSellOrderBatch(_msgSender(), _orderIds, remaining, orderAmounts, order.token);
        }

        emit OrdersFilled(_msgSender(), _orderIds, orderAmounts, order.asset, order.token, assetsFilled, volume);
    }

    function cancelOrders(uint256[] memory _orderIds) external override {
        require(_orderIds.length > 0, "empty order length.");
        
        require(orderbook.verifyOrdersExist(_orderIds), "Order does not exist");
        require(orderbook.verifyOrderOwners(_orderIds, _msgSender()), "Order is not owned by claimer");
        require(orderbook.verifyOrdersReady(_orderIds), "Filled/Cancelled Orders cannot be canceled.");

        // Escrows have built in reentrancy guards so doing withdraws before deleting the order is fine.
        executionManager.cancelOrders(_orderIds);

        orderbook.cancelOrders(_orderIds);

        emit OrdersDeleted(_msgSender(), _orderIds);
    }

    function claimOrders(uint256[] memory _orderIds) external override {
        require(_orderIds.length > 0, "empty order length.");
        
        require(orderbook.verifyOrdersExist(_orderIds), "Order does not exist");
        require(orderbook.verifyOrderOwners(_orderIds, _msgSender()), "Order is not owned by claimer");

        orderbook.claimOrders(_orderIds);
        executionManager.claimOrders(_msgSender(), _orderIds);
        
        emit OrdersClaimed(_msgSender(), _orderIds);
    }

    function claimRoyalties() external override {
        royaltyManager.claimRoyalties(_msgSender());
    }

    function addSupportedToken(address _token) external override onlyOwner {
        executionManager.addSupportedToken(_token);
    }

    function getOrder(uint256 id) external view override returns (LibOrder.Order memory) {
        return orderbook.getOrder(id);
    }

    function tokenEscrow() external view override returns(address) {
        return executionManager.tokenEscrow();
    }

    function nftsEscrow() external view override returns(address) {
        return executionManager.nftsEscrow();
    }

    function claimableRoyalties() external view override returns (address[] memory tokens, uint256[] memory amounts) {
        return royaltyManager.claimableRoyalties(_msgSender());
    }

    /**************** Internal Functions ****************/

    uint256[50] private __gap;

}