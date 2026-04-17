// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

import {NoLossLottery} from "../src/NoLossLottery.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockYieldVault} from "../src/MockYieldVault.sol";
import {MockRandomnessProvider} from "../src/randomness/MockRandomnessProvider.sol";
import {LotteryTicketNFT} from "../src/LotteryTicketNFT.sol";

contract NoLossLotteryFinalizeTest is Test {
    MockUSDC internal usdc;
    MockYieldVault internal vault;
    MockRandomnessProvider internal randomness;
    LotteryTicketNFT internal resultNft;
    NoLossLottery internal lottery;

    address internal owner = address(this);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        usdc = new MockUSDC(owner);
        vault = new MockYieldVault(usdc, owner);
        randomness = new MockRandomnessProvider(owner);
        resultNft = new LotteryTicketNFT(owner);

        NoLossLottery implementation = new NoLossLottery();

        bytes memory initData = abi.encodeCall(
            NoLossLottery.initialize,
            (
                owner,
                address(usdc),
                address(vault),
                address(randomness),
                address(resultNft),
                1 days,
                30 days
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        lottery = NoLossLottery(address(proxy));

        resultNft.setLottery(address(lottery));

        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        usdc.mint(owner, 1_000_000e6);

        vm.prank(alice);
        usdc.approve(address(lottery), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(lottery), type(uint256).max);

        usdc.approve(address(vault), type(uint256).max);

        lottery.startEpoch(7 days);

        vm.prank(alice);
        lottery.deposit(100e6);

        vm.prank(bob);
        lottery.deposit(300e6);
    }

    function test_FinalizeSelectsWinnerAndComputesPrize() public {
        vault.addYield(40e6);

        vm.warp(block.timestamp + 7 days + 1);
        lottery.closeEpochAndRequestRandomness();

        (, , , , , , uint256 requestId, , , ) = lottery.epochs(1);
        assertEq(requestId, 1);

        randomness.fulfillRandomWord(requestId, 350e6);

        lottery.finalizeEpoch();

        (
            ,
            ,
            ,
            NoLossLottery.EpochStatus status,
            uint256 totalPrincipal,
            uint256 totalShares,
            ,
            uint256 prize,
            address winner,
            bool prizeClaimed
        ) = lottery.epochs(1);

        assertEq(uint256(status), uint256(NoLossLottery.EpochStatus.Finalized));
        assertEq(totalPrincipal, 400e6);
        assertEq(totalShares, 400e6);
        assertApproxEqAbs(prize, 40e6, 1);
        assertEq(winner, bob);
        assertEq(prizeClaimed, false);
    }
}
