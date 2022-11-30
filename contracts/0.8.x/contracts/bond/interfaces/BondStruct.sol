// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


interface BondStruct {

    enum RequestType {REDEEM, HARVEST}
    enum RequestStatus {PENDING, EXECUTED}
    struct BondInfo {
        uint256 issueDate; // time issue
        uint256 lastHarvest; // last time harvest
        uint256 maturity; // last time harvest
        uint256 amount; // last time harvest
        uint256 interest; // interest
        uint256 batchId;
    }


    struct PendingRequest {
        RequestType requestType;
        RequestStatus status;
        address to;
        uint256 amount;
        uint256 createdAt;
        uint256 batchId;
        uint256[] tokenIds;
    }

    struct BatchConfig {
        uint256 totalFundRaise; // total fund
        uint256 startTime; // time to start
        uint256 maturity; // maturity date
        address currency; //
    }

    //bond nft from backed
    struct BackedBond {
        address nft;
        uint256[] ids;
    }

    struct InterestRate {
        uint256 max;
        uint256 min;
    }

    struct BatchInfo {
        bool status;
        uint256 raised; // current raised
        EnumerableSet.UintSet bondPrice;
        mapping(uint256 => InterestRate) interestRates;
        BackedBond[] backedBond;
        BatchConfig config;
    }

    struct BatchInfoResponse {
        bool status;
        uint256 raised; // current raised
        uint256[] bondPrice;
        InterestRate[] interestRate;
        BackedBond[] backedBond;
        BatchConfig config;
    }

    struct BuyingInfo {
        uint256 batchId;
        uint256 price;
        uint256 quantity;
    }

    struct ClaimInfo {
        uint256 batchId;
        uint256[] ids;
    }
}
