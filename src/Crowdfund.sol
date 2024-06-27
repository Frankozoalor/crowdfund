// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MyToken} from "./Token/MyToken.sol";

contract Crowdfund {
    error IdDoesNotExist(uint256 id);
    error amountExceedsGoal(uint256 goal, uint256 amount);
    error noContribution();
    error callerNotOwnerOfCampaign(address user);
    error GoalNotReached();
    error campaignDurationNotPassed();
    error ownerCannotContribute();
    error amountCannotBeZero();
    error deadlinePassed();

    using SafeERC20 for IERC20;

    /**
     * @param _tokens list of allowed token addresses
     */
    struct CampaignStatus {
        address owner;
        address token;
        uint256 Goal;
        uint256 duration;
        uint256 amountRaised;
    }

    constructor(address[] memory _tokens) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenAllowed[_tokens[i]] = true;
        }
    }

    uint256 campaignID;

    mapping(address token => bool allowed) tokenAllowed;
    mapping(address user => mapping(uint256 id => uint256 amount)) userAmountDeposited;
    mapping(uint256 id => bool exits) idExists;
    mapping(uint256 id => CampaignStatus) _campaignstatus;

    modifier _idExists(uint256 id) {
        if (!idExists[id]) revert IdDoesNotExist(id);
        _;
    }

    /**
     * @notice createCampaign allows anyone to create a campaign
     * @param _goal amount of funds to be raised in USD
     * @param _duration the duration of the campaign in seconds
     */
    function createCampaign(address _token, uint256 _goal, uint256 _duration) external returns (uint256) {
        uint256 id = campaignID++;
        CampaignStatus storage campaign = _campaignstatus[campaignID];
        campaign.owner = msg.sender;
        campaign.Goal = _goal;
        campaign.duration = block.timestamp + _duration;
        campaign.token = _token;
        idExists[id] = true;
        return id;
    }

    /**
     * @dev contribute allows anyone to contribute to a campaign
     * @param _id the id of the campaign
     * @param _amount the amount of tokens to contribute
     */
    function contribute(uint256 _id, uint256 _amount) external _idExists(_id) {
        CampaignStatus storage campaign = _campaignstatus[_id];
        if (msg.sender == campaign.owner) revert ownerCannotContribute();
        if (_amount == 0) revert amountCannotBeZero();
        if (campaign.amountRaised + _amount > campaign.Goal) revert amountExceedsGoal(campaign.Goal, _amount);
        userAmountDeposited[msg.sender][_id] += _amount;
        campaign.amountRaised += _amount;
        address campaignToken = campaign.token;
        IERC20(campaignToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice This function allows any donor to cancel their contribution.
     *  It should revert if no donations have been made by the caller for the particular campaign.
     */
    function cancelContribution(uint256 _id) external _idExists(_id) {
        CampaignStatus storage campaign = _campaignstatus[_id];
        if (block.timestamp >= campaign.duration) revert deadlinePassed();
        uint256 amountDeposited = userAmountDeposited[msg.sender][_id];
        address tokenAddress = campaign.token;
        if (amountDeposited == 0) revert noContribution();
        delete userAmountDeposited[msg.sender][_id];
        IERC20(tokenAddress).safeTransfer(msg.sender, amountDeposited);
    }

    /**
     * @notice This function allows the creator of the campaign id to collect all the contributions.
     * This function must revert if the duration of the campaign has not passed, or / and the goal has not been met.
     */
    function withdraw(uint256 _id) external _idExists(_id) returns (uint256) {
        CampaignStatus memory campaign = _campaignstatus[_id];
        uint256 amountToWithdraw = campaign.Goal;
        address tokenAddress = campaign.token;
        if (campaign.owner != msg.sender) revert callerNotOwnerOfCampaign(msg.sender);
        if (block.timestamp < campaign.duration) revert campaignDurationNotPassed();
        if (campaign.amountRaised < amountToWithdraw) revert GoalNotReached();
        IERC20(tokenAddress).safeTransfer(msg.sender, amountToWithdraw);
        return amountToWithdraw;
    }

    /**
     * This allows the donors to get their funds back if the campaign has failed.
     * It should revert if no donations were made to this campaign by the caller
     */
    function refund(uint256 _id) external _idExists(_id) {
        CampaignStatus storage campaign = _campaignstatus[_id];
        uint256 amountToRefund = userAmountDeposited[msg.sender][_id];
        address tokenAddress = campaign.token;
        if (amountToRefund == 0) revert noContribution();
        if (block.timestamp >= campaign.duration && campaign.amountRaised < campaign.Goal) {
            IERC20(tokenAddress).safeTransfer(msg.sender, amountToRefund);
        }
    }

    /**
     * @notice This function allows anyone to view the contributions made by contributor for the id campaign (in USD).
     */
    function getContribution(uint256 _id, address contributor) external view _idExists(_id) returns (uint256) {
        return userAmountDeposited[contributor][_id];
    }

    /**
     * @notice  This function returns the remaining time, the goal, token, and the total funds collected (in USD).
     */
    function getCampaign(uint256 _id) external view _idExists(_id) returns (uint256, uint256, address, uint256) {
        CampaignStatus memory campaign = _campaignstatus[_id];
        uint256 remainingtime = campaign.duration - block.timestamp;
        uint256 goal = campaign.Goal;
        uint256 totalFundsRaised = campaign.amountRaised;
        address campaignToken = campaign.token;
        return (remainingtime, goal, campaignToken, totalFundsRaised);
    }
}
