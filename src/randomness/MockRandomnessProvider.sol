// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRandomnessProvider} from "./IRandomnessProvider.sol";

contract MockRandomnessProvider is IRandomnessProvider, Ownable {
    uint256 public nextRequestId;
    mapping(uint256 => uint256) private _randomWords;
    mapping(uint256 => bool) private _ready;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function requestRandomWord() external override returns (uint256 requestId) {
        nextRequestId++;
        requestId = nextRequestId;
    }

    function fulfillRandomWord(uint256 requestId, uint256 randomWord) external onlyOwner {
        require(requestId != 0 && requestId <= nextRequestId, "bad requestId");
        _randomWords[requestId] = randomWord;
        _ready[requestId] = true;
    }

    function getRandomWord(uint256 requestId) external view override returns (uint256 randomWord, bool ready) {
        return (_randomWords[requestId], _ready[requestId]);
    }
}
