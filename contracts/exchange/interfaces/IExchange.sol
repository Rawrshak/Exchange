// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibOrder.sol";

interface IExchange {
    
    /******** View Functions ********/

    function getOrder(uint256 id) external view returns (LibOrder.Order memory);

    function tokenEscrow() external view returns(address);

    function nftsEscrow() external view returns(address);

    function claimableRoyalties() external view returns (address[] memory tokens, uint256[] memory amounts);
    
    /******** Mutative Functions ********/
    function placeOrder(LibOrder.OrderInput calldata _order) external; 
    
    function fillOrder(
        uint256 _orderId,
        uint256 amountToFill
    ) external;

    function fillOrderBatch(
        uint256[] calldata _orderIds,
        uint256 amountToFill,
        uint256 maxSpend
    ) external;

    function cancelOrders(uint256[] calldata _orderIds) external;

    function claimOrders(uint256[] calldata _orderIds) external;

    function claimRoyalties() external;

    function addSupportedToken(address _token) external;

    /*********************** Events *********************/
    event OrderPlaced(address indexed from, uint256 indexed orderId, LibOrder.OrderInput order);

    event OrdersFilled(
        address indexed from,
        uint256[] orderIds,
        uint256[] amounts,
        LibOrder.AssetData asset,
        address token,
        uint256 totalAssetsAmount,
        uint256 volume);

    event OrderFilled(
        address indexed from,
        uint256 orderId,
        uint256 amount,
        LibOrder.AssetData asset,
        address token,
        uint256 volume);

    event OrdersDeleted(address indexed owner, uint256[] orderIds);
    
    event OrdersClaimed(address indexed owner, uint256[] orderIds);
    
}