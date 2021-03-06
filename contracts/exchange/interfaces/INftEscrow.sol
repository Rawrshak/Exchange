// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibOrder.sol";

interface INftEscrow {
    
    /******** View Functions ********/
    function escrowedAmounts(uint256 _orderId) external view returns(uint256);
    
    function escrowedAsset(uint256 _orderId) external view returns(address contentAddress, uint256 tokenId);

    /******** Mutative Functions ********/
    function deposit(
        uint256 _orderId,
        address _sender,
        uint256 _amount,
        LibOrder.AssetData calldata _assetData
    ) external;

    function depositBatch(
        uint256[] calldata _orderIds,
        address _sender,
        uint256[] calldata _amounts,
        LibOrder.AssetData calldata _assetData
    ) external;

    function withdraw(uint256 orderId, address _receiver, uint256 amount) external;

    function withdrawBatch(uint256[] calldata _orderIds, address _receiver, uint256[] calldata _amounts) external;

}