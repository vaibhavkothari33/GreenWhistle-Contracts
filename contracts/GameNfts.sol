// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract QuestCertificateNFT is ERC721, ERC721URIStorage, ERC721Enumerable, Ownable {
    // Counter for token IDs
    uint256 private _tokenIdCounter;

    // Quest completion data structure
    struct QuestCompletion {
        string questId;
        string questName;
        uint256 completedAt;
        uint256 difficulty;
        uint256 experienceEarned;
    }

    // Mapping from token ID to quest completion data
    mapping(uint256 => QuestCompletion) public questCompletions;
    
    // Mapping to track unique quest completions per player
    mapping(address => mapping(string => bool)) public playerQuestCompletions;

    // Events
    event QuestCertificateMinted(
        address indexed player,
        uint256 indexed tokenId,
        string questId,
        string questName,
        uint256 completedAt,
        uint256 experienceEarned
    );

    constructor() ERC721("GreenWhistle Quest Certificate", "GWQC") Ownable(msg.sender) {}

    /**
     * @dev Mints a new quest completion certificate NFT
     * @param player Address of the player who completed the quest
     * @param questId Unique identifier for the quest
     * @param questName Name of the completed quest
     * @param difficulty Difficulty level of the quest
     * @param experienceEarned Amount of XP earned from the quest
     * @param metadataURI IPFS URI containing the NFT metadata
     */
    function mintQuestCertificate(
        address player,
        string memory questId,
        string memory questName,
        uint256 difficulty,
        uint256 experienceEarned,
        string memory metadataURI
    ) external onlyOwner returns (uint256) {
        require(!playerQuestCompletions[player][questId], "Quest already completed by player");

        _tokenIdCounter++;
        uint256 newTokenId = _tokenIdCounter;

        _safeMint(player, newTokenId);
        _setTokenURI(newTokenId, metadataURI);

        // Store quest completion data
        questCompletions[newTokenId] = QuestCompletion({
            questId: questId,
            questName: questName,
            completedAt: block.timestamp,
            difficulty: difficulty,
            experienceEarned: experienceEarned
        });

        // Mark quest as completed for this player
        playerQuestCompletions[player][questId] = true;

        emit QuestCertificateMinted(
            player,
            newTokenId,
            questId,
            questName,
            block.timestamp,
            experienceEarned
        );

        return newTokenId;
    }

    /**
     * @dev Returns all quest certificates owned by a specific player
     * @param player Address of the player
     */
    function getPlayerCertificates(address player) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(player);
        uint256[] memory tokens = new uint256[](balance);
        
        for(uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(player, i);
        }
        
        return tokens;
    }

    /**
     * @dev Returns quest completion details for a specific token
     * @param tokenId The ID of the certificate NFT
     */
    function getCertificateDetails(uint256 tokenId) external view returns (QuestCompletion memory) {
        require(_exists(tokenId), "Certificate does not exist");
        return questCompletions[tokenId];
    }

    /**
     * @dev Checks if a player has completed a specific quest
     * @param player Address of the player
     * @param questId ID of the quest to check
     */
    function hasCompletedQuest(address player, string memory questId) external view returns (bool) {
        return playerQuestCompletions[player][questId];
    }

    /**
     * @dev Returns the current token ID counter
     */
    function getCurrentTokenId() external view returns (uint256) {
        return _tokenIdCounter;
    }

    // Override required functions
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Checks if a token exists
     * @param tokenId The ID of the token to check
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}