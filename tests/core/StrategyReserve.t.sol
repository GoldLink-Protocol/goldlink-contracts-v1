// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { PercentMath } from "../../contracts/libraries/PercentMath.sol";
import { Constants } from "../../contracts/libraries/Constants.sol";
import {
    IStrategyReserve
} from "../../contracts/interfaces/IStrategyReserve.sol";
import { IStrategyBank } from "../../contracts/interfaces/IStrategyBank.sol";
import { Errors } from "../../contracts/libraries/Errors.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { StrategyReserve } from "../../contracts/core/StrategyReserve.sol";
import { TestUtilities } from "../testLibraries/TestUtilities.sol";
import { TestConstants } from "../testLibraries/TestConstants.sol";
import {
    IStrategyController
} from "../../contracts/interfaces/IStrategyController.sol";
import {
    IInterestRateModel
} from "../../contracts/interfaces/IInterestRateModel.sol";
import {
    IStrategyAccountDeployer
} from "../../contracts/interfaces/IStrategyAccountDeployer.sol";
import "forge-std/Test.sol";

import { StateManager } from "../StateManager.sol";

contract StrategyReserveTest is Test, StateManager {
    using PercentMath for uint256;
    using Math for uint256;

    // ============ Storage Variables ============

    IStrategyReserve strategyReserve;

    IStrategyController strategyController;

    // ============ Setup ============

    function setUp() public {
        strategyReserve = strategyReserves[0];
        strategyController = strategyControllers[0];
    }

    // ============ Constructor ============

    constructor() StateManager(false) {}

    // ============ Events ============

    // Emitted from the Interest Rate Model but tested here.
    event ModelUpdated(
        uint256 optimalUtilization,
        uint256 baseInterestRate,
        uint256 rateSlope1,
        uint256 rateSlope2
    );

    // ============ Constructor Tests ============

    function testAssetHasNoDecimals() public {
        IStrategyReserve.ReserveParameters memory reserveParams = TestConstants
            .defaultReserveParameters();
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));

        _expectRevert(
            Errors
                .STRATEGY_RESERVE_STRATEGY_ASSET_DOES_NOT_HAVE_ASSET_DECIMALS_SET
        );
        new StrategyReserve(
            address(this),
            IERC20(address(this)),
            IStrategyController(address(this)),
            reserveParams,
            bankParams
        );
    }

    function testZeroControllerAddress() public {
        IStrategyReserve.ReserveParameters memory reserveParams = TestConstants
            .defaultReserveParameters();
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));

        _expectRevert(Errors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        new StrategyReserve(
            address(this),
            usdc,
            IStrategyController(address(0)),
            reserveParams,
            bankParams
        );
    }

    function testZeroOwnerAddress() public {
        IStrategyReserve.ReserveParameters memory reserveParams = TestConstants
            .defaultReserveParameters();
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));

        _expectRevert(Errors.ZERO_ADDRESS_IS_NOT_ALLOWED);
        new StrategyReserve(
            address(this),
            IERC20(address(0)),
            IStrategyController(address(this)),
            reserveParams,
            bankParams
        );
    }

    function testZeroAssetAddress() public {
        IStrategyReserve.ReserveParameters memory reserveParams = TestConstants
            .defaultReserveParameters();
        IStrategyBank.BankParameters memory bankParams = TestUtilities
            .defaultBankParameters(IStrategyAccountDeployer(address(this)));

        vm.expectRevert();
        new StrategyReserve(
            address(0),
            usdc,
            IStrategyController(address(this)),
            reserveParams,
            bankParams
        );
    }

    // ============ Update Reserve TVL Cap Tests ============

    function testUpdateReserveTVLCap() public {
        strategyReserve.updateReserveTVLCap(100);

        assertEq(strategyReserve.tvlCap_(), 100);
    }

    // ============ Update Model Tests ============

    function testUpdateModelNotOwner() public {
        vm.prank(address(msg.sender));

        vm.expectRevert();
        StrategyReserve(address(strategyReserve)).updateModel(
            IInterestRateModel.InterestRateModelParameters(
                TestConstants.DEFAULT_OPTIMAL_UTILIZATION,
                TestConstants.DEFAULT_BASE_INTEREST_RATE,
                TestConstants.DEFAULT_RATE_SLOPE_1,
                TestConstants.DEFAULT_RATE_SLOPE_2
            )
        );
    }

    function testUpdateModel() public {
        uint256 depositAmount = 1e8;
        usdc.mint(address(this), depositAmount);

        usdc.approve(address(strategyReserve), type(uint256).max);

        uint256 shares = strategyReserve.deposit(depositAmount, address(this));
        assertEq(shares, depositAmount);
        vm.warp(block.timestamp + 365 days);

        TestUtilities.mintAndApprove(
            usdc,
            5e7,
            address(strategyReserve.STRATEGY_BANK())
        );

        _addCollateral(0, 5e7);
        _borrow(0, 5e7); // optimal utilization

        StrategyReserve fullReserve = StrategyReserve(address(strategyReserve));

        // Pass time so `updateModel` will update cumulative index.
        vm.warp(block.timestamp + 365 days);

        assertEq(fullReserve.cumulativeInterestIndex(), 0);

        IInterestRateModel.InterestRateModelParameters
            memory model = IInterestRateModel.InterestRateModelParameters(
                TestConstants.DEFAULT_OPTIMAL_UTILIZATION + 1,
                TestConstants.DEFAULT_BASE_INTEREST_RATE * 5,
                TestConstants.DEFAULT_RATE_SLOPE_1 * 3,
                TestConstants.DEFAULT_RATE_SLOPE_2 * 4
            );

        vm.expectEmit(true, true, true, true, address(fullReserve));
        emit ModelUpdated(
            model.optimalUtilization,
            model.baseInterestRate,
            model.rateSlope1,
            model.rateSlope2
        );
        fullReserve.updateModel(model);

        (
            uint256 optimalUtilization,
            uint256 baseInterestRate,
            uint256 rateSlope1,
            uint256 rateSlope2
        ) = fullReserve.model_();
        assertEq(
            optimalUtilization,
            TestConstants.DEFAULT_OPTIMAL_UTILIZATION + 1
        );
        assertEq(
            baseInterestRate,
            TestConstants.DEFAULT_BASE_INTEREST_RATE * 5
        );
        assertEq(rateSlope1, TestConstants.DEFAULT_RATE_SLOPE_1 * 3);
        assertEq(rateSlope2, TestConstants.DEFAULT_RATE_SLOPE_2 * 4);

        assertEq(fullReserve.cumulativeInterestIndex(), 0.1e18);
    }

    // ============ Borrow Tests ============

    function testBorrow() public {
        uint256 depositAmount = 1e8;
        usdc.mint(address(this), depositAmount);

        usdc.approve(address(strategyReserve), type(uint256).max);

        uint256 shares = strategyReserve.deposit(depositAmount, address(this));
        assertEq(shares, depositAmount);
        vm.warp(block.timestamp + 365 days);

        TestUtilities.mintAndApprove(
            usdc,
            5e7,
            address(strategyReserve.STRATEGY_BANK())
        );

        _addCollateral(0, 5e7);
        _borrow(0, 5e7); // optimal utilization

        vm.warp(block.timestamp + 365 days);

        vm.prank(address(strategyReserve.STRATEGY_BANK()));
        (uint256 interestOwed, ) = strategyReserve.settleInterest(5e7, 0);

        usdc.mint(address(this), interestOwed);

        usdc.approve(address(strategyReserve), interestOwed + 5e7);

        vm.prank(address(strategyAccounts[0]));
        strategyBanks[0].repayLoan(5e7, 5e7);

        assertEq(strategyReserve.utilizedAssets_(), 0);
        assertEq(strategyReserve.maxRedeem(address(this)), 1e8);
        assertEq(strategyReserve.maxWithdraw(address(this)), 104749999);
    }

    function testBorrowWhenTvlIsAtLimit() public {
        uint256 depositAmount = strategyReserve.tvlCap_();
        usdc.mint(address(this), 3 * depositAmount);

        usdc.approve(address(strategyReserve), type(uint256).max);

        uint256 shares = strategyReserve.deposit(depositAmount, address(this));
        assertEq(shares, depositAmount);
        vm.warp(block.timestamp + 365 days);

        TestUtilities.mintAndApprove(
            usdc,
            5e7,
            address(strategyReserve.STRATEGY_BANK())
        );

        _addCollateral(0, depositAmount);
        strategyAccounts[0].executeBorrow(depositAmount);
    }

    // ============ Deposit Tests ============

    function testDepositWhenPaused() public {
        strategyController.pause();
        _expectRevert(Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED);
        strategyReserve.deposit(100, address(this));
    }

    function testDepositWhenPausedInOtherReserve() public {
        strategyController.pause();

        _createLender(2, 50, 50);
    }

    function testDepositBeyondMax() public {
        TestUtilities.mintAndApprove(usdc, 1e20, address(strategyReserve));

        vm.expectRevert();
        strategyReserve.deposit(1e20, msg.sender);
    }

    function testDepositFirstDepositAttack() public {
        TestUtilities.mintAndApprove(usdc, 1e20, address(strategyReserve));

        uint256 shares = strategyReserve.deposit(1, msg.sender);
        assertEq(shares, 1);
        usdc.transfer(address(strategyReserve), 1e5);

        uint256 shares2 = strategyReserve.deposit(1000, address(this));
        assertEq(shares2, 1000);

        vm.prank(msg.sender);
        uint256 assets = strategyReserve.redeem(1, msg.sender, msg.sender);
        assertEq(assets, 1);
    }

    function testDepositSecondDonation() public {
        TestUtilities.mintAndApprove(usdc, 1e20, address(strategyReserve));

        uint256 shares = strategyReserve.deposit(1, msg.sender);
        assertEq(shares, 1);

        uint256 shares2 = strategyReserve.deposit(1000, address(this));
        assertEq(shares2, 1000);

        usdc.transfer(address(strategyReserve), 1e5);

        uint256 assets = strategyReserve.redeem(
            1000,
            msg.sender,
            address(this)
        );
        assertEq(assets, 1000);

        vm.prank(msg.sender);
        uint256 assets2 = strategyReserve.redeem(1, msg.sender, msg.sender);
        assertEq(assets2, 1);
    }

    function testDeposit() public {
        uint256 depositAmount = 1e8;
        usdc.mint(address(this), depositAmount);

        usdc.approve(address(strategyReserve), type(uint256).max);

        uint256 shares = strategyReserve.deposit(depositAmount, address(this));

        assertEq(strategyReserve.maxRedeem(address(this)), 1e8);
        assertEq(strategyReserve.maxWithdraw(address(this)), 1e8);

        uint256 currBalance = strategyReserve.balanceOf(address(this));
        assertEq(currBalance, 1e8);
        uint256 currBalanceUsdc = usdc.balanceOf(address(this));

        strategyReserve.redeem(shares, address(this), address(this));

        uint256 newBalance = strategyReserve.balanceOf(address(this));
        uint256 newBalanceUsdc = usdc.balanceOf(address(this));

        assertEq(newBalance, 0);
        assertEq(newBalanceUsdc, currBalanceUsdc + depositAmount);

        assertEq(usdc.balanceOf(address(strategyReserve)), 0);

        assertEq(strategyReserve.totalSupply(), 0);
    }

    // ============ Mint Tests ============

    function testMintWhenPaused() public {
        strategyController.pause();
        _expectRevert(Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED);
        strategyReserve.mint(100, address(this));
    }

    function testMintBeyondMax() public {
        TestUtilities.mintAndApprove(usdc, 1e20, address(strategyReserve));

        vm.expectRevert();
        strategyReserve.mint(type(uint256).max, msg.sender);
    }

    function testMintFirstDepositAttack() public {
        TestUtilities.mintAndApprove(usdc, 1e20, address(strategyReserve));

        uint256 shares = strategyReserve.deposit(1, msg.sender);
        assertEq(shares, 1);
        usdc.transfer(address(strategyReserve), 1e5);

        uint256 received = strategyReserve.mint(1, msg.sender);
        assertEq(received, 1);

        vm.prank(msg.sender);
        uint256 assets = strategyReserve.redeem(1, msg.sender, msg.sender);
        assertEq(assets, 1);

        // receive again
        vm.prank(msg.sender);
        uint256 assets2 = strategyReserve.redeem(1, msg.sender, msg.sender);
        assertEq(assets2, 1);
    }

    // ============ Withdraw Tests ============

    function testWithdrawWhenPaused() public {
        _createLender(0, 100, 100);
        _addCollateral(0, 100);
        _borrow(0, 100);

        strategyController.pause();

        vm.prank(msg.sender);
        _expectRevert(Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED);
        strategyReserve.withdraw(100, msg.sender, msg.sender);
    }

    function testWithdrawBeyondUnutilized() public {
        _createLender(0, 100, 100);
        _addCollateral(0, 100);
        _borrow(0, 100);

        vm.expectRevert();
        vm.prank(msg.sender);
        strategyReserve.withdraw(1, msg.sender, msg.sender);
    }

    function testWithdraw() public {
        _createLender(0, 100, 100);
        _addCollateral(0, 100);

        vm.prank(msg.sender);
        strategyReserve.withdraw(1, msg.sender, msg.sender);
    }

    // ============ Redeem Tests ============

    function testRedeemWhenPaused() public {
        _createLender(0, 100, 100);
        _addCollateral(0, 100);
        _borrow(0, 100);

        strategyController.pause();

        vm.prank(msg.sender);
        _expectRevert(Errors.CANNOT_CALL_FUNCTION_WHEN_PAUSED);
        strategyReserve.redeem(100, msg.sender, msg.sender);
    }

    function testRedeemBeyondUnutilized() public {
        _createLender(0, 100, 100);
        _addCollateral(0, 100);
        _borrow(0, 100);

        vm.expectRevert();
        vm.prank(msg.sender);
        strategyReserve.redeem(1, msg.sender, msg.sender);
    }

    function testRedeem() public {
        _createLender(0, 100, 100);
        _addCollateral(0, 100);

        vm.prank(msg.sender);
        strategyReserve.redeem(1, msg.sender, msg.sender);
    }

    function testRedeemAfterSevereLoss() public {
        TestUtilities.mintAndApprove(usdc, 1e20, address(strategyReserve));

        uint256 shares = strategyReserve.deposit(1e10, msg.sender);
        assertEq(shares, 1e10);

        _addCollateral(0, 4.5e9);
        _borrow(0, 9e9);
        _simulateProfitOrLoss(strategyAccounts[0], 9e9, false);
        strategyAccounts[0].executeInitiateLiquidation();
        strategyAccounts[0].executeProcessLiquidation();

        uint256 shares2 = strategyReserve.deposit(1000, msg.sender);
        assertEq(shares2, 1818);

        vm.prank(msg.sender);
        uint256 assets = strategyReserve.redeem(1e10, msg.sender, msg.sender);
        assertEq(assets, 5.5e9);

        vm.prank(address(strategyReserve.STRATEGY_BANK()));
        (
            uint256 interestOwed,
            uint256 cumulativeInterestIndex
        ) = strategyReserve.settleInterest(5e7, 0);
        assertEq(cumulativeInterestIndex, 0);
        assertEq(interestOwed, 0);

        vm.prank(msg.sender);
        assets = strategyReserve.redeem(1817, msg.sender, msg.sender);
        assertEq(assets, 999);
    }

    function testRedeemAfterInterest() public {
        TestUtilities.mintAndApprove(usdc, 1e20, address(strategyReserve));

        uint256 shares = strategyReserve.deposit(1e10, msg.sender);
        assertEq(shares, 1e10);

        _addCollateral(0, 4.5e9);
        _borrow(0, 9e9);

        vm.warp(365 days);

        vm.prank(address(strategyAccounts[0]));
        uint256 loanNow = strategyBanks[0].repayLoan(9e9, 9e9);
        assertEq(loanNow, 0);

        uint256 shares2 = strategyReserve.deposit(1000, msg.sender);
        assertEq(shares2, 866);

        vm.prank(msg.sender);
        uint256 assets = strategyReserve.redeem(1e10, msg.sender, msg.sender);
        assertEq(assets, 11538999952);

        vm.prank(msg.sender);
        assets = strategyReserve.redeem(866, msg.sender, msg.sender);
        assertEq(assets, 999);
    }

    function testRedeemAfterSevereLossAndProfit() public {
        TestUtilities.mintAndApprove(usdc, 1e20, address(strategyReserve));

        uint256 shares = strategyReserve.deposit(1e10, msg.sender);
        assertEq(shares, 1e10);

        _addCollateral(0, 4.5e9);
        _borrow(0, 9e9);
        _simulateProfitOrLoss(strategyAccounts[0], 9e9, false);
        strategyAccounts[0].executeInitiateLiquidation();
        strategyAccounts[0].executeProcessLiquidation();

        uint256 shares2 = strategyReserve.deposit(1000, msg.sender);
        assertEq(shares2, 1818);

        _addCollateral(0, 10e9);
        _borrow(0, 4.5e9);

        vm.warp(365 days);

        vm.prank(address(strategyBanks[0]));
        strategyReserve.repay(4.5e9, 4.5e9);

        // Does nothing.
        usdc.mint(address(strategyReserve), 9e9);

        vm.prank(msg.sender);
        uint256 assets = strategyReserve.redeem(1e10, msg.sender, msg.sender);
        assertEq(assets, 6199545179);

        vm.prank(msg.sender);
        assets = strategyReserve.redeem(1817, msg.sender, msg.sender);
        assertEq(assets, 1126);
    }

    function testFuzzRedeemOrWithdraw(uint256 loan) public {
        vm.assume(loan <= 1e18);

        TestUtilities.mintAndApprove(usdc, loan, address(strategyReserve));

        uint256 shares = strategyReserve.deposit(loan, msg.sender);
        assertEq(shares, loan);

        assertEq(strategyReserve.previewWithdraw(loan), shares);
        assertEq(strategyReserve.previewRedeem(shares), loan);
    }

    // ============ Total Assets Tests ============

    function testTotalAssets() public {
        // No assets.
        assertEq(strategyReserve.totalAssets(), 0);

        // A lender.
        _createLender(0, 100, 100);
        assertEq(strategyReserve.totalAssets(), 100);

        // A borrower.
        _addCollateral(0, 100);
        _borrow(0, 100);
        assertEq(strategyReserve.totalAssets(), 100);

        // Increase loan.
        _increasePosition(0, 100, 100);
        assertEq(strategyReserve.totalAssets(), 200);

        // Donate.
        usdc.mint(address(strategyReserve), 1e10);

        _increasePosition(0, 1e10, 1e10);
        assertEq(strategyReserve.totalAssets(), 1e10 + 200);
    }

    // ============ Max Deposit Tests ============

    function testMaxDeposit() public {
        TestUtilities.mintAndApprove(usdc, 1e30, address(strategyReserve));

        // No assets.
        assertEq(strategyReserve.maxDeposit(msg.sender), 1e18);

        // A lender.
        _createLender(0, 100, 100);
        assertEq(strategyReserve.maxDeposit(msg.sender), 1e18 - 100);

        // A borrower.
        _addCollateral(0, 100);
        _borrow(0, 100);
        assertEq(strategyReserve.maxDeposit(msg.sender), 1e18 - 100);

        // Increase loan.
        _increasePosition(0, 100, 100);
        assertEq(strategyReserve.maxDeposit(msg.sender), 1e18 - 200);

        // Donate.
        usdc.mint(address(strategyReserve), 1e10);
        assertEq(strategyReserve.maxDeposit(msg.sender), 1e18 - 200);

        _increasePosition(0, 1e10, 1e10);
        assertEq(strategyReserve.maxDeposit(msg.sender), 1e18 - (1e10 + 200));

        // Lend max.
        strategyReserve.deposit(1e18 - (1e10 + 200), msg.sender);
        assertEq(strategyReserve.maxDeposit(msg.sender), 0);

        vm.expectRevert();
        strategyReserve.deposit(1e20, msg.sender);
    }

    // ============ Max Mint Tests ============

    function testMaxMint() public {
        TestUtilities.mintAndApprove(usdc, 1e30, address(strategyReserve));

        // No assets.
        assertEq(strategyReserve.maxMint(msg.sender), 1e18);

        // A lender.
        _createLender(0, 100, 100);
        assertEq(strategyReserve.maxMint(msg.sender), 1e18 - 100);

        // A borrower.
        _addCollateral(0, 100);
        _borrow(0, 100);
        assertEq(strategyReserve.maxMint(msg.sender), 1e18 - 100);

        // Increase loan.
        _increasePosition(0, 100, 100);
        assertEq(strategyReserve.maxMint(msg.sender), 1e18 - 200);

        // Donate.
        usdc.mint(address(strategyReserve), 1e10);

        _increasePosition(0, 1e10, 1e10);
        assertEq(strategyReserve.maxMint(msg.sender), 1e18 - (1e10 + 200));

        strategyReserve.deposit(1e18 - (1e10 + 200), msg.sender);
        assertEq(strategyReserve.maxMint(msg.sender), 0);
    }

    // ============ Max Withdraw Tests ============

    function testMaxWithdraw() public {
        TestUtilities.mintAndApprove(usdc, 1e30, address(strategyReserve));

        // No assets.
        assertEq(strategyReserve.maxWithdraw(msg.sender), 0);

        // A lender.
        _createLender(0, 100, 100);
        assertEq(strategyReserve.maxWithdraw(msg.sender), 100);

        // A borrower.
        _addCollateral(0, 100);
        _borrow(0, 100);
        assertEq(strategyReserve.maxWithdraw(msg.sender), 0);

        // New loan.
        TestUtilities.mintAndApprove(usdc, 200, address(strategyReserve));
        strategyReserve.deposit(200, address(this));
        assertEq(strategyReserve.maxWithdraw(msg.sender), 100);

        // Donate.
        usdc.mint(address(strategyReserve), 1e10);
        assertEq(strategyReserve.maxWithdraw(msg.sender), 100);

        _increasePosition(0, 1e10, 1e10);
        assertEq(strategyReserve.maxWithdraw(msg.sender), 1e10 + 100);

        // Donate in excess of TVL allowed.
        strategyReserve.deposit(1e18 - (1e10 + 300), msg.sender);
        assertEq(strategyReserve.maxWithdraw(msg.sender), 1e18 - 200);
    }

    // ============ Max Redeem Tests ============

    function testMaxRedeem() public {
        // No assets.
        assertEq(strategyReserve.maxDeposit(msg.sender), 1e18);

        // A lender.
        _createLender(0, 100, 100);
        assertEq(strategyReserve.maxRedeem(msg.sender), 100);

        // A borrower.
        _addCollateral(0, 100);
        _borrow(0, 100);
        assertEq(strategyReserve.maxRedeem(msg.sender), 0);

        // New loan.
        TestUtilities.mintAndApprove(usdc, 200, address(strategyReserve));
        strategyReserve.deposit(200, address(this));
        assertEq(strategyReserve.maxRedeem(msg.sender), 100);

        // Donate.
        usdc.mint(address(strategyReserve), 1e10);
        assertEq(strategyReserve.maxRedeem(msg.sender), 100);

        // Donate in excess of TVL allowed.
        usdc.mint(address(strategyReserve), 1e20);
        assertEq(strategyReserve.maxRedeem(msg.sender), 100);
    }

    // ============ Interest Tests ============

    function testSendInterest() public {
        uint256 depositAmount = 1e8;
        usdc.mint(address(this), depositAmount);

        usdc.approve(address(strategyReserve), type(uint256).max);

        uint256 shares = strategyReserve.deposit(depositAmount, address(this));
        assertEq(shares, depositAmount);

        // Does nothing.
        usdc.mint(address(this), 1e8);

        _addCollateral(0, depositAmount * 2);
        _borrow(0, depositAmount);

        vm.warp(365 days);

        vm.prank(address(strategyBanks[0]));
        strategyReserve.repay(depositAmount, depositAmount);

        vm.prank(address(strategyReserve.STRATEGY_BANK()));
        strategyReserve.settleInterest(0, 0);

        assertEq(strategyReserve.maxWithdraw(address(this)), 118999999);
        assertEq(strategyReserve.maxRedeem(address(this)), 1e8);
    }

    // ============ Loss Tests ============

    function testLoss() public {
        uint256 depositAmount = 1e8;
        usdc.mint(address(this), depositAmount);

        usdc.approve(address(strategyReserve), type(uint256).max);

        uint256 shares = strategyReserve.deposit(depositAmount, address(this));
        assertEq(shares, depositAmount);

        _addCollateral(0, 2.5e7);
        _borrow(0, 5e7); // optimal utilization

        vm.expectEmit(true, true, true, true, address(strategyReserve));
        emit Repay(5e7, 2.5e7);

        vm.prank(address(strategyBanks[0]));
        strategyReserve.repay(5e7, 2.5e7);

        // Perhaps something we want to look at, this returns 1e8 - 1 (they minted 1e8)
        // because of rounding in the calculation of the available shares.
        assertEq(strategyReserve.utilizedAssets_(), 0);
        assertEq(strategyReserve.maxRedeem(address(this)), 1e8 - 1);
        assertEq(strategyReserve.maxWithdraw(address(this)), 7.5e7);
    }

    // ============ Get Next Cumulative Interest Index Tests ============

    function testSettleInterestViewNoAssets() public {
        (uint256 interestOwed, uint256 interestIndexNow) = strategyReserve
            .settleInterestView(0, 0);
        assertEq(interestOwed, 0);
        assertEq(interestIndexNow, 0);
    }

    function testSettleInterestViewNoAssetsAndTimePasses() public {
        vm.warp(50 days);

        (uint256 interestOwed, uint256 interestIndexNow) = strategyReserve
            .settleInterestView(0, 0);
        assertEq(interestOwed, 0);
        assertEq(interestIndexNow, 0);
    }

    function testSettleInterestViewNoBorrowedAssetsAndTimePasses() public {
        _createLender(0, 50, 50);

        vm.warp(50 days);

        (uint256 interestOwed, uint256 interestIndexNow) = strategyReserve
            .settleInterestView(0, 0);
        assertEq(interestOwed, 0);
        assertEq(interestIndexNow, 0);
    }

    function testSettleInterestViewNoTime() public {
        _createLender(0, 1e8, 1e8);

        vm.warp(100 days);

        uint256 borrowAmount = 5e7;
        _addCollateral(0, borrowAmount);
        _borrow(0, borrowAmount); // optimal utilization

        (uint256 interestOwed, uint256 interestIndexNow) = strategyReserve
            .settleInterestView(borrowAmount, 0);
        assertEq(interestOwed, 0);
        assertEq(interestIndexNow, 0);
    }

    function testSettleInterestView() public {
        _createLender(0, 1e8, 1e8);

        uint256 borrowAmount = 5e7;
        _addCollateral(0, borrowAmount);
        _borrow(0, borrowAmount); // optimal utilization

        vm.warp(100 days);

        (uint256 interestOwed, uint256 interestIndexNow) = strategyReserve
            .settleInterestView(borrowAmount, 0);
        assertEq(interestOwed, 1369863);
        assertEq(interestIndexNow, 27397257102993404);
    }

    function testSettleInterestViewAndDonation() public {
        _createLender(0, 1e8, 1e8);

        usdc.mint(address(strategyReserve), 1e8);

        uint256 borrowAmount = 5e7;
        _addCollateral(0, borrowAmount);
        _borrow(0, borrowAmount); // optimal utilization

        vm.warp(100 days);

        (uint256 interestOwed, uint256 interestIndexNow) = strategyReserve
            .settleInterestView(borrowAmount, 0);
        assertEq(interestOwed, 1369863);
        assertEq(interestIndexNow, 27397257102993404);
    }
}
