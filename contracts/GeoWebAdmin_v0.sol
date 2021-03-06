// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./ERC721License.sol";
import "./GeoWebParcel.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

abstract contract GeoWebAdmin_v0 is Initializable, OwnableUpgradeable {
    using SafeMath for uint256;

    ERC721License public licenseContract;
    GeoWebParcel public parcelContract;

    uint256 public minInitialValue;
    uint256 public perSecondFeeNumerator;
    uint256 public perSecondFeeDenominator;
    uint256 public dutchAuctionLengthInSeconds;

    /// @notice licenseInfo stores admin information about licenses
    mapping(uint256 => LicenseInfo) public licenseInfo;

    struct LicenseInfo {
        uint256 value;
        uint256 expirationTimestamp;
    }

    event LicenseInfoUpdated(
        uint256 indexed _licenseId,
        uint256 value,
        uint256 expirationTimestamp
    );

    modifier onlyLicenseHolder(uint256 licenseId) {
        require(
            msg.sender == licenseContract.ownerOf(licenseId),
            "Only holder of license can call this function."
        );
        _;
    }

    function initialize(
        uint256 _minInitialValue,
        uint256 _perSecondFeeNumerator,
        uint256 _perSecondFeeDenominator,
        uint256 _dutchAuctionLengthInSeconds
    ) public initializer {
        __Ownable_init();

        minInitialValue = _minInitialValue;
        perSecondFeeNumerator = _perSecondFeeNumerator;
        perSecondFeeDenominator = _perSecondFeeDenominator;
        dutchAuctionLengthInSeconds = _dutchAuctionLengthInSeconds;
    }

    function setMinInitialValue(uint256 _minInitialValue) external onlyOwner {
        minInitialValue = _minInitialValue;
    }

    function setParcelContract(address parcelContractAddress)
        external
        onlyOwner
    {
        parcelContract = GeoWebParcel(parcelContractAddress);
    }

    function setLicenseContract(address licenseContractAddress)
        external
        onlyOwner
    {
        licenseContract = ERC721License(licenseContractAddress);
    }

    function setDutchAuctionLength(uint256 _dutchAuctionLengthInSeconds)
        external
        onlyOwner
    {
        dutchAuctionLengthInSeconds = _dutchAuctionLengthInSeconds;
    }

    function _claim(
        address _to,
        uint64 baseCoordinate,
        uint256[] memory path,
        uint256 initialValue,
        uint256 initialFeePayment,
        string memory ceramicDocId
    ) internal {
        require(
            initialValue >= minInitialValue,
            "Initial value must be >= the required minimum value"
        );

        // Check expiration date
        uint256 perSecondFee =
            initialValue.mul(perSecondFeeNumerator).div(
                perSecondFeeDenominator
            );
        uint256 expirationTimestamp =
            initialFeePayment.div(perSecondFee).add(now);

        require(
            expirationTimestamp.sub(now) >= 365 days,
            "Resulting expiration date must be at least 365 days"
        );
        require(
            expirationTimestamp.sub(now) <= 730 days,
            "Resulting expiration date must be less than or equal to 730 days"
        );

        // Transfer initial payment
        _transferFeePayment(initialFeePayment);

        // Mint parcel and license
        uint256 newParcelId =
            parcelContract.mintLandParcel(baseCoordinate, path);
        licenseContract.mintLicense(_to, newParcelId, ceramicDocId);

        // Save license info
        LicenseInfo storage l = licenseInfo[newParcelId];
        l.value = initialValue;
        l.expirationTimestamp = expirationTimestamp;

        emit LicenseInfoUpdated(newParcelId, initialValue, expirationTimestamp);
    }

    function _updateValue(
        uint256 licenseId,
        uint256 newValue,
        uint256 additionalFeePayment
    ) internal {
        _updateLicense(licenseId, newValue, additionalFeePayment);
    }

    function _purchaseLicense(
        uint256 licenseId,
        uint256 totalBuyPrice,
        uint256 newValue,
        uint256 additionalFeePayment,
        string memory ceramicDocId
    ) internal {
        // Transfer payment to seller
        _transferSellerFeeReimbursement(
            licenseContract.ownerOf(licenseId),
            totalBuyPrice
        );

        // Transfer license to buyer
        licenseContract.transferFrom(
            licenseContract.ownerOf(licenseId),
            msg.sender,
            licenseId
        );

        // Update license info
        _updateLicense(licenseId, newValue, additionalFeePayment);

        // Update docID
        licenseContract.setContent(licenseId, ceramicDocId);
    }

    function _updateLicense(
        uint256 licenseId,
        uint256 newValue,
        uint256 additionalFeePayment
    ) internal {
        require(
            newValue >= minInitialValue,
            "New value must be >= the required minimum value"
        );

        LicenseInfo storage license = licenseInfo[licenseId];

        // Update expiration date
        uint256 existingTimeBalance;
        if (license.expirationTimestamp > now) {
            existingTimeBalance = license.expirationTimestamp.sub(now);
        } else {
            existingTimeBalance = 0;
        }

        uint256 newTimeBalance =
            existingTimeBalance.mul(license.value).div(newValue);
        uint256 newPerSecondFee =
            newValue.mul(perSecondFeeNumerator).div(perSecondFeeDenominator);
        uint256 additionalPaymentTimeBalance =
            additionalFeePayment.div(newPerSecondFee);

        uint256 newExpirationTimestamp =
            newTimeBalance.add(additionalPaymentTimeBalance).add(now);

        // TODO: Increase minimum expiration
        require(
            newExpirationTimestamp.sub(now) >= 1 days,
            "Resulting expiration date must be at least 1 day"
        );

        // Max expiration of 2 years
        if (newExpirationTimestamp.sub(now) > 730 days) {
            newExpirationTimestamp = now.add(730 days);
        }

        // Transfer additional payment
        _transferFeePayment(additionalFeePayment);

        // Save license info
        license.value = newValue;
        license.expirationTimestamp = newExpirationTimestamp;

        emit LicenseInfoUpdated(licenseId, newValue, newExpirationTimestamp);
    }

    function calculateTotalBuyPrice(uint256 licenseId)
        public
        view
        returns (uint256)
    {
        LicenseInfo storage license = licenseInfo[licenseId];
        return
            _calculateTotalBuyPrice(
                license.expirationTimestamp,
                license.value,
                now
            );
    }

    function _calculateTotalBuyPrice(
        uint256 expirationTimestamp,
        uint256 value,
        uint256 currentTime
    ) public view returns (uint256) {
        if (expirationTimestamp < currentTime) {
            //  Duction auction price
            uint256 auctionTime = currentTime.sub(expirationTimestamp);

            if (auctionTime > dutchAuctionLengthInSeconds) {
                // Auction is over, parcel is free
                return 0;
            } else {
                uint256 dutchAuctionDecrease =
                    value.mul(auctionTime).div(dutchAuctionLengthInSeconds);
                return value.sub(dutchAuctionDecrease);
            }
        } else {
            // Normal buy price
            uint256 existingTimeBalance = expirationTimestamp.sub(currentTime);
            uint256 perSecondFee =
                value.mul(perSecondFeeNumerator).div(perSecondFeeDenominator);
            uint256 existingFeeBalance = existingTimeBalance.mul(perSecondFee);

            uint256 totalBuyPrice = value.add(existingFeeBalance);

            return totalBuyPrice;
        }
    }

    function _transferFeePayment(uint256 amount) internal virtual;

    function _transferSellerFeeReimbursement(address seller, uint256 amount)
        internal
        virtual;
}
