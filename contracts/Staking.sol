// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function burn(uint256 amount) external;
}


contract Stake is  VRFConsumerBaseV2, ConfirmedOwner {
    using Counters for Counters.Counter;
    Counters.Counter public totalStakedFarmers;
    uint256 public totalStakedBudTokens;
    IERC20 public immutable _budsToken;
    IERC721 public immutable _farmerToken;

    VRFCoordinatorV2Interface COORDINATOR;

    struct stake {
        address owner;
        uint256 timeStamp;
        uint256 budsAmount;
        uint256 farmerTokenId;
        uint256 avgAPR;
    }
    struct RequestStatus {
        bool fulfilled; 
        bool exists; 
        uint256[] randomWords;
    }

    uint256 public lastRequestId;
    uint256 public latestRecordedAPR;
    uint256 public noOfChains;
    uint256 private randomNo;
    uint64 s_subscriptionId;
    uint32 numWords = 1;
    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;

    uint256[] public requestIds;
    address[] public stakerAddresses;

    bytes32 keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;
    
    mapping(address => stake) public stakeRecord; 
    mapping(uint256 => RequestStatus) public s_requests;
    mapping(address => uint256[]) public boosts;

    event NFTStaked(address owner, uint256 tokenId, uint256 timeStamp, uint256 totalStakedNFTs);
    event NFTUnstaked(address owner, uint256 tokenId, uint256 totalStakedNFTs);
    event BudsStaked(address owner, uint256 amount, uint256 timeStamp, uint256 totalStakedBuds);
    event BudsUnstaked(address owner, uint256 amount,  uint256 totalStakedBuds, uint256 latestApr);
    event Staked(address owner, uint256 tokenId, uint256 budsAmount, uint256 timeStamp, uint256 totalStakedBuds, uint256 totalStakedFarmers, uint256 latestApr);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    constructor(
        address _budsTokenAddress, 
        address _farmerTokenAddress,
        uint64 subscriptionId,
        uint256 baseAPR
    ) VRFConsumerBaseV2(0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D)
        ConfirmedOwner(msg.sender){
        _budsToken = IERC20(_budsTokenAddress);
        _farmerToken = IERC721(_farmerTokenAddress);
        COORDINATOR = VRFCoordinatorV2Interface(0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D);
        s_subscriptionId = subscriptionId;
        latestRecordedAPR = baseAPR;
    }

    function getNumberOfStakers() public view returns(uint256){
        return stakerAddresses.length;
    }

    function setNumberOfChains(uint256 _noOfChains) public{
        noOfChains = _noOfChains;
    }

    function addStake(uint256 _budsAmount, uint256 currentApr, uint256 _farmerTokenId) public {
        require(_budsAmount != 0, "put some buds in it");
        require(currentApr != 0, "What's the current apr");
        bool isFarmerStaked = false;
        if(_farmerTokenId != 0)
            require(_farmerToken.ownerOf(_farmerTokenId) == msg.sender, "Not your NFT");
            totalStakedFarmers.increment();
            isFarmerStaked = true;

        latestRecordedAPR = (latestRecordedAPR+currentApr)/2;      

        stakeRecord[msg.sender] = stake({
            owner:msg.sender,
            timeStamp:block.timestamp,
            budsAmount:_budsAmount,
            farmerTokenId:_farmerTokenId,
            avgAPR:latestRecordedAPR
        });

        for(uint256 i = 0; i < stakerAddresses.length; i++){
            stake storage stk = stakeRecord[stakerAddresses[i]];
            stk.avgAPR = (stk.avgAPR+currentApr)/2;
        }

        stakerAddresses.push(msg.sender);
        totalStakedBudTokens += _budsAmount;

        _budsToken.transferFrom(msg.sender, address(this), _budsAmount);
        if(isFarmerStaked)
            _farmerToken.safeTransferFrom(msg.sender, address(this), _farmerTokenId);

        emit Staked(msg.sender, _farmerTokenId, _budsAmount, block.timestamp, totalStakedBudTokens, totalStakedFarmers.current(), latestRecordedAPR);
    }

    function updateStake(uint256 _budsAmount, uint256 _farmerTokenId) public{
        require(_budsAmount != 0 || _farmerTokenId != 0, "No update data provided");
        stake storage stk = stakeRecord[msg.sender];
        stk.budsAmount += _budsAmount;
        if(_farmerTokenId != 0 && _farmerToken.ownerOf(_farmerTokenId) == msg.sender){
            if(stk.farmerTokenId != 0) 
                revert("Farmer already staked");
            stk.farmerTokenId = _farmerTokenId;
        }
        emit Staked(msg.sender, _farmerTokenId, _budsAmount, block.timestamp, totalStakedBudTokens, totalStakedFarmers.current(), latestRecordedAPR);        
    }

    function unStakeBuds(uint256 _budsAmount, uint256 currentApr) public{
        require(stakeRecord[msg.sender].budsAmount > 0, "No buds staked");
        require(stakeRecord[msg.sender].budsAmount >= _budsAmount, "Insufficient stake amount");
        stake storage stk = stakeRecord[msg.sender];
        stk.budsAmount -= _budsAmount;

        uint256 applicableReturns = calculateReturn(_budsAmount, stk.timeStamp);

        if(stk.budsAmount == 0 && stk.farmerTokenId == 0)
            for(uint256 i = 0; i < stakerAddresses.length; i++){
                if(msg.sender == stakerAddresses[i]){
                    address temp  = stakerAddresses[stakerAddresses.length-1];
                    stakerAddresses[i] = temp;
                    stakerAddresses[stakerAddresses.length-1] = msg.sender;
                    stakerAddresses.pop();
                    break;
                }
            }
            delete stakeRecord[msg.sender];

        totalStakedBudTokens -= _budsAmount;
        latestRecordedAPR = (latestRecordedAPR+currentApr)/2;

        _budsToken.transfer(msg.sender, applicableReturns);

        emit BudsUnstaked(msg.sender, _budsAmount, totalStakedBudTokens, latestRecordedAPR);
    }

    function unStakeFarmer(uint256 currentApr) public{
        require(stakeRecord[msg.sender].farmerTokenId != 0, "No farmer staked");
        stake storage stk = stakeRecord[msg.sender];
        uint256 tokenIdToSend = stk.farmerTokenId;
        stk.farmerTokenId = 0;

        latestRecordedAPR = (latestRecordedAPR+currentApr)/2;
        totalStakedFarmers.decrement();

        if(stk.farmerTokenId == 0 && stk.budsAmount == 0)
            delete stakeRecord[msg.sender];
        
        _farmerToken.safeTransferFrom(address(this), msg.sender, tokenIdToSend);

        emit NFTUnstaked(msg.sender, tokenIdToSend, totalStakedFarmers.current());
    }

    function calculateReturn(uint256 _budsAmount, uint256 startTime) internal view returns(uint256){
        uint256 timeStaked = block.timestamp - startTime;
        timeStaked = timeStaked/365 days;
        uint256 rewards = _budsAmount*latestRecordedAPR*timeStaked;
        return rewards+_budsAmount;
    }

    function applyBoost() public {
        for(uint256 i = 0; i < boosts[msg.sender].length; i++){
            if(boosts[msg.sender][i] - block.timestamp >= 7 days){
                delete boosts[msg.sender][i];
            }
        }
        require(boosts[msg.sender].length < 4, "Only four boosts are allowed at a time");
        uint256 len = boosts[msg.sender].length;

        stake storage stk = stakeRecord[msg.sender];
        stk.avgAPR = stk.avgAPR+5%len;
        boosts[msg.sender].push(block.timestamp);
    }

    function raid(uint256 totalBudsStakedAcrossAllChains, uint256 boostAdv) public returns(bool){

        uint256 reqNo = requestRandomWords();

        uint256 randomPercent = (randomNo%6)+1;

        //global avg of staked buds on each chain
        uint256 avgStakeBuds = totalBudsStakedAcrossAllChains/noOfChains;

        //gross share per capita glocal and local
        uint256 globalGSPC = avgStakeBuds/stakerAddresses.length;
        uint256 localGSPC = totalStakedBudTokens/stakerAddresses.length;

        if(localGSPC < globalGSPC){
            //if local gross share per capita is less than global 
            //calculating how much less is local GDPC as compared to globals GDPC
            uint256 percentLess = (localGSPC/globalGSPC)*100;

            //decreasing the success in same ratio
            randomPercent = (randomPercent * percentLess)/100;
        }

        if(boostAdv != 0){
            randomPercent += boostAdv;
        }

        uint256 randReq2 = requestRandomWords();

        uint256 decidingFactor = randomNo%100;

        if(randomPercent == decidingFactor){
            uint256 rewardAmount = totalStakedBudTokens/1000;
            _budsToken.burn(rewardAmount/1000);
            rewardAmount = rewardAmount/1000;
            _budsToken.transfer(msg.sender, rewardAmount);
            return true;
        }

        return false;
    }

    //-------------------------------------------------RANDOMNESS-------------------------------------------------
    function requestRandomWords()
        public
        returns (uint256 requestId)
    {
        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        randomNo = _randomWords[0];
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }

    
}