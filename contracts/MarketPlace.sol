// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract MarketplaceV2 is ReentrancyGuard, Pausable, Ownable {
    // Structs
    struct Item {
        uint256 itemId;
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool isActive;
        uint256 listedAt;
        ItemType itemType;
        uint256 quantity;  // For ERC20 tokens
    }

    struct MarketMetrics {
        uint256 totalVolume;
        uint256 totalTrades;
        uint256 lastPrice;
        uint256 highestPrice;
        uint256 lowestPrice;
        uint256 supply;
        uint256 demand;  // Number of unique buyers in last 24h
    }

    // Enums
    enum ItemType { ERC721, ERC20, INGAME }

    // State variables
    uint256 private _itemIds;
    uint256 private constant PLATFORM_FEE = 250; // 2.5% (based on 10000)
    address public treasury;
    IERC20 public gameToken;

    // Mappings
    mapping(uint256 => Item) public items;
    mapping(address => mapping(uint256 => MarketMetrics)) public itemMetrics;
    mapping(address => uint256) public userTrades;
    mapping(address => uint256[]) public userListings;
    mapping(address => uint256[]) public userPurchases;
    mapping(address => mapping(uint256 => uint256)) public lastBuyTime; // user => itemId => timestamp
    
    // Events
    event ItemListed(
        uint256 indexed itemId,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        ItemType itemType,
        uint256 quantity
    );
    
    event ItemSold(
        uint256 indexed itemId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );
    
    event ItemPriceChanged(
        uint256 indexed itemId,
        uint256 oldPrice,
        uint256 newPrice
    );
    
    event ItemDelisted(uint256 indexed itemId);
    
    event MarketMetricsUpdated(
        address indexed itemContract,
        uint256 indexed tokenId,
        uint256 price,
        uint256 supply,
        uint256 demand
    );

    constructor(address _gameToken, address _treasury) Ownable(msg.sender) {
        require(_gameToken != address(0), "Invalid game token address");
        require(_treasury != address(0), "Invalid treasury address");
        gameToken = IERC20(_gameToken);
        treasury = _treasury;
    }

    // Listing Functions
    function listItem(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        ItemType itemType,
        uint256 quantity
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(price > 0, "Price must be greater than 0");
        require(quantity > 0, "Quantity must be greater than 0");
        require(nftContract != address(0), "Invalid NFT contract address");

        _itemIds++;
        uint256 itemId = _itemIds;

        if (itemType == ItemType.ERC721) {
            IERC721 nftInterface = IERC721(nftContract);
            require(nftInterface.ownerOf(tokenId) == msg.sender, "Not owner of NFT");
            require(nftInterface.isApprovedForAll(msg.sender, address(this)) || 
                   nftInterface.getApproved(tokenId) == address(this), 
                   "Marketplace not approved");
            nftInterface.transferFrom(msg.sender, address(this), tokenId);
            quantity = 1;  // ERC721 always has quantity 1
        } else if (itemType == ItemType.ERC20) {
            IERC20 tokenInterface = IERC20(nftContract);
            require(tokenInterface.balanceOf(msg.sender) >= quantity, "Insufficient token balance");
            require(tokenInterface.allowance(msg.sender, address(this)) >= quantity, "Insufficient allowance");
            require(tokenInterface.transferFrom(msg.sender, address(this), quantity), "Token transfer failed");
        } else if (itemType == ItemType.INGAME) {
            // For in-game items, no actual transfer happens at listing time
            // This would be validated through a backend system
        }

        items[itemId] = Item({
            itemId: itemId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            isActive: true,
            listedAt: block.timestamp,
            itemType: itemType,
            quantity: quantity
        });

        userListings[msg.sender].push(itemId);
        _updateMetrics(nftContract, tokenId, price, true);

        emit ItemListed(itemId, msg.sender, nftContract, tokenId, price, itemType, quantity);
        return itemId;
    }

    // Buying Functions
    function buyItem(uint256 itemId, uint256 quantity) external whenNotPaused nonReentrant {
        Item storage item = items[itemId];
        require(item.isActive, "Item not active");
        require(msg.sender != item.seller, "Cannot buy your own item");
        require(quantity > 0 && quantity <= item.quantity, "Invalid quantity");

        uint256 totalPrice = item.price * quantity;
        uint256 platformFee = (totalPrice * PLATFORM_FEE) / 10000;
        uint256 sellerAmount = totalPrice - platformFee;

        // Transfer payment
        require(gameToken.transferFrom(msg.sender, treasury, platformFee), "Platform fee transfer failed");
        require(gameToken.transferFrom(msg.sender, item.seller, sellerAmount), "Payment transfer failed");

        // Transfer item
        if (item.itemType == ItemType.ERC721) {
            require(quantity == 1, "ERC721 quantity must be 1");
            IERC721(item.nftContract).safeTransferFrom(address(this), msg.sender, item.tokenId);
            item.isActive = false;
        } else if (item.itemType == ItemType.ERC20) {
            require(IERC20(item.nftContract).transfer(msg.sender, quantity), "Token transfer failed");
            item.quantity -= quantity;
            if (item.quantity == 0) {
                item.isActive = false;
            }
        } else if (item.itemType == ItemType.INGAME) {
            // For in-game items, actual transfer happens off-chain
            // Just update the quantity and status
            item.quantity -= quantity;
            if (item.quantity == 0) {
                item.isActive = false;
            }
        }

        // Update metrics
        userTrades[msg.sender]++;
        userTrades[item.seller]++;
        userPurchases[msg.sender].push(itemId);
        lastBuyTime[msg.sender][itemId] = block.timestamp;
        _updateMetrics(item.nftContract, item.tokenId, item.price, false);

        emit ItemSold(itemId, item.seller, msg.sender, totalPrice);
    }

    // Market Management Functions
    function updateItemPrice(uint256 itemId, uint256 newPrice) external {
        Item storage item = items[itemId];
        require(msg.sender == item.seller, "Not the seller");
        require(item.isActive, "Item not active");
        require(newPrice > 0, "Invalid price");

        uint256 oldPrice = item.price;
        item.price = newPrice;

        emit ItemPriceChanged(itemId, oldPrice, newPrice);
        _updateMetrics(item.nftContract, item.tokenId, newPrice, false);
    }

    function delistItem(uint256 itemId) external nonReentrant {
        Item storage item = items[itemId];
        require(msg.sender == item.seller || msg.sender == owner(), "Not authorized");
        require(item.isActive, "Item not active");

        if (item.itemType == ItemType.ERC721) {
            IERC721(item.nftContract).safeTransferFrom(address(this), item.seller, item.tokenId);
        } else if (item.itemType == ItemType.ERC20) {
            require(IERC20(item.nftContract).transfer(item.seller, item.quantity), "Token transfer failed");
        }
        // No transfer needed for INGAME items

        item.isActive = false;
        emit ItemDelisted(itemId);
    }

    // View Functions
    function getItemsByUser(address user) external view returns (uint256[] memory) {
        return userListings[user];
    }

    function getPurchasesByUser(address user) external view returns (uint256[] memory) {
        return userPurchases[user];
    }

    function getActiveItems() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= _itemIds; i++) {
            if (items[i].isActive) {
                count++;
            }
        }

        uint256[] memory activeItems = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= _itemIds; i++) {
            if (items[i].isActive) {
                activeItems[index] = i;
                index++;
            }
        }

        return activeItems;
    }

    function getItemDetails(uint256 itemId) external view returns (Item memory) {
        require(itemId > 0 && itemId <= _itemIds, "Invalid item ID");
        return items[itemId];
    }

    function getMarketMetrics(address nftContract, uint256 tokenId) 
        external 
        view 
        returns (MarketMetrics memory) 
    {
        return itemMetrics[nftContract][tokenId];
    }

    // Internal Functions
    function _updateMetrics(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool isNewListing
    ) internal {
        MarketMetrics storage metrics = itemMetrics[nftContract][tokenId];
        
        if (isNewListing) {
            metrics.supply++;
        } else {
            metrics.totalTrades++;
            metrics.totalVolume += price;
            metrics.lastPrice = price;
            
            if (metrics.highestPrice == 0 || price > metrics.highestPrice) {
                metrics.highestPrice = price;
            }
            if (metrics.lowestPrice == 0 || price < metrics.lowestPrice) {
                metrics.lowestPrice = price;
            }

            // Update demand (count of unique buyers in last 24h)
            uint256 uniqueBuyers = 0;
            address[] memory processedAddresses = new address[](_itemIds);
            uint256 processedCount = 0;
            
            for (uint256 i = 0; i < processedCount; i++) {
                if (lastBuyTime[processedAddresses[i]][tokenId] > block.timestamp - 1 days) {
                    uniqueBuyers++;
                }
            }
            
            metrics.demand = uniqueBuyers;
        }

        emit MarketMetricsUpdated(
            nftContract,
            tokenId,
            price,
            metrics.supply,
            metrics.demand
        );
    }

    // Admin Functions
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury address");
        treasury = newTreasury;
    }

    function setGameToken(address newGameToken) external onlyOwner {
        require(newGameToken != address(0), "Invalid game token address");
        gameToken = IERC20(newGameToken);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Emergency Functions
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
    }

    function emergencyWithdrawNFT(
        address nftContract,
        uint256 tokenId
    ) external onlyOwner {
        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
    }
}