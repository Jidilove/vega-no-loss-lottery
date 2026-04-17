// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {NoLossLottery} from "../src/NoLossLottery.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockYieldVault} from "../src/MockYieldVault.sol";
import {MockRandomnessProvider} from "../src/randomness/MockRandomnessProvider.sol";
import {LotteryTicketNFT} from "../src/LotteryTicketNFT.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeploySepolia is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(pk);

        vm.startBroadcast(pk);

        MockUSDC usdc = new MockUSDC(owner);
        MockYieldVault vault = new MockYieldVault(usdc, owner);
        MockRandomnessProvider randomness = new MockRandomnessProvider(owner);
        LotteryTicketNFT resultNft = new LotteryTicketNFT(owner);

        NoLossLottery implementation = new NoLossLottery();

        bytes memory initData = abi.encodeCall(
            NoLossLottery.initialize,
            (
                owner,
                address(usdc),
                address(vault),
                address(randomness),
                address(resultNft),
                60,
                604800
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        NoLossLottery lottery = NoLossLottery(address(proxy));

        resultNft.setLottery(address(lottery));

        console2.log("MockUSDC:", address(usdc));
        console2.log("MockYieldVault:", address(vault));
        console2.log("MockRandomnessProvider:", address(randomness));
        console2.log("LotteryTicketNFT:", address(resultNft));
        console2.log("NoLossLottery implementation:", address(implementation));
        console2.log("NoLossLottery proxy:", address(lottery));

        vm.stopBroadcast();
    }
}
