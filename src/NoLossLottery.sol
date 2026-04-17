// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IRandomnessProvider} from "./randomness/IRandomnessProvider.sol";
import {ILotteryTicketNFT} from "./interfaces/ILotteryTicketNFT.sol";
import {EpochMath} from "./libraries/EpochMath.sol";

contract NoLossLottery is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    enum EpochStatus {
        NotStarted,
        Active,
        AwaitingRandomness,
        Finalized
    }

    struct Epoch {
        uint256 id;
        uint64 startTime;
        uint64 endTime;
        EpochStatus status;
        uint256 totalPrincipal;
	uint256 totalShares;
        uint256 requestId;
        uint256 prize;
        address winner;
        bool prizeClaimed;
    }

    IERC20 public depositToken;
    IERC4626 public vault;
    IRandomnessProvider public randomnessProvider;
    ILotteryTicketNFT public resultNFT;

    uint256 public currentEpochId;
    uint64 public minEpochDuration;
    uint64 public maxEpochDuration;

    mapping(uint256 => Epoch) public epochs;

    mapping(uint256 => address[]) private epochParticipants;
    mapping(uint256 => mapping(address => bool)) public isParticipant;
    mapping(uint256 => mapping(address => uint256)) public userPrincipal;
    mapping(uint256 => mapping(address => bool)) public principalWithdrawn;

    event EpochStarted(uint256 indexed epochId, uint64 startTime, uint64 endTime);
    event Deposited(uint256 indexed epochId, address indexed user, uint256 assets, uint256 shares);
    event EpochClosed(uint256 indexed epochId, uint256 requestId);
    event EpochFinalized(uint256 indexed epochId, address indexed winner, uint256 prize);
    event PrincipalWithdrawn(uint256 indexed epochId, address indexed user, uint256 amount);
    event PrizeClaimed(uint256 indexed epochId, address indexed winner, uint256 amount, uint256 resultTokenId);

    error InvalidDuration();
    error EpochNotActive();
    error EpochNotAwaitingRandomness();
    error EpochNotFinalized();
    error EpochAlreadyStarted();
    error EpochAlreadyFinalized();
    error EpochStillRunning();
    error NoDeposit();
    error PrincipalAlreadyWithdrawn();
    error NotWinner();
    error PrizeAlreadyClaimed();
    error RandomnessNotReady();
    error ZeroAddress();
    error ZeroAmount();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address depositToken_,
        address vault_,
        address randomnessProvider_,
        address resultNFT_,
        uint64 minEpochDuration_,
        uint64 maxEpochDuration_
    ) external initializer {
        if (
            owner_ == address(0) ||
            depositToken_ == address(0) ||
            vault_ == address(0) ||
            randomnessProvider_ == address(0) ||
            resultNFT_ == address(0)
        ) revert ZeroAddress();

        if (
            minEpochDuration_ == 0 ||
            maxEpochDuration_ == 0 ||
            minEpochDuration_ > maxEpochDuration_
        ) revert InvalidDuration();

        __Ownable_init(owner_);
        __Pausable_init();

        depositToken = IERC20(depositToken_);
        vault = IERC4626(vault_);
        randomnessProvider = IRandomnessProvider(randomnessProvider_);
        resultNFT = ILotteryTicketNFT(resultNFT_);

        minEpochDuration = minEpochDuration_;
        maxEpochDuration = maxEpochDuration_;
    }

    function startEpoch(uint64 duration) external onlyOwner whenNotPaused {
        if (duration < minEpochDuration || duration > maxEpochDuration) {
            revert InvalidDuration();
        }

        if (currentEpochId != 0) {
            Epoch storage prev = epochs[currentEpochId];
            if (
                prev.status == EpochStatus.Active ||
                prev.status == EpochStatus.AwaitingRandomness
            ) {
                revert EpochAlreadyStarted();
            }
        }

        currentEpochId++;
        uint256 epochId = currentEpochId;

        epochs[epochId] = Epoch({
            id: epochId,
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp) + duration,
            status: EpochStatus.Active,
            totalPrincipal: 0,
            totalShares: 0,
            requestId: 0,
            prize: 0,
            winner: address(0),
            prizeClaimed: false
        });

        emit EpochStarted(epochId, uint64(block.timestamp), uint64(block.timestamp) + duration);
    }

    function deposit(uint256 assets) external whenNotPaused nonReentrant {
        if (assets == 0) revert ZeroAmount();

        uint256 epochId = currentEpochId;
        Epoch storage epoch = epochs[epochId];

        if (epoch.status != EpochStatus.Active) revert EpochNotActive();
        if (block.timestamp >= epoch.endTime) revert EpochStillRunning();

        depositToken.safeTransferFrom(msg.sender, address(this), assets);

        depositToken.forceApprove(address(vault), assets);
        uint256 shares = vault.deposit(assets, address(this));

        if (!isParticipant[epochId][msg.sender]) {
            isParticipant[epochId][msg.sender] = true;
            epochParticipants[epochId].push(msg.sender);
        }

        userPrincipal[epochId][msg.sender] += assets;
        epoch.totalPrincipal += assets;
        epoch.totalShares += shares;

        emit Deposited(epochId, msg.sender, assets, shares);
    }

    function closeEpochAndRequestRandomness() external onlyOwner whenNotPaused {
        uint256 epochId = currentEpochId;
        Epoch storage epoch = epochs[epochId];

        if (epoch.status != EpochStatus.Active) revert EpochNotActive();
        if (block.timestamp < epoch.endTime) revert EpochStillRunning();

        uint256 requestId = randomnessProvider.requestRandomWord();

        epoch.requestId = requestId;
        epoch.status = EpochStatus.AwaitingRandomness;

        emit EpochClosed(epochId, requestId);
    }

    function finalizeEpoch() external onlyOwner whenNotPaused nonReentrant {
        uint256 epochId = currentEpochId;
        Epoch storage epoch = epochs[epochId];

        if (epoch.status != EpochStatus.AwaitingRandomness) {
            revert EpochNotAwaitingRandomness();
        }

        (uint256 randomWord, bool ready) = randomnessProvider.getRandomWord(epoch.requestId);
        if (!ready) revert RandomnessNotReady();

        uint256 assetsBeforeRedeem = vault.previewRedeem(epoch.totalShares);

        uint256 prize = EpochMath.computePrize(
            assetsBeforeRedeem,
            epoch.totalPrincipal
        );

        address[] memory participants = epochParticipants[epochId];
        uint256[] memory deposits = new uint256[](participants.length);

        for (uint256 i = 0; i < participants.length; i++) {
            deposits[i] = userPrincipal[epochId][participants[i]];
        }

        uint256 winnerIndex = EpochMath.pickWinnerIndex(
            deposits,
            randomWord,
            epoch.totalPrincipal
        );

        address winner = participants[winnerIndex];

        vault.redeem(epoch.totalShares, address(this), address(this));

        epoch.prize = prize;
        epoch.winner = winner;
        epoch.status = EpochStatus.Finalized;

        emit EpochFinalized(epochId, winner, prize);
    }

    function withdrawPrincipal(uint256 epochId) external nonReentrant {
        Epoch storage epoch = epochs[epochId];
        if (epoch.status != EpochStatus.Finalized) revert EpochNotFinalized();

        uint256 amount = userPrincipal[epochId][msg.sender];
        if (amount == 0) revert NoDeposit();
        if (principalWithdrawn[epochId][msg.sender]) revert PrincipalAlreadyWithdrawn();

        principalWithdrawn[epochId][msg.sender] = true;
        depositToken.safeTransfer(msg.sender, amount);

        emit PrincipalWithdrawn(epochId, msg.sender, amount);
    }

    function claimPrize(uint256 epochId) external nonReentrant {
        Epoch storage epoch = epochs[epochId];
        if (epoch.status != EpochStatus.Finalized) revert EpochNotFinalized();
        if (msg.sender != epoch.winner) revert NotWinner();
        if (epoch.prizeClaimed) revert PrizeAlreadyClaimed();

        epoch.prizeClaimed = true;
        depositToken.safeTransfer(msg.sender, epoch.prize);

        uint256 tokenId = resultNFT.mintResultNFT(msg.sender, epochId, epoch.prize);

        emit PrizeClaimed(epochId, msg.sender, epoch.prize, tokenId);
    }

    function getParticipants(uint256 epochId) external view returns (address[] memory) {
        return epochParticipants[epochId];
    }

    function getUserDeposit(uint256 epochId, address user) external view returns (uint256) {
        return userPrincipal[epochId][user];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setEpochDurationBounds(uint64 minDuration, uint64 maxDuration) external onlyOwner {
        if (minDuration == 0 || maxDuration == 0 || minDuration > maxDuration) {
            revert InvalidDuration();
        }

        minEpochDuration = minDuration;
        maxEpochDuration = maxDuration;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
