// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract GameToken is ERC20, ERC20Burnable, Pausable, Ownable, ERC20Permit {
    // Game specific events
    event ItemListed(address indexed seller, uint256 indexed itemId, uint256 price, string itemName);
    event ItemSold(address indexed seller, address indexed buyer, uint256 indexed itemId, uint256 price);
    event ItemDelisted(address indexed seller, uint256 indexed itemId);
    event RewardEarned(address indexed player, uint256 amount, string reason);
    event TokensStaked(address indexed player, uint256 amount);
    event TokensUnstaked(address indexed player, uint256 amount, uint256 reward);
    event PlayerLevelUp(address indexed player, uint256 newLevel);
    event QuestCompleted(address indexed player, string questId, uint256 reward);

    // Staking related variables
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public stakingStartTime;
    
    // Player stats
    mapping(address => uint256) public playerLevel;
    mapping(address => uint256) public playerExperience;
    
    // Marketplace items
    struct MarketItem {
        uint256 id;
        address seller;
        uint256 price;
        string name;
        bool isActive;
    }
    
    mapping(uint256 => MarketItem) public marketItems;
    uint256 private nextItemId = 1;
    
    // Constants
    uint256 public constant STAKING_PERIOD = 7 days;
    uint256 public constant STAKING_REWARD_RATE = 5; // 5% APR
    uint256 public constant XP_PER_LEVEL = 1000;
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10**18; // 1 million tokens

    constructor() ERC20("GreenWhistle", "GWT") Ownable(msg.sender) ERC20Permit("GreenWhistle") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    // Marketplace Functions
    function listItem(string memory itemName, uint256 price) external whenNotPaused returns (uint256) {
        require(price > 0, "Price must be greater than 0");
        require(bytes(itemName).length > 0, "Item name cannot be empty");
        
        uint256 itemId = nextItemId++;
        marketItems[itemId] = MarketItem({
            id: itemId,
            seller: msg.sender,
            price: price,
            name: itemName,
            isActive: true
        });
        
        emit ItemListed(msg.sender, itemId, price, itemName);
        return itemId;
    }

    function buyItem(uint256 itemId) external whenNotPaused {
        MarketItem storage item = marketItems[itemId];
        require(item.isActive, "Item not available");
        require(msg.sender != item.seller, "Cannot buy your own item");
        require(balanceOf(msg.sender) >= item.price, "Insufficient balance");

        // Transfer tokens
        _transfer(msg.sender, item.seller, item.price);
        
        // Update item status
        item.isActive = false;
        
        emit ItemSold(item.seller, msg.sender, itemId, item.price);
    }

    function delistItem(uint256 itemId) external {
        MarketItem storage item = marketItems[itemId];
        require(item.seller == msg.sender, "Not the seller");
        require(item.isActive, "Item not active");
        
        item.isActive = false;
        emit ItemDelisted(msg.sender, itemId);
    }

    // Staking Functions
    function stake(uint256 amount) external whenNotPaused {
        require(amount > 0, "Cannot stake 0 tokens");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // If already staking, claim rewards first
        if (stakedBalance[msg.sender] > 0) {
            uint256 reward = calculateStakingReward(msg.sender);
            if (reward > 0) {
                _mint(msg.sender, reward);
                emit RewardEarned(msg.sender, reward, "Staking Reward");
            }
        }

        _transfer(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        stakingStartTime[msg.sender] = block.timestamp;
        
        emit TokensStaked(msg.sender, amount);
    }

    function unstake() external whenNotPaused {
        uint256 stakedAmount = stakedBalance[msg.sender];
        require(stakedAmount > 0, "No tokens staked");
        
        uint256 stakingDuration = block.timestamp - stakingStartTime[msg.sender];
        require(stakingDuration >= STAKING_PERIOD, "Staking period not completed");

        uint256 reward = calculateStakingReward(msg.sender);
        uint256 totalAmount = stakedAmount + reward;

        stakedBalance[msg.sender] = 0;
        stakingStartTime[msg.sender] = 0;

        _mint(msg.sender, reward);
        _transfer(address(this), msg.sender, stakedAmount);
        
        emit TokensUnstaked(msg.sender, stakedAmount, reward);
    }

    function calculateStakingReward(address player) public view returns (uint256) {
        if (stakedBalance[player] == 0) return 0;
        
        uint256 stakingDuration = block.timestamp - stakingStartTime[player];
        return (stakedBalance[player] * STAKING_REWARD_RATE * stakingDuration) / (365 days * 100);
    }

    // Game Progress Functions
    function awardExperience(address player, uint256 xpAmount) external onlyOwner {
        require(player != address(0), "Invalid player address");
        require(xpAmount > 0, "XP amount must be greater than 0");
        
        playerExperience[player] += xpAmount;
        
        // Check for level up
        uint256 newLevel = (playerExperience[player] / XP_PER_LEVEL) + 1;
        if (newLevel > playerLevel[player]) {
            playerLevel[player] = newLevel;
            emit PlayerLevelUp(player, newLevel);
        }
    }

    function completeQuest(address player, string memory questId, uint256 reward) external onlyOwner {
        require(player != address(0), "Invalid player address");
        require(bytes(questId).length > 0, "Quest ID cannot be empty");
        
        _mint(player, reward);
        emit QuestCompleted(player, questId, reward);
        emit RewardEarned(player, reward, "Quest Completion");
    }

    function awardGameReward(address player, uint256 amount, string memory reason) external onlyOwner {
        require(player != address(0), "Invalid player address");
        require(amount > 0, "Reward amount must be greater than 0");
        
        _mint(player, amount);
        emit RewardEarned(player, amount, reason);
    }

    // Player stats view functions
    function getPlayerStats(address player) external view returns (uint256 level, uint256 experience) {
        return (playerLevel[player], playerExperience[player]);
    }

    function getStakingInfo(address player) external view returns (uint256 staked, uint256 stakingTime, uint256 pendingReward) {
        return (stakedBalance[player], stakingStartTime[player], calculateStakingReward(player));
    }

    // Admin Functions
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // Emergency function to recover stuck tokens
    function recoverERC20(address tokenAddress, uint256 amount) external onlyOwner {
        require(tokenAddress != address(this), "Cannot recover game tokens");
        IERC20(tokenAddress).transfer(owner(), amount);
    }

    // Override required functions
    function _update(address from, address to, uint256 value) internal virtual override(ERC20) whenNotPaused {
        super._update(from, to, value);
    }
}