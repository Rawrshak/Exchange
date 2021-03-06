// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@rawrshak/rawr-content/contracts/escrow/EscrowBase.sol";
import "../libraries/LibOrder.sol";
import "./interfaces/INftEscrow.sol";

contract NftEscrow is INftEscrow, EscrowBase, ERC1155HolderUpgradeable, ERC721HolderUpgradeable {
    /******************** Constants ********************/
    /*
     * INftEscrow == 0x06265fe7
     * IERC721ReceiverUpgradeable == 0x150b7a02
     * IERC1155ReceiverUpgradeable == 0x4e2312e0
     * IEscrowBase: 0x7965db0b
     * IAccessControlUpgradeable: 0x7965db0b
     */
    
    /***************** Stored Variables *****************/
    mapping(uint256 => LibOrder.AssetData) public override escrowedAsset;
    mapping(uint256 => uint256) public override escrowedAmounts;

    /******************** Public API ********************/
    function initialize() public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __ERC1155Holder_init_unchained();
        __ERC721Holder_init_unchained();
        __EscrowBase_init_unchained();
        __NftEscrow_init_unchained();
    }

    function __NftEscrow_init_unchained() internal onlyInitializing {
        _registerInterface(type(INftEscrow).interfaceId);
        _registerInterface(type(IERC721ReceiverUpgradeable).interfaceId);
        _registerInterface(type(IERC1155ReceiverUpgradeable).interfaceId);
    }

    function deposit(
        uint256 _orderId,
        address _sender,
        uint256 _amount,
        LibOrder.AssetData calldata _assetData
    ) external override onlyRole(MANAGER_ROLE) {
        // No need to do checks. The exchange contracts will do the checks.
        escrowedAsset[_orderId] = _assetData;
        escrowedAmounts[_orderId] = escrowedAmounts[_orderId] + _amount;

        _transfer(_orderId, _sender, address(this), _amount);
    }

    function depositBatch(
        uint256[] calldata _orderIds,
        address _sender,
        uint256[] calldata _amounts,
        LibOrder.AssetData calldata _assetData
    ) external override onlyRole(MANAGER_ROLE) {
        uint256 total;
        for (uint256 i = 0; i < _orderIds.length; i++) {
            if (_amounts[i] > 0) {
                // Update mappings for each order
                escrowedAsset[_orderIds[i]] = _assetData;
                escrowedAmounts[_orderIds[i]] = escrowedAmounts[_orderIds[i]] + _amounts[i];
                // tally up total amount of assets
                total += _amounts[i];
            }
        }
        _transfer(_orderIds[0], _sender, address(this), total);
    }

    // withdraw() and withdrawBatch() is called when a user buys an escrowed asset, a seller cancels an order 
    // and withdraw's their escrowed asset, or a buyer's order is filled and claims the escrowed asset.
    function withdraw(
        uint256 _orderId,
        address _receiver,
        uint256 _amount
    ) external override onlyRole(MANAGER_ROLE) {
        escrowedAmounts[_orderId] = escrowedAmounts[_orderId] - _amount;

        _transfer(_orderId, address(this), _receiver, _amount);

        // Delete if order is filled; Gas Refund
        // We don't need to store how much was escrowed because we keep track of the order data in 
        // the orderbook.
        if (escrowedAmounts[_orderId] == 0) {
            delete escrowedAsset[_orderId];
        }
    }

    function withdrawBatch(
        uint256[] calldata _orderIds,
        address _receiver,
        uint256[] calldata _amounts
    ) external override onlyRole(MANAGER_ROLE) {
        uint256 total;
        address contractAddress;
        uint256 tokenId;
        for (uint256 i = 0; i < _orderIds.length; ++i) {
            if (_amounts[i] > 0) {
                // update mapping for each order
                escrowedAmounts[_orderIds[i]] = escrowedAmounts[_orderIds[i]] - _amounts[i];
                // tally up the total amount of assets
                total += _amounts[i];
                // grab contract address and tokenId for transfer
                if (contractAddress == address(0)) {
                    contractAddress = escrowedAsset[_orderIds[i]].contentAddress;
                    tokenId = escrowedAsset[_orderIds[i]].tokenId;
                }
                // Delete if order is filled; Gas Refund
                // We don't need to store how much was escrowed because we keep track of the order data in 
                // the orderbook.
                if (escrowedAmounts[_orderIds[i]] == 0) {
                    delete escrowedAsset[_orderIds[i]];
                }
            }
        }
        if (contractAddress != address(0)) {
            IERC1155Upgradeable(contractAddress)
                .safeTransferFrom(address(this), _receiver, tokenId, total, "");
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(EscrowBase, ERC1155ReceiverUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**************** Internal Functions ****************/
    function _transfer(uint256 _orderId, address _sender, address _receiver, uint256 amount) internal {
        if (amount > 0) {
            IERC1155Upgradeable(escrowedAsset[_orderId].contentAddress)
                .safeTransferFrom(_sender, _receiver, escrowedAsset[_orderId].tokenId, amount, "");
        }
    }

    uint256[50] private __gap;
}