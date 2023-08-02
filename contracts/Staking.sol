// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import "@openzeppelin/contracts/utils/Counters.sol";
import "@zetachain/protocol-contracts/contracts/evm/interfaces/ZetaInterfaces.sol";
import "@zetachain/protocol-contracts/contracts/evm/tools/ZetaInteractor.sol";

contract StakeFarmer is ZetaInteractor, ZetaReceiver{
    using Counters for Counters.Counter;
    Counters.Counter public totalStakedIn;
    uint256 public curChainId;

    IERC20 internal immutable _zetaToken;
    IERC20 internal immutable _budsToken;

    bytes32 public constant CROSS_CHAIN_APR_TRANSFER = keccak256("CROSS_CHAIN_APR_TRANSFER");
    bytes32 public constant CROSS_CHAIN_APR_REQUEST = keccak256("CROSS_CHAIN_APR_REQUEST");

    ZetaTokenConsumer private immutable _zetaConsumer;

    struct farmerStake {
        uint256 tokenId;
        address owner;
        uint256 timeStamp;
    }
    struct budsStake {
        address owner;
        uint256 amount;
        uint256 timeStamp;
    }

    mapping (address => farmerStake) farmerStakeRecord; //address to token id
    mapping (address => budsStake) budsStakeRecord;
    mapping (uint256 => uint256) aprOnChain;    

    event NFTStaked(address owner, uint256 tokenId, uint256 timeStamp);
    event NFTUnstaked(address owner, uint256 tokenId);
    event BudsStaked(address owner, uint256 amount, uint256 timeStamp);
    event BudsUnstaked(address owner, uint256 amount);

    constructor(address _budsToken_, address _zetaToken_, address _zetaConsumer_, address _connectorAddress, uint256 _curChainId) ZetaInteractor(_connectorAddress){
        _budsToken = IERC20(_budsToken_);
        _zetaToken = IERC20(_zetaToken_);
        _zetaConsumer = ZetaTokenConsumer(_zetaConsumer_);
        curChainId = _curChainId;
    }

    function getVarAPR() public returns(uint256){

    }

    function stakeNFT(uint256 tokenId) external {
        require(!_isNFTEarning(msg.sender), "NFT already staked");

        IERC721 nftToken = IERC721(msg.sender);
        require(nftToken.ownerOf(tokenId) == msg.sender, "You are not the owner of the NFT");

        nftToken.transferFrom(msg.sender, address(this), tokenId);

        farmerStakeRecord[msg.sender] = farmerStake({
            tokenId: tokenId,
            owner: msg.sender,
            timeStamp: block.timestamp
        });

        totalStakedIn.increment();

        emit NFTStaked(msg.sender, tokenId, block.timestamp);
    }

    function unstakeNFT() external {
        require(_isNFTEarning(msg.sender), "No NFT staked");

        uint256 tokenId = farmerStakeRecord[msg.sender].tokenId;

        IERC721 nftToken = IERC721(msg.sender);
        nftToken.transferFrom(address(this), msg.sender, tokenId);

        uint256 amount = 10000*getVarAPR()/100;

        _budsToken.transfer(address(this),amount);

        delete farmerStakeRecord[msg.sender];

        totalStakedIn.decrement();

        emit NFTUnstaked(msg.sender, tokenId);
    }

    function stakeBuds(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(_budsToken.balanceOf(msg.sender) >= amount, "Insufficient Buds balance");

        _budsToken.transferFrom(msg.sender, address(this), amount);

        budsStakeRecord[msg.sender] = budsStake({
            owner: msg.sender,
            amount: amount,
            timeStamp: block.timestamp
        });

        totalStakedIn.increment();

        emit BudsStaked(msg.sender, amount, block.timestamp);
    }

    function unstakeBuds() external {
        require(!_isBudsEarning(msg.sender), "No Buds staked");

        uint256 amount = budsStakeRecord[msg.sender].amount;

        amount = amount + amount*10/100;

        _budsToken.transfer(msg.sender, amount);

        delete budsStakeRecord[msg.sender];

        totalStakedIn.decrement();

        emit BudsUnstaked(msg.sender, amount);
    }

    function _isNFTEarning(address owner) internal view returns (bool) {
        return farmerStakeRecord[owner].owner == owner;
    }

    function _isBudsEarning(address owner) internal view returns (bool) {
        return budsStakeRecord[owner].owner == owner;
    }

    function crossChainAprRequest(uint256 destChainId) public payable{
        if (!_isValidChainId(destChainId)) revert("Not valid destination chain");

        uint256 crossChainGas = 2 * (10 ** 18);
        uint256 zetaValueAndGas = _zetaConsumer.getZetaFromEth{
            value: msg.value
        }(address(this), crossChainGas);
        _zetaToken.approve(address(connector), zetaValueAndGas);

        connector.send(
            ZetaInterfaces.SendInput({
                destinationChainId: destChainId,
                destinationAddress: interactorsByChainId[destChainId],
                destinationGasLimit: 500000,
                message: abi.encode(CROSS_CHAIN_APR_REQUEST,
                    curChainId,
                    destChainId,
                    aprOnChain[curChainId]
                ),
                zetaValueAndGas: zetaValueAndGas,
                zetaParams: abi.encode("")
            })
        );

    }

    function crossChainSendApr(uint256 destChainId) public payable{
        if (!_isValidChainId(destChainId)) revert("Not valid destination chain");

        uint256 crossChainGas = 2 * (10 ** 18);
        uint256 zetaValueAndGas = _zetaConsumer.getZetaFromEth{
            value: msg.value
        }(address(this), crossChainGas);
        _zetaToken.approve(address(connector), zetaValueAndGas);

        connector.send(
            ZetaInterfaces.SendInput({
                destinationChainId: destChainId,
                destinationAddress: interactorsByChainId[destChainId],
                destinationGasLimit: 500000,
                message: abi.encode(CROSS_CHAIN_APR_TRANSFER,
                    curChainId,
                    destChainId,
                    aprOnChain[curChainId]
                ),
                zetaValueAndGas: zetaValueAndGas,
                zetaParams: abi.encode("")
            })
        );

    }

    function onZetaMessage(ZetaInterfaces.ZetaMessage calldata zetaMessage) external override isValidMessageCall(zetaMessage){

        (bytes32 messageType, uint256 sourceChainIdOfMsg, , uint256 apr) = abi.decode(
            zetaMessage.message, (bytes32, uint256, uint256, uint256)
        );

        if(messageType == CROSS_CHAIN_APR_REQUEST){
            crossChainSendApr(sourceChainIdOfMsg);
        }

        if(messageType == CROSS_CHAIN_APR_TRANSFER){
            aprOnChain[sourceChainIdOfMsg] = apr;
        }

        revert("Invalid message type");

    }

    function onZetaRevert(ZetaInterfaces.ZetaRevert calldata zetaRevert) external override isValidRevertCall(zetaRevert){
        (bytes32 messageType, , , ) = abi.decode(
            zetaRevert.message, (bytes32, uint256, uint256, uint256)
        );

        if(messageType == CROSS_CHAIN_APR_REQUEST){

        }

        if(messageType == CROSS_CHAIN_APR_TRANSFER){
            
        }

        revert("Invalid message type");

    }
}