// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.20;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IInterestRateModel } from "./IInterestRateModel.sol";
import { IStrategyBank } from "./IStrategyBank.sol";

/**
 * @title IStrategyReserve
 * @author GoldLink
 *
 * @dev Interface for the strategy reserve, GoldLink custom ERC4626.
 */
interface IStrategyReserve is IERC4626, IInterestRateModel {
    // ============ Structs ============

    // @dev Parameters for the reserve to create.
    struct ReserveParameters {
        // The maximum total value allowed in the reserve to be lent.
        uint256 totalValueLockedCap;
        // The reserve's interest rate model.
        InterestRateModelParameters interestRateModel;
        // The name of the ERC20 minted by this vault.
        string erc20Name;
        // The symbol for the ERC20 minted by this vault.
        string erc20Symbol;
    }

    // ============ Events ============

    /// @notice Emitted when the TVL cap is updated. This the maximum
    /// capital lenders can deposit in the reserve.
    /// @param newTotalValueLockedCap The new TVL cap for the reserve.
    event TotalValueLockedCapUpdated(uint256 newTotalValueLockedCap);

    /// @notice Emitted when the balance of the `StrategyReserve` is synced.
    /// @param newBalance The new balance of the reserve after syncing.
    event BalanceSynced(uint256 newBalance);

    /// @notice Emitted when assets are borrowed from the reserve.
    /// @param borrowAmount The amount of assets borrowed by the strategy bank.
    event BorrowAssets(uint256 borrowAmount);

    /// @notice Emitted when assets are repaid to the reserve.
    /// @param initialLoan  The repay amount expected from the strategy bank.
    /// @param returnedLoan The repay amount provided by the strategy bank.
    event Repay(uint256 initialLoan, uint256 returnedLoan);

    // ============ External Functions ============

    /// @dev Update the reserve TVL cap, modifying how many assets can be lent.
    function updateReserveTVLCap(uint256 newTotalValueLockedCap) external;

    /// @dev Borrow assets from the reserve.
    function borrowAssets(
        address strategyAccount,
        uint256 borrowAmount
    ) external;

    /// @dev Register that borrowed funds were repaid.
    function repay(uint256 initialLoan, uint256 returnedLoan) external;

    /// @dev Settle global lender interest and calculate new interest owed
    ///  by a borrower, given their previous loan amount and cached index.
    function settleInterest(
        uint256 loanBefore,
        uint256 interestIndexLast
    ) external returns (uint256 interestOwed, uint256 interestIndexNow);

    /// @dev The strategy bank that can borrow form this reserve.
    function STRATEGY_BANK() external view returns (IStrategyBank strategyBank);

    /// @dev Get the TVL cap for the `StrategyReserve`.
    function tvlCap_() external view returns (uint256 totalValueLockedCap);

    /// @dev Get the utilized assets in the `StrategyReserve`.
    function utilizedAssets_() external view returns (uint256 utilizedAssets);

    /// @dev Calculate new interest owed by a borrower, given their previous
    ///  loan amount and cached index. Does not modify state.
    function settleInterestView(
        uint256 loanBefore,
        uint256 interestIndexLast
    ) external view returns (uint256 interestOwed, uint256 interestIndexNow);

    /// @dev The amount of assets currently available to borrow.
    function availableToBorrow() external view returns (uint256 assets);
}
