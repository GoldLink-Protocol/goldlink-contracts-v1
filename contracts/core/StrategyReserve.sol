// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ERC20,
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    ERC4626
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { GoldLinkOwnable } from "../utils/GoldLinkOwnable.sol";
import { InterestRateModel } from "./InterestRateModel.sol";
import { StrategyBank } from "./StrategyBank.sol";
import { IStrategyBank } from "../interfaces/IStrategyBank.sol";
import { IStrategyReserve } from "../interfaces/IStrategyReserve.sol";
import { Errors } from "../libraries/Errors.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Constants } from "../libraries/Constants.sol";
import { ControllerHelpers } from "./ControllerHelpers.sol";
import { IStrategyController } from "../interfaces/IStrategyController.sol";

/**
 * @title StrategyReserve
 * @author GoldLink
 *
 * @notice Manages all lender actions and state for a single strategy.
 */
contract StrategyReserve is
    IStrategyReserve,
    GoldLinkOwnable,
    ERC4626,
    InterestRateModel,
    ControllerHelpers
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============ Constants ============

    /// @notice The strategy bank permissioned to borrow from the reserve.
    IStrategyBank public immutable STRATEGY_BANK;

    /// @notice The asset used for lending in this strategy.
    IERC20 public immutable STRATEGY_ASSET;

    // ============ Storage Variables ============

    /// @notice The net balance of borrowed assets, utilized in active loans.
    uint256 public utilizedAssets_;

    /// @notice The maximum TVL (total value locked), limiting the total net
    /// funds deposited in the reserve.
    ///
    /// Is is possible for the ERC-20 balance or reserveBalance_ to exceed this
    /// in some cases, such as due to received interest. In this case, borrows
    /// will still be limited to prevent utilizedAssets_ exceeding tvlCap_.
    uint256 public tvlCap_;

    /// @notice The asset balance of the contract. Extraneous ERC-20 transfers
    /// not made through function calls on the reserve are excluded and ignored.
    uint256 public reserveBalance_;

    // ============ Modifiers ============

    /// @dev Require address is not zero.
    modifier onlyNonZeroAddress(address addressToCheck) {
        require(
            addressToCheck != address(0),
            Errors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );
        _;
    }

    /// @dev Only callable by the strategy bank.
    modifier onlyStrategyBank() {
        require(
            msg.sender == address(STRATEGY_BANK),
            Errors.STRATEGY_RESERVE_CALLER_MUST_BE_THE_STRATEGY_BANK
        );
        _;
    }

    /// @dev Sync balance and accrue interest before executing a function.
    ///
    /// The interest rate is a function of utilization, so the cumulative
    /// interest must be settled before any transaction that affects
    /// utilization.
    modifier syncAndAccrue() {
        // Get the used and total asset amounts.
        uint256 used = utilizedAssets_;
        uint256 total = used + reserveBalance_; // equal to totalAssets()

        // Settle interest that has accrued since the last settlement,
        // and get the new amount owed on the utilized asset balance.
        uint256 interestOwed = _accrueInterest(used, total);

        // Take interest from `StrategyBank`.
        //
        // Note that in rare cases it is possible for the bank to underpay,
        // if it has insufficient collateral available to satisfy the payment.
        // In this case, the reserve will simply receive less interest than
        // expected.
        uint256 interestToPay = STRATEGY_BANK.getInterestAndTakeInsurance(
            interestOwed
        );

        // Update reserve balance with interest to be paid.
        reserveBalance_ += interestToPay;

        // Transfer interest from the strategy bank. We use the amount
        // returned by getInterestAndTakeInsurance() which is guaranteed to
        // be less than or equal to the bank's ERC-20 asset balance.
        if (interestToPay > 0) {
            STRATEGY_ASSET.safeTransferFrom(
                address(STRATEGY_BANK),
                address(this),
                interestToPay
            );
        }

        // Run the function.
        _;
    }

    // ============ Constructor ============

    constructor(
        address strategyOwner,
        IERC20 strategyAsset,
        IStrategyController strategyController,
        IStrategyReserve.ReserveParameters memory reserveParameters,
        IStrategyBank.BankParameters memory bankParameters
    )
        Ownable(strategyOwner)
        onlyNonZeroAddress(address(strategyAsset))
        ERC20(reserveParameters.erc20Name, reserveParameters.erc20Symbol)
        ERC4626(strategyAsset)
        ControllerHelpers(strategyController)
        InterestRateModel(reserveParameters.interestRateModel)
    {
        // Verify `strategyAsset` has decimals.
        require(
            _checkHasDecimals(strategyAsset),
            Errors
                .STRATEGY_RESERVE_STRATEGY_ASSET_DOES_NOT_HAVE_ASSET_DECIMALS_SET
        );

        STRATEGY_ASSET = strategyAsset;

        // Create the strategy bank.
        STRATEGY_BANK = new StrategyBank(
            strategyOwner,
            strategyAsset,
            strategyController,
            this,
            bankParameters
        );

        // Set TVL cap for this reserve.
        tvlCap_ = reserveParameters.totalValueLockedCap;
    }

    // ============ External Functions ============

    /**
     * @notice Updates the total value locked cap for `reserveId`.
     * @dev Emits the `TotalValueLockedCapUpdated()` event.
     * @param newTotalValueLockedCap The new TVL cap to enforce. Will not effect preexisting positions.
     */
    function updateReserveTVLCap(
        uint256 newTotalValueLockedCap
    ) external override onlyOwner {
        // Set new TVL cap.
        tvlCap_ = newTotalValueLockedCap;

        emit TotalValueLockedCapUpdated(newTotalValueLockedCap);
    }

    /**
     * @notice Update the model for the interest rate.
     * @dev Syncs interest model, updating interest owed and then sets the new model. Therefore,
     * no borrower is penalized retroactively for a new interest rate model.
     * @param model The new model for the interest rate.
     */
    function updateModel(
        InterestRateModelParameters calldata model
    ) external onlyOwner syncAndAccrue {
        _updateModel(model);
    }

    /**
     * @notice Borrow assets from the reserve pool.
     * Only callable by the strategy bank.
     * @dev Emits the `BorrowAssets()` event.
     * @param borrower     The account borrowing funds from this reserve.
     * @param borrowAmount The amount of assets that have been borrowed and are
     * now utilized.
     */
    function borrowAssets(
        address borrower,
        uint256 borrowAmount
    ) external override onlyStrategyBank syncAndAccrue {
        // Verify that the amount is available to be borrowed.
        require(
            availableToBorrow() >= borrowAmount,
            Errors.STRATEGY_RESERVE_INSUFFICIENT_AVAILABLE_TO_BORROW
        );

        // Increase utilized assets and decrease reserve balance.
        utilizedAssets_ += borrowAmount;
        reserveBalance_ -= borrowAmount;

        // Transfer borrowed assets to the borrower.
        if (borrowAmount > 0) {
            STRATEGY_ASSET.safeTransfer(borrower, borrowAmount);
        }

        emit BorrowAssets(borrowAmount);
    }

    /**
     * @notice Deduct `initialLoan` from the utilized balance while receiving
     * asset amount `returnedLoan` from the strategy bank. If the returned
     * amount is less, the difference represents a loss in the borrower's
     * position that will not be repaid and will be assumed by the lenders.
     * @dev Emits the `Repay()` event.
     * @param initialLoan  Assets previously borrowed that are no longer utilized.
     * @param returnedLoan Loan assets that are being returned, net of loan loss.
     */
    function repay(
        uint256 initialLoan,
        uint256 returnedLoan
    ) external onlyStrategyBank syncAndAccrue {
        // Reduce utilized assets by assets no longer borrowed and increase
        // reserve balance by the amount being returned, net of loan loss.
        utilizedAssets_ -= initialLoan;
        reserveBalance_ += returnedLoan;

        // Effectuate the transfer of the returned amount.
        if (returnedLoan > 0) {
            STRATEGY_ASSET.safeTransferFrom(
                address(STRATEGY_BANK),
                address(this),
                returnedLoan
            );
        }

        emit Repay(initialLoan, returnedLoan);
    }

    /**
     * @notice Settle global lender interest and calculate new interest owed
     * by a borrower, given their previous loan amount and cached index.
     * @param loanBefore        The loan's value before any state updates have been made.
     * @param interestIndexLast The last interest index corresponding to the borrower's loan.
     * @return interestOwed     The interest owed since the last time the borrow updated their position.
     * @return interestIndexNow The current interest index corresponding to the borrower's loan.
     */
    function settleInterest(
        uint256 loanBefore,
        uint256 interestIndexLast
    )
        external
        override
        onlyStrategyBank
        syncAndAccrue
        returns (uint256 interestOwed, uint256 interestIndexNow)
    {
        // Get the current interest index.
        interestIndexNow = cumulativeInterestIndex();

        // Calculate the interest owed since the last time the borrower's
        // interest was settled.
        interestOwed = _calculateInterestOwed(
            loanBefore,
            interestIndexLast,
            interestIndexNow
        );

        return (interestOwed, interestIndexNow);
    }

    /**
     * @notice Calculate new interest owed by a borrower, given their previous
     * loan amount and cached index. Does not modify state.
     * @param loanBefore        The loan's value before any state updates have been made.
     * @param interestIndexLast The last interest index corresponding to the borrower's loan.
     * @return interestOwed     The interest owed since the last time the borrow updated their position.
     * @return interestIndexNow The current interest index corresponding to the borrower's loan.
     */
    function settleInterestView(
        uint256 loanBefore,
        uint256 interestIndexLast
    ) external view returns (uint256 interestOwed, uint256 interestIndexNow) {
        // Calculate the updated cumulative interest index (without updating storage).
        interestIndexNow = _getNextCumulativeInterestIndex(
            utilizedAssets_,
            totalAssets()
        );

        // Calculate the interest owed since the last time the borrower's
        // interest was settled.
        interestOwed = _calculateInterestOwed(
            loanBefore,
            interestIndexLast,
            interestIndexNow
        );

        return (interestOwed, interestIndexNow);
    }

    // ============ Public Functions ============

    /**
     * @notice Implements deposit, adding funds to the reserve and receiving LP tokens in return.
     * @dev Emits the `Deposit()` event via `_deposit`.
     * @param assets   The assets deposited into the reserve to be lent out to borrowers.
     * @param receiver The address receiving shares.
     * @return shares  The shares minted for the assets deposited.
     */
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        override(ERC4626, IERC4626)
        whenNotPaused
        strategyNonReentrant
        syncAndAccrue
        returns (uint256 shares)
    {
        shares = super.deposit(assets, receiver);
        reserveBalance_ += assets;

        return shares;
    }

    /**
     * @notice Implements mint, adding funds to the reserve and receiving LP tokens in return.
     * Unlike `deposit`, specifies target shares to mint rather than assets deposited.
     * @dev Emits the `Deposit()` event via `_deposit`.
     * @param shares   The shares to mint.
     * @param receiver The address receiving shares.
     * @return assets  The assets deposited into the reserve to be lent out to borrowers.
     */
    function mint(
        uint256 shares,
        address receiver
    )
        public
        override(ERC4626, IERC4626)
        whenNotPaused
        strategyNonReentrant
        syncAndAccrue
        returns (uint256 assets)
    {
        assets = super.mint(shares, receiver);
        reserveBalance_ += assets;

        return assets;
    }

    /**
     * @notice Implements withdraw, removing assets from the reserve and burning shares worth
     * assets value.
     * @dev Emits the `Withdraw()` event via `_withdraw`.
     * @param assets   The assets being withdrawn.
     * @param receiver The address receiving withdrawn assets.
     * @param lender   The owner of the shares that will be burned. If the caller is not
     * the owner, must have a spend allowance.
     * @return shares  The shares burned.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address lender
    )
        public
        override(ERC4626, IERC4626)
        whenNotPaused
        strategyNonReentrant
        syncAndAccrue
        returns (uint256 shares)
    {
        shares = super.withdraw(assets, receiver, lender);
        reserveBalance_ -= assets;

        return shares;
    }

    /**
     * @notice Implements redeem, burning shares and receiving assets worth share value.
     * @dev Emits the `Withdraw()` event via `_withdraw`.
     * @param shares   The shares being burned.
     * @param receiver The address receiving withdrawn assets.
     * @param lender   The owner of the shares that will be burned. If the caller is not
     * the owner, must have a spend allowance.
     * @return assets  The assets received worth the shares burned.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address lender
    )
        public
        override(ERC4626, IERC4626)
        whenNotPaused
        strategyNonReentrant
        syncAndAccrue
        returns (uint256 assets)
    {
        assets = super.redeem(shares, receiver, lender);
        reserveBalance_ -= assets;

        return assets;
    }

    /**
     * @notice Implements total assets, the balance of assets in the reserve and utilized by
     * the strategy bank.
     * @return reserveTotalAssets The total assets belonging to the reserve.
     */
    function totalAssets()
        public
        view
        override(ERC4626, IERC4626)
        returns (uint256 reserveTotalAssets)
    {
        return reserveBalance_ + utilizedAssets_;
    }

    /**
     * @notice Implements max deposit, the maximum deposit viable given remaining TVL capacity.
     * @return allowedDeposit The maximum allowed deposit.
     */
    function maxDeposit(
        address
    ) public view override(ERC4626, IERC4626) returns (uint256 allowedDeposit) {
        if (isStrategyPaused()) {
            return 0;
        }
        return _remainingAssetCapacity();
    }

    /**
     * @notice Implements max mint, the maximum mint viable given remaining TVL capacity.
     * @return allowedMint The maximum allowed mint.
     */
    function maxMint(
        address
    ) public view override(ERC4626, IERC4626) returns (uint256 allowedMint) {
        if (isStrategyPaused()) {
            return 0;
        }
        return _convertToShares(_remainingAssetCapacity(), Math.Rounding.Floor);
    }

    /**
     * @notice Implements max withdraw, the maximum assets withdrawable from the reserve.
     * @param lender          The owner of the balance being withdrawn.
     * @return viableWithdraw The maximum viable withdawal.
     */
    function maxWithdraw(
        address lender
    ) public view override(ERC4626, IERC4626) returns (uint256 viableWithdraw) {
        if (isStrategyPaused()) {
            return 0;
        }

        // The lender's assets.
        uint256 ownerAssets = _convertToAssets(
            balanceOf(lender),
            Math.Rounding.Floor
        );

        // Get the available assets in the reserve to withdraw.
        uint256 contractAssetBalance = reserveBalance_;

        // Return the minimum of the owner's assets and the available withdrawable
        // assets in the reserve.
        return Math.min(ownerAssets, contractAssetBalance);
    }

    /**
     * @notice Implements max redeem, the maximum shares redeemable from the reserve.
     * @param lender            The owner of the balance being withdrawn.
     * @return viableRedemption The maximum viable redemption.
     */
    function maxRedeem(
        address lender
    )
        public
        view
        override(ERC4626, IERC4626)
        returns (uint256 viableRedemption)
    {
        if (isStrategyPaused()) {
            return 0;
        }

        // Get share value of all withdrawable assets in the reserve.
        uint256 availableToRedeem = _convertToShares(
            reserveBalance_,
            Math.Rounding.Floor
        );

        // Get lender's shares.
        uint256 ownerShares = balanceOf(lender);

        // Return the minimum of the owner's shares and the available redeemable
        // shares in the reserve.
        return Math.min(ownerShares, availableToRedeem);
    }

    /**
     * @notice The amount of assets currently available to borrow.
     * @return assets The amount of assets currently available to borrow.
     */
    function availableToBorrow() public view override returns (uint256 assets) {
        uint256 availableBalance = reserveBalance_;
        uint256 borrowedBalance = utilizedAssets_;

        // Disallow borrows that would result in the utilized balance
        // exceeding the TVL cap.
        uint256 borrowableUpToCap = tvlCap_ > borrowedBalance
            ? tvlCap_ - borrowedBalance
            : 0;
        return Math.min(availableBalance, borrowableUpToCap);
    }

    // ============ Internal Functions ============

    /**
     * @notice Implements remaining asset capacity, fetching the remaining
     * capacity in the reserve given the TVL cap.
     * @return remainingAssets Amount of assets that can still be deposited.
     */
    function _remainingAssetCapacity()
        internal
        view
        returns (uint256 remainingAssets)
    {
        // Get the total assets available in the reserve or utilized by the strategy bank.
        uint256 loanAssets = totalAssets();

        // Get the TVL cap for the strategy.
        uint256 tvlCap = tvlCap_;

        // Return assets that can still be enrolled in the strategy.
        return tvlCap > loanAssets ? tvlCap - loanAssets : 0;
    }

    // ============ Private Functions ============

    /**
     * @notice Checks if `asset` has decimals. Necessary for this `StrategyReserve` to fetch
     * vault asset decimals.
     * @param asset    The asset being checked for decimals.
     * @return success If the asset has decimals.
     */
    function _checkHasDecimals(
        IERC20 asset
    ) private view returns (bool success) {
        (success, ) = address(asset).staticcall(
            abi.encodeCall(IERC20Metadata.decimals, ())
        );
        return success;
    }
}
