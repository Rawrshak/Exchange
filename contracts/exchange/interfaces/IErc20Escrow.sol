// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/LibOrder.sol";

interface IErc20Escrow {

    /******** View Functions ********/
    function escrowedTokensByOrder(uint256 _orderId) external view returns(uint256);
    
    function claimableTokensByOwner(address _owner) external view returns(address[] memory tokens, uint256[] memory amounts); 

    function isTokenSupported(address _token) external view returns(bool);

    /******** Mutative Functions ********/
    function addSupportedTokens(address _token) external;

    function deposit(address _token, uint256 _orderId, address _sender, uint256 _amount) external;

    function depositBatch(address _token, uint256[] calldata _orderIds, address _sender, uint256[] calldata _amounts) external;

    function withdraw(uint256 _orderId, address _user, uint256 _amount) external;

    function withdrawBatch(uint256[] calldata _orderIds, address _receiver, uint256[] calldata _amounts) external;

    function transferRoyalty(address _token, address _sender, address _owner, uint256 _amount) external;

    function transferRoyalties(
        uint256[] calldata _orderIds,
        address _owner,
        uint256[] calldata _amounts
    ) external;
    
    function transferRoyalty(uint256 _orderId, address _owner, uint256 _amount) external;
    
    function transferPlatformFee(address _token, address _sender, address _feesEscrow, uint256 _amount) external;

    function transferPlatformFees(
        uint256[] calldata _orderIds, 
        address _feesEscrow, 
        uint256[] calldata _platformFees, 
        uint256 totalFee
    ) external;

    function transferPlatformFee(uint256 _orderId, address _feesEscrow, uint256 _amount) external;

    function claimRoyalties(address _owner) external;

    /******** Events ********/
    event ClaimedRoyalties(address indexed owner, address[] tokens, uint256[] amounts);
    
    event AddedTokenSupport(address indexed token);
}