// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IYumbrella} from "./utils/Setup.sol";

contract FunctionSignatureTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    // This test should not be overridden and checks that
    // no function signature collisions occurred from the custom functions.
    // Does not check functions that are strategy dependant and will be checked in other tests
    function test_functionCollisions() public {
        uint256 wad = 1e18;
        vm.expectRevert("initialized");
        yumbrella.initialize(
            address(asset),
            "name",
            management,
            performanceFeeRecipient,
            keeper
        );

        // Check view functions
        assertEq(yumbrella.convertToAssets(wad), wad, "convert to assets");
        assertEq(yumbrella.convertToShares(wad), wad, "convert to shares");
        assertEq(yumbrella.previewDeposit(wad), wad, "preview deposit");
        assertEq(yumbrella.previewMint(wad), wad, "preview mint");
        assertEq(yumbrella.previewWithdraw(wad), wad, "preview withdraw");
        assertEq(yumbrella.previewRedeem(wad), wad, "preview redeem");
        assertEq(yumbrella.totalAssets(), 0, "total assets");
        assertEq(yumbrella.totalSupply(), 0, "total supply");
        assertEq(yumbrella.unlockedShares(), 0, "unlocked shares");
        assertEq(yumbrella.asset(), address(asset), "asset");
        assertEq(yumbrella.apiVersion(), "3.0.4", "api");
        assertEq(yumbrella.MAX_FEE(), 5_000, "max fee");
        assertEq(yumbrella.fullProfitUnlockDate(), 0, "unlock date");
        assertEq(yumbrella.profitUnlockingRate(), 0, "unlock rate");
        assertGt(yumbrella.lastReport(), 0, "last report");
        assertEq(yumbrella.pricePerShare(), 10**asset.decimals(), "pps");
        assertTrue(!yumbrella.isShutdown());
        assertEq(
            yumbrella.symbol(),
            string(abi.encodePacked("ys", asset.symbol())),
            "symbol"
        );
        assertEq(yumbrella.decimals(), asset.decimals(), "decimals");

        // Assure modifiers are working
        vm.startPrank(user);
        vm.expectRevert("!management");
        yumbrella.setPendingManagement(user);
        vm.expectRevert("!pending");
        yumbrella.acceptManagement();
        vm.expectRevert("!management");
        yumbrella.setKeeper(user);
        vm.expectRevert("!management");
        yumbrella.setEmergencyAdmin(user);
        vm.expectRevert("!management");
        yumbrella.setPerformanceFee(uint16(2_000));
        vm.expectRevert("!management");
        yumbrella.setPerformanceFeeRecipient(user);
        vm.expectRevert("!management");
        yumbrella.setProfitMaxUnlockTime(1);
        vm.stopPrank();

        // Assure checks are being used
        vm.startPrank(yumbrella.management());
        vm.expectRevert("Cannot be self");
        yumbrella.setPerformanceFeeRecipient(address(yumbrella));
        vm.expectRevert("too long");
        yumbrella.setProfitMaxUnlockTime(type(uint256).max);
        vm.stopPrank();

        // Mint some shares to the user
        airdrop(ERC20(address(yumbrella)), user, wad);
        assertEq(yumbrella.balanceOf(address(user)), wad, "balance");
        vm.prank(user);
        yumbrella.transfer(keeper, wad);
        assertEq(yumbrella.balanceOf(user), 0, "second balance");
        assertEq(yumbrella.balanceOf(keeper), wad, "keeper balance");
        assertEq(yumbrella.allowance(keeper, user), 0, "allowance");
        vm.prank(keeper);
        assertTrue(yumbrella.approve(user, wad), "approval");
        assertEq(yumbrella.allowance(keeper, user), wad, "second allowance");
        vm.prank(user);
        assertTrue(yumbrella.transferFrom(keeper, user, wad), "transfer from");
        assertEq(yumbrella.balanceOf(user), wad, "second balance");
        assertEq(yumbrella.balanceOf(keeper), 0, "keeper balance");
    }
}
