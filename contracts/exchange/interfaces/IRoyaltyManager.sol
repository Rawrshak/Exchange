// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibOrder.sol";

interface IRoyaltyManager { 
    /******** View Functions ********/

    function claimableRoyalties(address _user) external view returns(address[] memory tokens, uint256[] memory amounts);

    function payableRoyalties(
        LibOrder.AssetData calldata _asset,
        uint256 _total
    ) external view returns(address receiver, uint256 royaltyFee, uint256 remaining);
    
    function buyOrderRoyalties(
        LibOrder.AssetData calldata _asset,
        uint256[] memory amountPerOrder
    ) external view returns(address receiver, uint256[] memory royaltyFees, uint256[] memory platformFees, uint256[] memory remaining);

    function sellOrderRoyalties(
        LibOrder.AssetData calldata _asset,
        uint256[] memory amountPerOrder
    ) external view returns(address receiver, uint256 royaltyTotal, uint256[] memory remaining);

    /******** Mutative Functions ********/
    function claimRoyalties(address _user) external;

    function transferRoyalty(
        address _sender,
        address _token,
        address _receiver,
        uint256 _royaltyFee
    ) external;

    function transferRoyalty(
        uint256[] calldata _orderIds,
        address _receiver,
        uint256[] calldata _royaltyFees
    ) external;

    function transferRoyalty(
        uint256 _orderId,
        address _receiver,
        uint256 _fee
    ) external;

    function transferPlatformFee(address _sender, address _token, uint256 _total) external;

    function transferPlatformFee(address _token, uint256[] calldata _orderIds, uint256[] memory platformFees) external;

    function transferPlatformFee(address _token, uint256 _orderId, uint256 _total) external;
}