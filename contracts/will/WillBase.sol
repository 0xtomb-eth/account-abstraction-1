// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { StructsLibrary } from "./StructsLibrary.sol";
import { IWillBase } from "../interfaces/IWillBase.sol";
import { SimpleAccount } from "../samples/SimpleAccount.sol";
import { IEntryPoint } from "../interfaces/IEntryPoint.sol";

contract WillBase is IWillBase, SimpleAccount {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    event AllocationSet(
        address indexed asset,
        address[] beneficiaries,
        uint256[] percentages
    );

    event DeathValidatorsSet(
        address[] validators,
        uint256 votingThreshold
    );

    event WillExecuted(
    );

    event DeathAcknowledged(
        address validator,
        bool acknowledged
    );

    // asset address => allocation
    mapping (address => StructsLibrary.Allocation) allocations;
    EnumerableSet.AddressSet userAssets;
    bool willStatus;
    
    // death ack
    StructsLibrary.DeathAck deathAck;

    constructor(IEntryPoint anEntryPoint, address _owner)
        SimpleAccount(anEntryPoint)
    {
        initialize(_owner);
    }
    
    function setAllocation(address asset, address[] calldata beneficiaries, uint256[] calldata percentages) external virtual {
        _allocationValidityCheck;

        StructsLibrary.Allocation storage allocation = allocations[asset];
        if (allocation.beneficiaries.length == 0) {
            userAssets.add(asset);
        }

        allocation.beneficiaries = beneficiaries;
        allocation.percentages = percentages;

        emit AllocationSet(asset, beneficiaries, percentages);
    }

    function setDeathValidators(address[] calldata validators, uint256 votingThreshold) external {
        // clear
        uint256 length = deathAck.validatorAcks.length();
        EnumerableSet.AddressSet storage _validators = deathAck.validators;
        for (uint256 i=length; i>0; i--) {
            _validators.remove(_validators.at(i));
        }

        // reset
        for (uint256 i=0; i<validators.length; ++i) {
            _validators.add(validators[i]);
        }
        deathAck.VotingThreshold = votingThreshold;
        emit DeathValidatorsSet(validators, votingThreshold);
    }

    function ackDeath(bool ack) external {
        require(deathAck.validators.contains(msg.sender));
        if (ack) {
            deathAck.validatorAcks.set(msg.sender, 1);
            emit DeathAcknowledged(msg.sender, true);
        } else {
            deathAck.validatorAcks.set(msg.sender, 0);
            emit DeathAcknowledged(msg.sender, false);
        }
        
        if (_checkDeath()) {
            for (uint256 i=0; i < userAssets.length(); i++) {
                address assetAddr = userAssets.at(i);
                address[] memory beneficiaries = allocations[assetAddr].beneficiaries;
                uint256[] memory percentages = allocations[assetAddr].percentages;
                for (i=0; i<beneficiaries.length; i++) {
                    IERC20(assetAddr).transferFrom(owner, beneficiaries[i], percentages[i]);
                }                
            }
            emit WillExecuted();
        }

    }

    /// view functions below ////

    function getAllocationAssets() external view returns(address[] memory assets) {
        return userAssets.values();
    }

    function getAllocation(address asset) external view returns (StructsLibrary.Allocation memory allocation) {
        return allocations[asset];
    }

    function getValidators() external view returns (address[] memory validators) {
        return deathAck.validators.values();
    }

    function getVotingThreshold() external view returns (uint256) {
        return deathAck.VotingThreshold;
    }

    function checkDeath() external view returns(bool) {
        return _checkDeath();
    }

    function getWillStatus() external view returns(bool) {
        return willStatus;
    }

    function _getAckStatus(address validatorAddr) internal view returns(bool) {
        return (deathAck.validatorAcks.get(validatorAddr) > 0);
    }

    function _checkDeath() internal view returns(bool) {
        return (deathAck.VotingThreshold < deathAck.validatorAcks.length());
    }

    function _allocationValidityCheck(address[] calldata beneficiaries, uint256[] calldata percentages) internal pure {
        require(beneficiaries.length == percentages.length, "Beneficiaries and percentages length mismatch");   

        uint256 sumPercentages = 0;
        for (uint256 j = 0; j < percentages.length; j++) {
            sumPercentages += percentages[j];
        }
        require(sumPercentages == 100, "Total percentages must equal 100");
    }

}