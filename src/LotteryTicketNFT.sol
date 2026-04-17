// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ILotteryTicketNFT} from "./interfaces/ILotteryTicketNFT.sol";

contract LotteryTicketNFT is ERC721, Ownable, ILotteryTicketNFT {
    using Strings for uint256;

    uint256 public nextTokenId;
    address public lottery;
    string private _baseTokenURI;

    struct ResultData {
        uint256 epochId;
        uint256 prizeAmount;
    }

    mapping(uint256 => ResultData) public resultData;

    error NotLottery();

    modifier onlyLottery() {
        if (msg.sender != lottery) revert NotLottery();
        _;
    }

    constructor(address initialOwner) ERC721("Lottery Result NFT", "LRNFT") Ownable(initialOwner) {}

    function setLottery(address lottery_) external onlyOwner {
        lottery = lottery_;
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    function mintResultNFT(
        address to,
        uint256 epochId,
        uint256 prizeAmount
    ) external override onlyLottery returns (uint256 tokenId) {
        nextTokenId++;
        tokenId = nextTokenId;

        _safeMint(to, tokenId);
        resultData[tokenId] = ResultData({
            epochId: epochId,
            prizeAmount: prizeAmount
        });
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        string memory base = _baseTokenURI;
        if (bytes(base).length == 0) {
            return "";
        }

        return string(abi.encodePacked(base, tokenId.toString(), ".json"));
    }
}
