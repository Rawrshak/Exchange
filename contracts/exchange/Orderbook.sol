// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ManagerBase.sol";
import "../libraries/LibOrder.sol";
import "./interfaces/IOrderbook.sol";
import "@rawrshak/rawr-content/contracts/utils/LibContractHash.sol";

contract Orderbook is IOrderbook, ManagerBase {
    /******************** Interfaces ********************/
    /*
     * IOrderbook == 0x0950d870
     */
    
    /***************** Stored Variables *****************/
    mapping(uint256 => LibOrder.Order) orders;
    uint256 public override ordersLength;

    /******************** Public API ********************/
    function initialize(address _resolver) public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ManagerBase_init_unchained(_resolver);
        __Orderbook_init_unchained();
    }

    function __Orderbook_init_unchained() internal onlyInitializing {
        _registerInterface(type(IOrderbook).interfaceId);
        ordersLength = 0;
    }

    /**************** External Functions ****************/
    function placeOrder(LibOrder.OrderInput calldata _order) external override onlyOwner returns(uint256 id){
        id = ordersLength++;
        orders[id].asset = _order.asset;
        orders[id].owner = _order.owner;
        orders[id].token = _order.token;
        orders[id].price = _order.price;
        orders[id].amountOrdered = _order.amount;
        orders[id].isBuyOrder = _order.isBuyOrder;
        orders[id].state = LibOrder.OrderState.READY;

        // Note: Order.amountFilled is 0 by default
    }

    function fillOrder(uint256 _orderId, uint256 orderAmount) public override onlyOwner {
        // This will revert if amount is greater than the order amount. This will automatically revert
        orders[_orderId].amountFilled += orderAmount;

        if (orders[_orderId].amountFilled != orders[_orderId].amountOrdered) {
            orders[_orderId].state = LibOrder.OrderState.PARTIALLY_FILLED;
        } else {
            orders[_orderId].state = LibOrder.OrderState.FILLED;
        }
    }

    function fillOrders(uint256[] calldata _orderIds, uint256[] calldata _amounts) external override onlyOwner {
        // The Exchange contract should have already checked the matching lengths of the parameters.
        // the caller will already fill in the orders up to the amount. 
        for (uint256 i = 0; i < _orderIds.length; ++i) {
            // skip zero amounts
            if (_amounts[i] > 0) {
                fillOrder(_orderIds[i], _amounts[i]);
            }
        }
    }

    function cancelOrders(uint256[] calldata _orderIds) external override onlyOwner {
        for (uint256 i = 0; i < _orderIds.length; ++i) {
            // Note: verifyOrdersReady() already checks that the order state is either READY or PARTIALLY_FILLED
            orders[_orderIds[i]].state = LibOrder.OrderState.CANCELLED;
        }
    }
    
    function claimOrders(uint256[] calldata _orderIds) external override onlyOwner {
        for (uint256 i = 0; i < _orderIds.length; ++i) {
            // If the state is Partially Filled, we don't set the order state as claimed. Claimed state 
            // only occurs for when the order is completely filled and the order owner claims.
            if (orders[_orderIds[i]].state == LibOrder.OrderState.FILLED) {
                orders[_orderIds[i]].state = LibOrder.OrderState.CLAIMED;
            }
        }
    }

    function verifyOrdersExist(
        uint256[] calldata _orderIds
    ) external view override onlyOwner returns (bool) {
        for (uint256 i = 0; i < _orderIds.length; ++i) {
            if (!exists(_orderIds[i]) ) {
                return false;
            }
        }
        return true;
    }

    function verifyAllOrdersData(
        uint256[] calldata _orderIds
    ) external view override onlyOwner returns (bool) {
        LibOrder.Order memory firstOrder = orders[_orderIds[0]];
        for (uint256 i = 1; i < _orderIds.length; ++i) {
            if (orders[_orderIds[i]].asset.contentAddress != firstOrder.asset.contentAddress || 
                orders[_orderIds[i]].asset.tokenId != firstOrder.asset.tokenId ||
                orders[_orderIds[i]].token != firstOrder.token ||
                orders[_orderIds[i]].isBuyOrder != firstOrder.isBuyOrder) {
                return false;
            }
        }
        return true;
    }

    function verifyOrderOwners(
        uint256[] calldata _orderIds,
        address _owner
    ) external view override onlyOwner returns (bool) {
        for (uint256 i = 0; i < _orderIds.length; ++i) {
            if (orders[_orderIds[i]].owner != _owner) {
                return false;
            }
        }
        return true;
    }

    function verifyOrdersReady(uint256[] calldata _orderIds) external view override returns(bool){
        for (uint256 i = 0; i < _orderIds.length; ++i) {
            if (orders[_orderIds[i]].state != LibOrder.OrderState.READY && 
                orders[_orderIds[i]].state != LibOrder.OrderState.PARTIALLY_FILLED) {
                return false;
            }
        }
        return true;
    }

    function getOrderAmounts(
        uint256[] calldata _orderIds,
        uint256 amountToFill,
        uint256 maxSpend
    ) external view override returns(uint256[] memory orderAmounts, uint256 amountFilled) {
        // Get Available Orders
        orderAmounts = new uint256[](_orderIds.length); // default already at 0
        for (uint256 i = 0; i < _orderIds.length; ++i) {
            if (orders[_orderIds[i]].state == LibOrder.OrderState.READY) {
                // If state is ready, we set the order amount correctly
                orderAmounts[i] = orders[_orderIds[i]].amountOrdered;
            } else if (orders[_orderIds[i]].state == LibOrder.OrderState.PARTIALLY_FILLED) {
                orderAmounts[i] = orders[_orderIds[i]].amountOrdered - orders[_orderIds[i]].amountFilled;
            }
        }

        // get amounts ordered based on AmountToFill and Max Spend
        amountFilled = 0;
        uint256 amountSpentOnOrder = 0;
        for (uint256 i = 0; i < orderAmounts.length; ++i) {
            if (orderAmounts[i] > 0) {
                amountSpentOnOrder = orders[_orderIds[i]].price * orderAmounts[i];
                
                // Check if the transaction is still under the Max Spend
                if (maxSpend >= amountSpentOnOrder) {
                    maxSpend -= amountSpentOnOrder;
                } else if (maxSpend == 0) {
                    orderAmounts[i] = 0;
                    continue;
                } else if (maxSpend < amountSpentOnOrder) {
                    orderAmounts[i] = maxSpend / orders[_orderIds[i]].price;
                    maxSpend = 0;
                }

                if (orderAmounts[i] <= amountToFill) {
                    // order amount exists but is less than amount remaining to fill
                    amountToFill -= orderAmounts[i];
                    amountFilled += orderAmounts[i];
                } else if (amountToFill > 0) {
                    // order amount exists but is greater than amount remaining to fill
                    orderAmounts[i] = amountToFill;
                    amountFilled += amountToFill; // remainder
                    amountToFill = 0;
                } else {
                    // no more orders to sell
                    orderAmounts[i] = 0;
                }
            }
        }
    }

    function getPaymentTotals(
        uint256[] calldata _orderIds,
        uint256[] calldata _amounts
    ) external view override onlyOwner returns(uint256 volume, uint256[] memory amountPerOrder) {
        // The Exchange contract should have already checked the matching lengths of the parameters.
        amountPerOrder = new uint256[](_amounts.length);
        volume = 0;
        for (uint256 i = 0; i < _orderIds.length; ++i) {
            // Only fill orders that have a non-zero amount
            if (_amounts[i] > 0) {
                amountPerOrder[i] = orders[_orderIds[i]].price * _amounts[i];
                volume = volume + amountPerOrder[i];
            }
        }
    } 

    function getOrder(uint256 _orderId) external view override returns(LibOrder.Order memory) {
        return orders[_orderId];
    }

    function exists(uint256 _orderId) public view override returns(bool){
        return orders[_orderId].owner != address(0);
    }
    
    uint256[50] private __gap;
}