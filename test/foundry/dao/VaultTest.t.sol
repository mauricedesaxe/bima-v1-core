// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IncentiveVoting} from "../../../contracts/dao/IncentiveVoting.sol";
import {MockEmissionReceiver} from "../../../contracts/mocks/MockEmissionReceiver.sol";

// vault specific members
import {IEmissionSchedule} from "../../../contracts/interfaces/IEmissionSchedule.sol";
import {IBoostCalculator} from "../../../contracts/interfaces/IBoostCalculator.sol";
import {EmissionSchedule} from "../../../contracts/dao/EmissionSchedule.sol";
import {BoostCalculator} from "../../../contracts/dao/BoostCalculator.sol";

// test setup
import {TestSetup, IBabelVault, BabelVault, IIncentiveVoting, ITokenLocker} from "../TestSetup.sol";

contract VaultTest is TestSetup {
    // only vault uses these
    EmissionSchedule internal emissionSchedule;
    BoostCalculator internal boostCalc;

    uint256 internal constant INIT_BS_GRACE_WEEKS = 1;
    uint64 internal constant INIT_ES_LOCK_WEEKS = 4;
    uint64 internal constant INIT_ES_LOCK_DECAY_WEEKS = 1;
    uint64 internal constant INIT_ES_WEEKLY_PCT = 2500; // 25%
    uint64[2][] internal scheduledWeeklyPct;

    uint256 internal constant INIT_BAB_TKN_TOTAL_SUPPLY = 1_000_000e18;
    uint64 internal constant INIT_VLT_LOCK_WEEKS = 2;

    function setUp() public virtual override {
        super.setUp();

        // create EmissionSchedule
        emissionSchedule = new EmissionSchedule(
            address(babelCore),
            IIncentiveVoting(address(incentiveVoting)),
            IBabelVault(address(babelVault)),
            INIT_ES_LOCK_WEEKS,
            INIT_ES_LOCK_DECAY_WEEKS,
            INIT_ES_WEEKLY_PCT,
            scheduledWeeklyPct
        );

        // create BoostCalculator
        boostCalc = new BoostCalculator(address(babelCore), ITokenLocker(address(tokenLocker)), INIT_BS_GRACE_WEEKS);
    }

    function test_constructor() external view {
        // addresses correctly set
        assertEq(address(babelVault.babelToken()), address(babelToken));
        assertEq(address(babelVault.locker()), address(tokenLocker));
        assertEq(address(babelVault.voter()), address(incentiveVoting));
        assertEq(babelVault.deploymentManager(), users.owner);
        assertEq(babelVault.lockToTokenRatio(), INIT_LOCK_TO_TOKEN_RATIO);

        // StabilityPool made receiver with ID 0
        (address account, bool isActive) = babelVault.idToReceiver(0);
        assertEq(account, address(stabilityPool));
        assertEq(isActive, true);

        // IncentiveVoting receiver count was increased by 1
        assertEq(incentiveVoting.receiverCount(), 1);
    }

    function test_setInitialParameters() public {
        uint128[] memory _fixedInitialAmounts;
        BabelVault.InitialAllowance[] memory initialAllowances;

        vm.prank(users.owner);
        babelVault.setInitialParameters(
            emissionSchedule,
            boostCalc,
            INIT_BAB_TKN_TOTAL_SUPPLY,
            INIT_VLT_LOCK_WEEKS,
            _fixedInitialAmounts,
            initialAllowances
        );

        // addresses correctly set
        assertEq(address(babelVault.emissionSchedule()), address(emissionSchedule));
        assertEq(address(babelVault.boostCalculator()), address(boostCalc));

        // BabelToken supply correct
        assertEq(babelToken.totalSupply(), INIT_BAB_TKN_TOTAL_SUPPLY);
        assertEq(babelToken.maxTotalSupply(), INIT_BAB_TKN_TOTAL_SUPPLY);

        // BabelToken supply minted to BabelVault
        assertEq(babelToken.balanceOf(address(babelVault)), INIT_BAB_TKN_TOTAL_SUPPLY);

        // BabelVault::unallocatedTotal correct (no initial allowances)
        assertEq(babelVault.unallocatedTotal(), INIT_BAB_TKN_TOTAL_SUPPLY);

        // BabelVault::totalUpdateWeek correct
        assertEq(babelVault.totalUpdateWeek(), _fixedInitialAmounts.length + babelVault.getWeek());

        // BabelVault::lockWeeks correct
        assertEq(babelVault.lockWeeks(), INIT_VLT_LOCK_WEEKS);
    }

    // added because I thought the conversion in `transferTokens` was interesting and worth fuzzing
    function testFuzz_transferTokens(address receiver, uint256 amount) public {
        vm.assume(receiver != address(0) && receiver != address(babelVault));
        amount = bound(amount, 0, babelToken.balanceOf(address(babelVault)));

        uint256 initialUnallocated = babelVault.unallocatedTotal();
        uint256 initialBabelBalance = babelToken.balanceOf(address(babelVault));
        uint256 initialReceiverBalance = babelToken.balanceOf(receiver);

        vm.prank(users.owner);
        bool success = babelVault.transferTokens(IERC20(address(babelToken)), receiver, amount);

        assertTrue(success);
        assertEq(babelVault.unallocatedTotal(), initialUnallocated - amount);
        assertEq(babelToken.balanceOf(address(babelVault)), initialBabelBalance - amount);
        assertEq(babelToken.balanceOf(receiver), initialReceiverBalance + amount);

        // Test with non-BabelToken
        IERC20 mockToken = new ERC20("Mock", "MCK");
        uint256 mockAmount = 1000 * 10 ** 18;
        deal(address(mockToken), address(babelVault), mockAmount);

        uint256 initialMockBalance = mockToken.balanceOf(address(babelVault));
        uint256 initialReceiverMockBalance = mockToken.balanceOf(receiver);

        vm.prank(users.owner);
        success = babelVault.transferTokens(mockToken, receiver, mockAmount);

        assertTrue(success);
        assertEq(babelVault.unallocatedTotal(), initialUnallocated - amount); // Unchanged
        assertEq(mockToken.balanceOf(address(babelVault)), initialMockBalance - mockAmount);
        assertEq(mockToken.balanceOf(receiver), initialReceiverMockBalance + mockAmount);
    }

    // added because I thought the conversion in `transferTokens` was interesting and worth fuzzing
    function testFuzz_transferTokens_revert(address receiver, uint256 amount) public {
        vm.assume(receiver != address(0));
        amount = bound(amount, 0, babelToken.balanceOf(address(babelVault)));

        // Test revert on non-owner call
        vm.prank(users.user1);
        vm.expectRevert("Only owner");
        babelVault.transferTokens(IERC20(address(babelToken)), receiver, amount);

        // Test revert on self-transfer
        vm.prank(users.owner);
        vm.expectRevert("Self transfer denied");
        babelVault.transferTokens(IERC20(address(babelToken)), address(babelVault), amount);

        // Test revert on insufficient balance
        uint256 excessiveAmount = babelToken.balanceOf(address(babelVault)) + 1;
        vm.prank(users.owner);
        vm.expectRevert();
        babelVault.transferTokens(IERC20(address(babelToken)), receiver, excessiveAmount);
    }

    function testFuzz_registerReceiver(address receiver, uint256 count, uint256 weeksToAdd) public {
        vm.assume(receiver != address(0) && receiver != address(babelVault));
        vm.assume(uint160(receiver) > 9); // Exclude precompile addresses (0x1 to 0x9)
        count = bound(count, 1, 100); // Limit count to avoid excessive gas usage or memory issues
        weeksToAdd = bound(weeksToAdd, 0, type(uint64).max - 1);
        vm.assume(weeksToAdd <= type(uint64).max - 1);

        // Set up week
        vm.warp(block.timestamp + weeksToAdd * 1 weeks);
        uint256 currentWeek = babelVault.getWeek();

        // Mock the IEmissionReceiver interface
        MockEmissionReceiver mockReceiver = new MockEmissionReceiver();
        vm.etch(receiver, address(mockReceiver).code);

        // Have owner register receiver
        vm.prank(users.owner);
        bool success = babelVault.registerReceiver(receiver, count);

        // Assertions
        assertTrue(success);
        for (uint256 i = 1; i <= count; i++) {
            (address registeredReceiver, bool isActive) = babelVault.idToReceiver(i);
            assertEq(registeredReceiver, receiver);
            assertTrue(isActive);
            assertEq(babelVault.receiverUpdatedWeek(i), uint16(currentWeek));
        }

        // Verify IncentiveVoting state
        assertEq(incentiveVoting.receiverCount(), count + 1); // +1 because of the initial StabilityPool receiver

        // Verify MockEmissionReceiver state
        MockEmissionReceiver(receiver).assertNotifyRegisteredIdCalled(count);
    }

    function test_registerReceiver_zeroCount() public {
        vm.prank(users.owner);
        vm.expectRevert();
        babelVault.registerReceiver(address(1), 0);
    }

    function test_registerReceiver_revert_zeroAddress() public {
        vm.prank(users.owner);
        vm.expectRevert();
        babelVault.registerReceiver(address(0), 1);
    }

    function test_registerReceiver_revert_babelVault() public {
        vm.prank(users.owner);
        vm.expectRevert();
        babelVault.registerReceiver(address(babelVault), 1);
    }

    function test_registerReceiver_revert_nonOwner() public {
        vm.prank(users.user1);
        vm.expectRevert();
        babelVault.registerReceiver(address(1), 1);
    }
}
