// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

import {NoLossLottery} from "../src/NoLossLottery.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockYieldVault} from "../src/MockYieldVault.sol";
import {MockRandomnessProvider} from "../src/randomness/MockRandomnessProvider.sol";
import {LotteryTicketNFT} from "../src/LotteryTicketNFT.sol";

contract NoLossLotteryDepositTest is Test {
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

        vm.prank(alice);
        usdc.approve(address(lottery), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(lottery), type(uint256).max);

        lottery.startEpoch(7 days);
    }

    function test_DepositUpdatesPrincipalAndShares() public {
        vm.prank(alice);
        lottery.deposit(100e6);

        (
            uint256 id,
            uint64 startTime,
            uint64 endTime,
            NoLossLottery.EpochStatus status,
            uint256 totalPrincipal,
            uint256 totalShares,
            uint256 requestId,
            uint256 prize,
            address winner,
            bool prizeClaimed
        ) = lottery.epochs(1);

        assertEq(id, 1);
        assertEq(uint256(status), uint256(NoLossLottery.EpochStatus.Active));
        assertEq(totalPrincipal, 100e6);
        assertEq(totalShares, 100e6);
        assertEq(requestId, 0);
        assertEq(prize, 0);
        assertEq(winner, address(0));
        assertEq(prizeClaimed, false);

        assertEq(lottery.getUserDeposit(1, alice), 100e6);
        assertEq(usdc.balanceOf(address(lottery)), 0);
        assertEq(usdc.balanceOf(address(vault)), 100e6);

        startTime;
        endTime;
    }

    function test_MultipleUsersDeposit() public {
        vm.prank(alice);
        lottery.deposit(100e6);

        vm.prank(bob);
        lottery.deposit(300e6);

        (, , , , uint256 totalPrincipal, uint256 totalShares, , , , ) = lottery.epochs(1);

        assertEq(totalPrincipal, 400e6);
        assertEq(totalShares, 400e6);

        assertEq(lottery.getUserDeposit(1, alice), 100e6);
        assertEq(lottery.getUserDeposit(1, bob), 300e6);

        address[] memory participants = lottery.getParticipants(1);
        assertEq(participants.length, 2);
        assertEq(participants[0], alice);
        assertEq(participants[1], bob);
    }

    function test_RevertDepositZero() public {
        vm.prank(alice);
        vm.expectRevert(NoLossLottery.ZeroAmount.selector);
        lottery.deposit(0);
    }
}
