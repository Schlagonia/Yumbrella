// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IOracle} from "./interfaces/IOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";
import {TokenizedStaker, ERC20, SafeERC20} from "./TokenizedStaker.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";

interface IValtCorrected {
    function FACTORY() external view returns (address);
}

// Can kick auction in `tend` and refund in `report` OR kick in `report` and dont allow withdraws till auction is over and recall report.

/// @notice You can farm under my Yumbrella
contract Yumbrella is TokenizedStaker {
    using SafeERC20 for ERC20;

    struct WithdrawRequest {
        uint256 amount;
        uint256 timestamp;
    }

    struct UserInfo {
        uint256 lastDepositTimestamp;
        WithdrawRequest withdrawRequest;
    }

    uint256 public constant WAD = 1e18;

    IVault public immutable SENIOR_VAULT;

    ERC20 public immutable SENIOR_ASSET;

    IVaultFactory internal immutable VAULT_FACTORY;

    address public auction;

    IOracle public assetToSeniorOracle;

    uint256 public withdrawCooldown;

    uint256 public performanceFee;

    uint256 public collateralRatio;

    mapping(address => UserInfo) public userInfo;

    constructor(
        address _asset,
        string memory _name,
        address _seniorVault,
        address _assetToSeniorOracle
    ) TokenizedStaker(_seniorVault, _asset, _name) {
        SENIOR_VAULT = IVault(_seniorVault);
        SENIOR_ASSET = ERC20(SENIOR_VAULT.asset());
        VAULT_FACTORY = IVaultFactory(IValtCorrected(_seniorVault).FACTORY());
        assetToSeniorOracle = IOracle(_assetToSeniorOracle);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _amount) internal override {}

    function _postDepositHook(
        uint256 assets,
        uint256 shares,
        address receiver
    ) internal virtual override {
        super._postDepositHook(assets, shares, receiver);
        userInfo[receiver].lastDepositTimestamp = block.timestamp;
    }

    function _freeFunds(uint256 _amount) internal override {}

    function _postWithdrawHook(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) internal virtual override {
        super._postWithdrawHook(assets, shares, receiver, owner, maxLoss);
        userInfo[owner].withdrawRequest.amount -= assets;
    }

    /*//////////////////////////////////////////////////////////////
                    VAULT CALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function available_deposit_limit(address _receiver)
        external
        view
        returns (uint256)
    {
        uint256 currentAssets = SENIOR_VAULT.totalAssets();
        uint256 maxAssets = (_fromAssetToSeniorAsset(
            asset.balanceOf(address(this))
        ) * collateralRatio) / WAD;

        return currentAssets >= maxAssets ? 0 : maxAssets - currentAssets;
    }

    // Don't allow withdraws if any of the strategies have unrealised losses.
    function available_withdraw_limit(
        address _owner,
        uint256 _maxLoss,
        address[] calldata _strategies
    ) external view returns (uint256) {
        for (uint256 i = 0; i < _strategies.length; i++) {
            uint256 debt = SENIOR_VAULT.strategies(_strategies[i]).current_debt;
            if (debt > 0) {
                if (
                    SENIOR_VAULT.assess_share_of_unrealised_losses(
                        _strategies[i],
                        debt
                    ) != 0
                ) return 0;
            }
        }

        return SENIOR_VAULT.convertToAssets(SENIOR_VAULT.balanceOf(_owner));
    }

    function report(
        address _strategy,
        uint256 _gain,
        uint256 _loss
    ) external returns (uint256 _fees, uint256 _refunds) {
        require(msg.sender == address(SENIOR_VAULT), "only senior vault");

        if (_gain > 0) {
            _fees = (_gain * performanceFee) / MAX_BPS;
            (uint16 protocolFee, ) = VAULT_FACTORY.protocol_fee_config(
                address(SENIOR_VAULT)
            );
            uint256 sharesToEarn = SENIOR_VAULT.convertToShares(_fees);
            uint256 protocolShares = (sharesToEarn * protocolFee) / MAX_BPS;
            _notifyRewardAmount(sharesToEarn - protocolShares);
        } else {
            // TODO: Check if the auction was kicked and filled.
            //require(!Auction(auction).isActive(address(asset)), "auction not filled");
            _refunds = Math.min(_loss, SENIOR_ASSET.balanceOf(address(this)));
        }
    }

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }

    function _fromAssetToSeniorAsset(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        return (_amount * assetToSeniorOracle.getRate()) / WAD;
    }

    function _fromSeniorAssetToAsset(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        return (_amount * WAD) / assetToSeniorOracle.getRate();
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies.
     *
     *   EX:
     *       return asset.balanceOf(yieldSource);
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(address _owner)
        public
        view
        override
        returns (uint256)
    {
        WithdrawRequest memory request = userInfo[_owner].withdrawRequest;
        if (request.timestamp + withdrawCooldown > block.timestamp) {
            return request.amount;
        }
        return 0;
    }

    function requestWithdraw(uint256 _amount) external {
        uint256 currentAmount = userInfo[msg.sender].withdrawRequest.amount;
        _amount = Math.min(
            _amount + currentAmount,
            TokenizedStrategy.convertToAssets(
                TokenizedStrategy.balanceOf(msg.sender) // Should never accrue PPS
            )
        );

        userInfo[msg.sender].withdrawRequest = WithdrawRequest({
            amount: _amount,
            timestamp: block.timestamp
        });
    }

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     */
    function _tend(uint256 _totalIdle) internal override {
        uint256 _loss;
        address[] memory strategies = SENIOR_VAULT.get_default_queue();
        for (uint256 i = 0; i < strategies.length; i++) {
            uint256 debt = SENIOR_VAULT.strategies(strategies[i]).current_debt;
            if (debt > 0) {
                _loss += SENIOR_VAULT.assess_share_of_unrealised_losses(
                    strategies[i],
                    debt
                );
            }
        }

        if (_loss > 0) {
            uint256 toAuction = _fromSeniorAssetToAsset(_loss);
            asset.safeTransfer(address(auction), toAuction);
            //Auction(auction).kick(address(asset));
            TokenizedStrategy.report();
        }
    }

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     */
    function _tendTrigger() internal view override returns (bool) {
        address[] memory strategies = SENIOR_VAULT.get_default_queue();
        for (uint256 i = 0; i < strategies.length; i++) {
            uint256 debt = SENIOR_VAULT.strategies(strategies[i]).current_debt;
            if (debt > 0) {
                if (
                    SENIOR_VAULT.assess_share_of_unrealised_losses(
                        strategies[i],
                        debt
                    ) != 0
                ) {
                    return true;
                }
            }
        }
        return false;
    }

    function setAuction(address _auction) external onlyEmergencyAuthorized {
        if (_auction != address(0)) {
            require(Auction(_auction).want() == address(asset), "wrong want");
        }
        auction = _auction;
    }

    function setAssetToSeniorOracle(address _assetToSeniorOracle)
        external
        onlyEmergencyAuthorized
    {
        require(IOracle(_assetToSeniorOracle).getRate() > 0, "invalid oracle");
        assetToSeniorOracle = IOracle(_assetToSeniorOracle);
    }

    function setPerformanceFee(uint256 _performanceFee)
        external
        onlyManagement
    {
        performanceFee = _performanceFee;
    }

    function setWithdrawCooldown(uint256 _withdrawCooldown)
        external
        onlyManagement
    {
        withdrawCooldown = _withdrawCooldown;
    }

    function setCollateralRatio(uint256 _collateralRatio)
        external
        onlyManagement
    {
        collateralRatio = _collateralRatio;
    }
}
