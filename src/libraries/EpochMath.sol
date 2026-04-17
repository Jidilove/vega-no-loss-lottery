// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library EpochMath {
    error ZeroTotalPrincipal();
    error PrizeUnderflow();
    error EmptyParticipants();

    function computePrize(
        uint256 totalAssets,
        uint256 totalPrincipal
    ) internal pure returns (uint256) {
        if (totalPrincipal == 0) revert ZeroTotalPrincipal();
        if (totalAssets < totalPrincipal) revert PrizeUnderflow();
        return totalAssets - totalPrincipal;
    }

    function pickWinnerIndex(
        uint256[] memory deposits,
        uint256 randomWord,
        uint256 totalPrincipal
    ) internal pure returns (uint256) {
        if (deposits.length == 0) revert EmptyParticipants();
        if (totalPrincipal == 0) revert ZeroTotalPrincipal();

        uint256 target = randomWord % totalPrincipal;
        uint256 cumulative = 0;

        for (uint256 i = 0; i < deposits.length; i++) {
            cumulative += deposits[i];
            if (target < cumulative) {
                return i;
            }
        }

        revert EmptyParticipants();
    }
}
