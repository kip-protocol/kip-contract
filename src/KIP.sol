// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import "./ICross.sol";

contract KIP is ICross, ERC1155, Ownable {
    address private _receiver;
    uint256 private _id = 0;
    uint64 private _dstChainSelectorOfSepholia = 16015286601757825753;
    uint64 private _dstChainSelectorOfMumbai = 12532609583862916517;

    IRouterClient private _routerClient;

    // Collection ID => URI
    mapping(uint256 => string) private _collectionURI;

    // Emit when user create a collection
    event CreateCollection(
        uint256 id, address creator, uint256 supply, uint256 price, uint256 royalties, uint8 category
    );

    // Router of Sepholia: 0xD0daae2231E9CB96b94C8512223533293C3693Bf
    // Router of Mumbai: 0x70499c328e1E2a3c41108bd3730F6670a44595D1
    // Chain Selector of Sepholia: 16015286601757825753
    // Chain Selector of Mumbai: 12532609583862916517
    constructor(address receiver) ERC1155("") Ownable(_msgSender()) {
        _receiver = receiver;
        _routerClient = IRouterClient(0xD0daae2231E9CB96b94C8512223533293C3693Bf);
    }

    /**
     * Create a collection and send message to polygon
     */
    function createCollection(uint256 supply, uint256 price, uint256 royalties, uint8 category, string calldata URI)
        external
        payable
    {
        address creator = _msgSender();
        Collection memory collection = Collection({
            id: _id,
            creator: creator,
            supply: supply,
            price: price,
            royalties: royalties,
            category: category,
            queryCount: 0,
            mintCount: 0
        });

        _collectionURI[_id] = URI;
        _mint(creator, _id, supply, "");

        Message memory data = Message({messageType: 1, data: abi.encode(collection)});

        // Send message to polygon contract by CCIP
        bytes32 messageId = _sendMessage(data);

        // Emit Event
        emit CreateCollection(_id, creator, supply, price, royalties, category);
        emit MessageSent(messageId);

        unchecked {
            _id++;
        }
    }

    function _sendMessage(Message memory message) internal returns (bytes32) {
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: abi.encode(message),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 700_000, strict: false})),
            feeToken: address(0)
        });

        uint256 fees = _routerClient.getFee(_dstChainSelectorOfMumbai, evm2AnyMessage);
        require(fees <= msg.value, "KIP Error: Insufficient value");
        return _routerClient.ccipSend{value: fees}(_dstChainSelectorOfMumbai, evm2AnyMessage);
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) public override {
        // Transfer token
        super.safeTransferFrom(from, to, id, value, data);

        TransferInfo memory transferInfo = TransferInfo({from: from, to: to, id: id, value: value, data: data});

        Message memory _data = Message({messageType: 2, data: abi.encode(transferInfo)});

        bytes32 messageId = _sendMessage(_data);

        // Emit event
        emit MessageSent(messageId);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public pure override {
        revert("Not support");
    }

    /**
     * Get collection URI
     */
    function uri(uint256 id) public view override returns (string memory) {
        return _collectionURI[id];
    }

    /**
     * Set new receiver
     */
    function setReceiver(address receiver) external onlyOwner {
        _receiver = receiver;
    }
}
