// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TipWithCause
 * @author Kostas
 * @notice A contract that facilitates tipping content creators while routing a
 *         configurable portion of each tip to a sponsored cause. The list of
 *         sponsored causes is supplied at deployment and kept private.
 *
 *         Key features
 *         -------------
 *         • Method overloading (`tip`) provides two ways to send tips:
 *           1. Implicit 10% donation (creator & sponsor index).
 *           2. Explicit donation amount (creator, sponsor index, donation).
 *         • Contract‐wide tally of total tips (in wei).
 *         • Tracking of the single highest tip and its sender (owner‑only view).
 *         • Emission of `TipReceived` event on every successful tip.
 *         • Owner‑only ability to (de)activate the contract (graceful shutdown).
 */
contract TipWithCause {
    // ---------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------
    address public immutable owner;           // Deployer / contract owner.
    address[] private sponsoredCauses;        // Hidden list of causes.

    uint256 public totalTipped;               // Aggregate tips (wei).
    address private highestTipper;            // Top tipper address.
    uint256 private highestTipAmount;         // Top tip amount (wei).

    bool public active;                       // Global switch.

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    /**
     * @dev Emitted on every successful tip.
     * @param tipper        Address that sent the tip.
     * @param creator       Destination content‑creator address.
     * @param tipAmount     Total amount sent (wei).
     * @param donation      Portion forwarded to the sponsored cause (wei).
     * @param sponsorIndex  Index of the sponsored cause chosen.
     */
    event TipReceived(
        address indexed tipper,
        address indexed creator,
        uint256 tipAmount,
        uint256 donation,
        uint256 sponsorIndex
    );

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "TipWithCause: caller is not the owner");
        _;
    }

    modifier whenActive() {
        require(active, "TipWithCause: contract is not active");
        _;
    }

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------
    /**
     * @param _causes Addresses of the sponsored causes.
     */
    constructor(address[] memory _causes) {
        require(_causes.length > 0, "TipWithCause: at least one cause required");
        owner = msg.sender;
        sponsoredCauses = _causes;
        active = true;
    }

    // ---------------------------------------------------------------------
    // Public Interface — Tipping (method overloading)
    // ---------------------------------------------------------------------
    /**
     * @notice Tip a creator. 10% of `msg.value` is automatically donated.
     * @param creator      Destination content‑creator address.
     * @param sponsorIndex Index of the chosen sponsored cause.
     */
    function tip(address creator, uint256 sponsorIndex)
        external
        payable
        whenActive
    {
        uint256 donation = msg.value / 10; // 10% donation.
        _processTip(creator, sponsorIndex, donation);
    }

    /**
     * @notice Tip a creator and specify the exact donation amount.
     * @dev    Donation must be 1–50 % of `msg.value`.
     * @param creator          Destination content‑creator address.
     * @param sponsorIndex     Index of the chosen sponsored cause.
     * @param donationAmountWei Donation amount in wei.
     */
    function tip(
        address creator,
        uint256 sponsorIndex,
        uint256 donationAmountWei
    ) external payable whenActive {
        uint256 minDonation = msg.value / 100; // 1 % of total.
        uint256 maxDonation = msg.value / 2;   // 50 % of total.
        require(
            donationAmountWei >= minDonation && donationAmountWei <= maxDonation,
            "TipWithCause: donation outside allowed range"
        );
        _processTip(creator, sponsorIndex, donationAmountWei);
    }

    // ---------------------------------------------------------------------
    // View Functions
    // ---------------------------------------------------------------------
    /**
     * @notice Returns the address and amount of the highest tip. Owner‑only.
     */
    function getHighestTip()
        external
        view
        onlyOwner
        returns (address tipper, uint256 amount)
    {
        return (highestTipper, highestTipAmount);
    }

    /**
     * @notice Returns the cumulative amount tipped through this contract.
     */
    function getTotalTipped() external view returns (uint256) {
        return totalTipped;
    }

    /**
     * @notice Returns how many sponsored causes were supplied at deployment.
     */
    function getCausesCount() external view returns (uint256) {
        return sponsoredCauses.length;
    }

    // ---------------------------------------------------------------------
    // Admin (owner‑only)
    // ---------------------------------------------------------------------
    /**
     * @notice Disables all tipping functionality.
     */
    function deactivate() external onlyOwner {
        active = false;
    }

    /**
     * @notice Re‑enables tipping after a deactivation.
     */
    function activate() external onlyOwner {
        active = true;
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------
    function _processTip(
        address creator,
        uint256 sponsorIndex,
        uint256 donation
    ) internal {
        require(msg.value > 0, "TipWithCause: zero ether sent");
        require(
            sponsorIndex < sponsoredCauses.length,
            "TipWithCause: invalid sponsor index"
        );
        address sponsor = sponsoredCauses[sponsorIndex];

        uint256 creatorAmount = msg.value - donation;

        // Transfer funds (use `call` for gas‑stipend safety).
        (bool sentSponsor, ) = payable(sponsor).call{value: donation}("");
        require(sentSponsor, "TipWithCause: sponsor transfer failed");

        (bool sentCreator, ) = payable(creator).call{value: creatorAmount}("");
        require(sentCreator, "TipWithCause: creator transfer failed");

        // Statistics.
        totalTipped += msg.value;
        if (msg.value > highestTipAmount) {
            highestTipAmount = msg.value;
            highestTipper = msg.sender;
        }

        emit TipReceived(msg.sender, creator, msg.value, donation, sponsorIndex);
    }

    // ---------------------------------------------------------------------
    // Fallbacks
    // ---------------------------------------------------------------------
    /**
     * @dev Reverts unsolicited ether transfers.
     */
    receive() external payable {
        revert("TipWithCause: direct deposits disallowed");
    }

    fallback() external payable {
        revert("TipWithCause: invalid call");
    }
}
