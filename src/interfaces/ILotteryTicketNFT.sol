// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILotteryTicketNFT {
    function mintResultNFT(address to, uint256 epochId, uint256 prizeAmount) external returns (uint256 tokenId);
}
