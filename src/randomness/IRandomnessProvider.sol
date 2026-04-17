// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRandomnessProvider {
    function requestRandomWord() external returns (uint256 requestId);
    function getRandomWord(uint256 requestId) external view returns (uint256 randomWord, bool ready);
}
