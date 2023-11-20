// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {KIPQANFT} from "./KIPQANFT.sol";
import "./ICross.sol";

contract KIPQuery is ICross, CCIPReceiver, Context, Ownable, ReentrancyGuard {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    struct Question {
        // Collection ID
        uint256 id;
        // Question ID
        uint256 questionId;
        // Question Content
        string question;
        // Queryor Address
        address queryor;
        // NFT owner
        address owner;
        // Query timestamp
        uint256 time;
        // Has been mint
        bool isMint;
    }

    uint128 private _questionId = 0;
    uint64 private _dstChainSelectorOfSepholia = 16015286601757825753;
    uint64 private _dstChainSelectorOfMumbai = 12532609583862916517;

    address public protocolAddress;
    address public nftAddress;
    KIPQANFT private NFT;

    // Pay token
    IERC20 private _token;

    // Last message ID of CCIP
    bytes32 public lastestMessageId;

    // Category ID => Category Collections
    // Education:           1
    // Entertainment:       2
    // Sport:               3
    // Marketing:           4
    // Business:            5
    // Developer's Tool:    6
    // Finance:             7
    // Lifestyle:           8
    // Academics:           9
    // Productivity:        10
    // Utility:             11
    mapping(uint8 => uint256[]) private _categoryCollections;

    // Collection ID => Collection
    mapping(uint256 => Collection) private _collectionMap;

    // Collection ID => Collection Holders and holder balance;
    mapping(uint256 => EnumerableMap.AddressToUintMap) private _collectionHolders;

    // Collection ID => Collection Question IDs
    mapping(uint256 => uint256[]) private _collectionQuestionIDs;

    // Question ID => Question
    mapping(uint256 => Question) private _collectionQuestions;

    // User Address => User Balance
    mapping(address => uint256) private _balances;

    // Emit when user query a question
    event Query(uint256 id, uint256 questionId, address queryor);

    // Emit when user mint an answer NFT
    event Mint(uint256 questionId, address to);

    // Emit when answer NFT transfer
    event Transfer(uint256 questionId, address to);

    // Emit when user withdraw the bonus
    event Withdraw(address withdrawer, uint256 amount);

    // Router of Sepholia: 0xD0daae2231E9CB96b94C8512223533293C3693Bf
    // Router of Mumbai: 0x70499c328e1E2a3c41108bd3730F6670a44595D1
    // Chain Selector of Sepholia: 16015286601757825753
    // Chain Selector of Mumbai: 12532609583862916517
    constructor(address payTokenAddress)
        CCIPReceiver(0x70499c328e1E2a3c41108bd3730F6670a44595D1)
        Ownable(_msgSender())
    {
        _token = IERC20(payTokenAddress);
        protocolAddress = _msgSender();
    }

    /**
     * Triggerd by CCIP router when someone send message/token or both message and token to this contracct
     * @dev message {Client.Any2EVMMessage} Cross blockchain message
     */
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        lastestMessageId = message.messageId;
        Message memory _message = abi.decode(message.data, (Message));

        if (_message.messageType == 1) {
            // Create Collection
            Collection memory collection = abi.decode(_message.data, (Collection));

            _updateCollections(
                collection.id,
                collection.creator,
                collection.supply,
                collection.price,
                collection.royalties,
                collection.category,
                collection.queryCount,
                collection.mintCount
            );
            _updateHolders(collection.id, address(0), collection.creator, collection.supply);
        } else if (_message.messageType == 2) {
            // Transfer
            TransferInfo memory transferInfo = abi.decode(_message.data, (TransferInfo));

            _updateHolders(transferInfo.id, transferInfo.from, transferInfo.to, transferInfo.value);
        }

        emit MessageReceived(message.messageId);
    }

    /**
     * Update holders balance when mint/transfer
     */
    function _updateHolders(uint256 collectionId, address from, address to, uint256 value) internal {
        EnumerableMap.AddressToUintMap storage holders = _collectionHolders[collectionId];
        (bool fromIsExist, uint256 fromBeforeValue) = holders.tryGet(from);
        (bool toIsExist, uint256 toBeforeValue) = holders.tryGet(to);

        if (to == address(0)) {
            // Burn, from address must exist
            holders.set(from, fromBeforeValue - value);
            _collectionMap[collectionId].supply -= value;
        } else {
            // Normal Transfer, from address maybe not exist
            if (fromIsExist) {
                holders.set(from, fromBeforeValue - value);
            }
            if (toIsExist) {
                holders.set(to, toBeforeValue + value);
            } else {
                holders.set(to, value);
            }
        }
    }

    /**
     * Update collection when created
     */
    function _updateCollections(
        uint256 id,
        address creator,
        uint256 supply,
        uint256 price,
        uint256 royalties,
        uint8 categoryId,
        uint32 queryCount,
        uint32 mintCount
    ) internal {
        Collection memory collection = Collection({
            id: id,
            creator: creator,
            supply: supply,
            price: price,
            royalties: royalties,
            category: categoryId,
            queryCount: queryCount,
            mintCount: mintCount
        });
        _collectionMap[id] = collection;
        _categoryCollections[categoryId].push(id);
    }

    /**
     * Update when query collection
     */
    function _updataCollectionQueryCount(uint256 collectionId) internal {
        _collectionMap[collectionId].queryCount += 1;
    }

    /**
     * Update when mint Q&A
     */
    function _updateCollectionMintCount(uint256 collectionId) internal {
        _collectionMap[collectionId].mintCount += 1;
    }

    /**
     * User query question for some collection
     */
    function query(uint256 id, string calldata question) external {
        Collection memory collection = _collectionMap[id];
        require(collection.id == id, "KIP Error: Collection doesn't exist");

        address queryor = _msgSender();
        uint256 questionId = _questionId;
        uint256 queryPrice = collection.price;

        {
            address contractor = address(this);
            uint256 allowance = _token.allowance(queryor, contractor);

            require(allowance >= queryPrice, "KIP Error: Insufficient allowance");

            bool transferResult1 = _token.transferFrom(queryor, contractor, queryPrice * 50 / 100);
            bool transferResult2 = _token.transferFrom(queryor, protocolAddress, queryPrice * 50 / 100);
            require(transferResult1, "KIP Error: Transfer token failed");
            require(transferResult2, "KIP Error: Transfer token failed");
        }

        {
            // Share bonus
            EnumerableMap.AddressToUintMap storage holders = _collectionHolders[id];
            uint256 holdersCount = holders.length();
            uint256 protocolEarnings = queryPrice * 50 / 100;
            uint256 creatorEarnings = queryPrice * collection.royalties / 100;
            uint256 holdersEarnings = queryPrice - protocolEarnings - creatorEarnings;
            uint256 unitEarnings = holdersEarnings / collection.supply;
            _balances[collection.creator] += creatorEarnings;
            for (uint256 i = 0; i < holdersCount; i++) {
                (address holder, uint256 value) = holders.at(i);
                _balances[holder] += unitEarnings * value;
            }
        }

        {
            Question memory _question = Question({
                id: id,
                questionId: questionId,
                question: question,
                queryor: queryor,
                owner: queryor,
                time: block.timestamp,
                isMint: false
            });
            _collectionQuestionIDs[id].push(questionId);
            _collectionQuestions[questionId] = _question;

            _updataCollectionQueryCount(id);
            emit Query(id, questionId, queryor);
        }

        unchecked {
            _questionId++;
        }
    }

    /**
     * Get special category collections
     */
    function getCategoryCollections(uint8 categoryId) external view returns (Collection[] memory) {
        uint256[] memory categoryCollections = _categoryCollections[categoryId];
        Collection[] memory collections = new Collection[](categoryCollections.length);
        for (uint256 i = 0; i < categoryCollections.length; i++) {
            collections[i] = _collectionMap[categoryCollections[i]];
        }
        return collections;
    }

    /**
     * Get special collection
     */
    function getCollection(uint256 collectionId) external view returns (Collection memory) {
        return _collectionMap[collectionId];
    }

    /**
     * Get collection questions
     */
    function getQuestions(uint256 id) external view returns (Question[] memory) {
        uint256[] memory questionIDs = _collectionQuestionIDs[id];
        Question[] memory questions = new Question[](questionIDs.length);
        for (uint256 i = 0; i < questionIDs.length; i++) {
            questions[i] = _collectionQuestions[questionIDs[i]];
        }
        return questions;
    }

    /**
     * Get question
     */
    function getQuestion(uint256 id) external view returns (Question memory) {
        return _collectionQuestions[id];
    }

    /**
     * Withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        address invoker = _msgSender();
        require(_balances[invoker] != 0, "KIP Error: ZERO");

        uint256 balance = _token.balanceOf(address(this));
        require(_balances[invoker] >= amount && balance >= amount, "KIP Error: Insufficient balance");

        bool transferResult = _token.transfer(invoker, amount);
        require(transferResult, "KIP Error: Transfer failed");

        _balances[invoker] -= amount;
        emit Withdraw(invoker, amount);
    }

    /**
     * Mint NFT
     */
    function mint(uint256 questionId, address to, string calldata uri) external {
        // Require the query not be minted
        require(!_collectionQuestions[questionId].isMint, "KIP Error: illegal call");
        _collectionQuestions[questionId].owner = to;
        _collectionQuestions[questionId].isMint = true;
        NFT.mint(questionId, to, uri);
        emit Mint(questionId, to);
    }

    /**
     * Update NFT owner
     */
    function update(uint256 questionId, address newOwner) external {
        require(_msgSender() == nftAddress, "KIP Error: Illegal call");
        _collectionQuestions[questionId].owner = newOwner;
        emit Transfer(questionId, newOwner);
    }

    /**
     * Get user balance
     */
    function getBalance(address user) external view returns (uint256) {
        return _balances[user];
    }

    /**
     * Set new protocol address
     */
    function setProtocolAddress(address protocolAddress_) external onlyOwner {
        protocolAddress = protocolAddress_;
    }

    /**
     * Set new NFT address;
     */
    function setNFTAddress(address nftAddress_) external onlyOwner {
        nftAddress = nftAddress_;
        NFT = KIPQANFT(nftAddress_);
    }
}
