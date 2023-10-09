// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {IAlphaKeysTokenV3} from "./interfaces/IAlphaKeysTokenV3.sol";
import {AlphaKeysTokenStorage} from "./storage/AlphaKeysTokenStorage.sol";

import {BlockContext} from "./base/BlockContext.sol";
import {Multicall} from "./base/Multicall.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import {IAlphaKeysFactory} from "./interfaces/IAlphaKeysFactory.sol";

import {TransferHelper} from "./libraries/TransferHelper.sol";
import {NumberMath} from "./libraries/NumberMath.sol";
import {TokenTypes} from "./libraries/TokenTypes.sol";

contract AlphaKeysTokenV3 is
    IAlphaKeysTokenV3,
    BlockContext,
    Multicall,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    AlphaKeysTokenStorage
{
    using SafeMathUpgradeable for uint256;
    using NumberMath for uint256;
    using AddressUpgradeable for address;

    uint24 internal constant FEE_ENABLED = 1;

    modifier onlyFactory() {
        require(_msgSender() == _factory);
        _;
    }

    modifier onlyPlayer() {
        require(_msgSender() == _player);
        _;
    }

    modifier notContract() {
        // caller is contract
        require(!_msgSender().isContract(), "AKF_CIC");
        _;
    }

    function initialize(
        address factory,
        address player,
        string calldata name,
        string calldata symbol
    ) external override initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __ERC20Votes_init();
        //
        _factory = factory;
        _player = player;
        _createdTimestamp = _blockTimestamp();
        _btcMigrated = true;
        //
        if (player == address(0)) {
            _mint(address(this), NumberMath.ONE_ETHER);
        } else {
            _mint(player, NumberMath.ONE_ETHER);
        }
    }

    //FOR PROPOSAL
    function _mint(
        address account,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        return ERC20VotesUpgradeable._mint(account, amount);
    }

    function _burn(
        address account,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        ERC20VotesUpgradeable._burn(account, amount);
        _requireCheckBalance(account);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        ERC20VotesUpgradeable._afterTokenTransfer(from, to, amount);
        _requireCheckBalance(from);
    }

    // for GET

    function getFactory() public view returns (IAlphaKeysFactory) {
        return IAlphaKeysFactory(_factory);
    }

    function getPlayer() external view override returns (address) {
        return _player;
    }

    function getProtocolFeeRatio() public view returns (uint24) {
        uint256 buyPrice = getBuyPriceV2(NumberMath.ONE_ETHER);
        if (buyPrice >= 10 ether) {
            return 10000;
        } else if (buyPrice >= 1 ether) {
            return 20000;
        } else if (buyPrice >= 0.1 ether) {
            return 30000;
        } else if (buyPrice >= 0.01 ether) {
            return 40000;
        }
        return 50000;
    }

    function getPlayerFeeRatio() public view returns (uint24) {
        uint24 playerFeeRatio = _playerFeeRatio;
        if (playerFeeRatio == 0) {
            IAlphaKeysFactory factory = getFactory();
            playerFeeRatio = factory.getPlayerFeeRatio();
            return playerFeeRatio;
        }
        return (playerFeeRatio - FEE_ENABLED);
    }

    function updatePlayerFeeRatio(
        uint24 playerFeeRatio
    ) external notContract onlyPlayer {
        require(playerFeeRatio <= 50000, "AKT_BFR");
        //
        _playerFeeRatio = (playerFeeRatio + FEE_ENABLED);
        //
        emit PlayerFeeRatioUpdated(playerFeeRatio);
    }

    //

    function totalSupplyUnits() public view returns (uint256) {
        return totalSupply().div(NumberMath.PRICE_UNIT);
    }

    function balanceUnitOf(address account) public view returns (uint256) {
        return balanceOf(account).div(NumberMath.PRICE_UNIT);
    }

    function getPrice(
        uint256 supply,
        uint256 amount
    ) public pure returns (uint256) {
        return
            getPriceV2(
                supply.mul(NumberMath.NUMBER_UNIT_PER_ONE_ETHER),
                amount.mul(NumberMath.NUMBER_UNIT_PER_ONE_ETHER)
            );
    }

    function getPriceV2(
        uint256 supply,
        uint256 amount
    ) public pure returns (uint256) {
        uint256 sum1 = supply == 0
            ? 0
            : ((supply - NumberMath.NUMBER_UNIT_PER_ONE_ETHER) *
                supply *
                (2 *
                    (supply - NumberMath.NUMBER_UNIT_PER_ONE_ETHER) +
                    NumberMath.NUMBER_UNIT_PER_ONE_ETHER)) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : ((supply - NumberMath.NUMBER_UNIT_PER_ONE_ETHER + amount) *
                (supply + amount) *
                (2 *
                    (supply - NumberMath.NUMBER_UNIT_PER_ONE_ETHER + amount) +
                    NumberMath.NUMBER_UNIT_PER_ONE_ETHER)) / 6;
        uint256 summation = sum2 - sum1;
        return
            (summation * NumberMath.ONE_ETHER) /
            NumberMath.PRICE_KEYS_DENOMINATOR /
            (NumberMath.NUMBER_UNIT_PER_ONE_ETHER *
                NumberMath.NUMBER_UNIT_PER_ONE_ETHER *
                NumberMath.NUMBER_UNIT_PER_ONE_ETHER);
    }

    function getBuyPrice(uint256 amount) public view returns (uint256) {
        uint256 amountUnit = amount.mul(NumberMath.ONE_ETHER).div(
            NumberMath.PRICE_UNIT
        );
        return getPriceV2(totalSupplyUnits(), amountUnit).add(1);
    }

    function getSellPrice(uint256 amount) public view returns (uint256) {
        uint256 amountUnit = amount.mul(NumberMath.ONE_ETHER).div(
            NumberMath.PRICE_UNIT
        );
        return getPriceV2(totalSupplyUnits().sub(amountUnit), amountUnit);
    }

    function getBuyPriceV2(uint256 amountX18) public view returns (uint256) {
        uint256 amount = amountX18.div(NumberMath.PRICE_UNIT);
        return getPriceV2(totalSupplyUnits(), amount).add(1);
    }

    function getBuyPriceAfterFee(uint256 amount) public view returns (uint256) {
        return getBuyPriceAfterFeeV2(amount.mul(NumberMath.ONE_ETHER));
    }

    function getSellPriceAfterFee(
        uint256 amount
    ) public view returns (uint256) {
        return getSellPriceAfterFeeV2(amount.mul(NumberMath.ONE_ETHER));
    }

    function getSellPriceV2(uint256 amountX18) public view returns (uint256) {
        uint256 amount = amountX18.div(NumberMath.PRICE_UNIT);
        return getPriceV2(totalSupplyUnits().sub(amount), amount);
    }

    function getBuyPriceAfterFeeV2(
        uint256 amountX18
    ) public view returns (uint256) {
        uint24 protocolFeeRatio = getProtocolFeeRatio();
        uint24 playerFeeRatio = getPlayerFeeRatio();
        //
        uint256 price = getBuyPriceV2(amountX18);
        uint256 protocolFee = price.mulRatio(protocolFeeRatio);
        uint256 playerFee = price.mulRatio(playerFeeRatio);
        return price + protocolFee + playerFee;
    }

    function getSellPriceAfterFeeV2(
        uint256 amountX18
    ) public view returns (uint256) {
        uint24 protocolFeeRatio = getProtocolFeeRatio();
        uint24 playerFeeRatio = getPlayerFeeRatio();
        //
        uint256 price = getSellPriceV2(amountX18);
        uint256 protocolFee = price.mulRatio(protocolFeeRatio);
        uint256 playerFee = price.mulRatio(playerFeeRatio);
        return price - protocolFee - playerFee;
    }

    function getBTC() public view returns (address) {
        address btc = IAlphaKeysFactory(_factory).getBTC();
        require(btc != address(0), "AKT_BAZ");
        return btc;
    }

    function getBTCBalance() public view returns (uint256) {
        return IERC20Upgradeable(getBTC()).balanceOf(address(this));
    }

    function getFeeBTC() public view returns (uint256) {
        uint256 supplyUnits = totalSupplyUnits();
        uint256 price = 0;
        if (supplyUnits > NumberMath.NUMBER_UNIT_PER_ONE_ETHER) {
            price = getPriceV2(
                NumberMath.NUMBER_UNIT_PER_ONE_ETHER,
                supplyUnits - NumberMath.NUMBER_UNIT_PER_ONE_ETHER
            );
        }
        return getBTCBalance().sub(price);
    }

    function freeBalanceOf(address user) public view returns (uint256) {
        uint256 balance = balanceOf(user);
        uint256 lockedBalance = lockedBalanceOf(user);
        if (balance <= lockedBalance) {
            return 0;
        }
        return balance.sub(lockedBalance);
    }

    function lockedBalanceOf(address user) public view returns (uint256) {
        uint256 lockedBalance = 0;
        {
            uint256 duationTs = NumberMath.TS_30_DAYS;
            uint256 len = _lockedUsers[user][duationTs].length;
            for (uint i = 0; i < len; i++) {
                TokenTypes.Locked memory locked = _lockedUsers[user][duationTs][
                    (len - 1 - i)
                ];
                if (locked.expiredTs < _blockTimestamp()) {
                    break;
                }
                lockedBalance = lockedBalance.add(locked.amount);
            }
        }
        return lockedBalance;
    }

    function _requireCheckBalance(address user) internal view {
        // balance not required
        require(lockedBalanceOf(user) <= balanceOf(user), "AKT_BNR");
    }

    // internal

    function _buyKeysFor(
        address from,
        uint256 amountX18,
        address recipient,
        TokenTypes.OrderType orderType
    ) internal {
        uint256 amount = amountX18.div(NumberMath.PRICE_UNIT);
        //
        require(amount > 0, "AKT_IA");
        //
        IAlphaKeysFactory factory = getFactory();
        uint24 protocolFeeRatio = getProtocolFeeRatio();
        uint24 playerFeeRatio = getPlayerFeeRatio();
        address protocolFeeDestination = factory.getProtocolFeeDestination();
        //
        uint256 supply = totalSupplyUnits();
        address player = _player;
        // only player first buy
        require(
            supply >= NumberMath.NUMBER_UNIT_PER_ONE_ETHER ||
                player == recipient,
            "AKT_OPFB"
        );
        uint256 price = getPriceV2(supply, amount).add(1);
        uint256 protocolFee = price.mulRatio(protocolFeeRatio);
        uint256 playerFee = price.mulRatio(playerFeeRatio);
        //
        _mint(recipient, amount.mul(NumberMath.PRICE_UNIT));
        //
        emit TradeV4(
            recipient,
            player,
            true,
            amount.mul(NumberMath.PRICE_UNIT),
            price,
            protocolFee,
            playerFee,
            supply.add(amount).mul(NumberMath.PRICE_UNIT),
            orderType,
            bytes32(0)
        );
        //
        address btc = getBTC();
        //
        if (_msgSender() == address(factory)) {
            factory.requestPayment(
                btc,
                from,
                price.add(protocolFee).add(playerFee)
            );
        } else {
            TransferHelper.safeTransferFrom(
                btc,
                from,
                address(this),
                price.add(protocolFee).add(playerFee)
            );
        }
        //
        TransferHelper.safeTransfer(btc, protocolFeeDestination, protocolFee);
        if (player != address(0)) {
            TransferHelper.safeTransfer(btc, player, playerFee);
        }
    }

    function _sellKeysForV2(
        address from,
        uint256 amountX18,
        address recipient,
        TokenTypes.OrderType orderType
    ) internal {
        uint256 amount = amountX18.div(NumberMath.PRICE_UNIT);
        //
        require(amount > 0, "AKT_IA");
        //
        IAlphaKeysFactory factory = getFactory();
        uint24 protocolFeeRatio = getProtocolFeeRatio();
        uint24 playerFeeRatio = getPlayerFeeRatio();
        address protocolFeeDestination = factory.getProtocolFeeDestination();
        //
        uint256 supply = totalSupplyUnits();
        // can not sell last keys
        require(
            supply >= NumberMath.NUMBER_UNIT_PER_ONE_ETHER + amount,
            "AKT_CNSLK"
        );
        // insufficient keys
        require(balanceUnitOf(from) >= amount, "AKT_IK");
        //
        uint256 price = getPriceV2(supply.sub(amount), amount);
        uint256 protocolFee = price.mulRatio(protocolFeeRatio);
        uint256 playerFee = price.mulRatio(playerFeeRatio);
        //
        _burn(from, amount.mul(NumberMath.PRICE_UNIT));
        //
        address player = _player;
        emit TradeV4(
            recipient,
            player,
            false,
            amount.mul(NumberMath.PRICE_UNIT),
            price,
            protocolFee,
            playerFee,
            supply.sub(amount).mul(NumberMath.PRICE_UNIT),
            orderType,
            bytes32(0)
        );
        //
        address btc = getBTC();
        //
        TransferHelper.safeTransfer(
            btc,
            recipient,
            price.sub(protocolFee).sub(playerFee)
        );
        TransferHelper.safeTransfer(btc, protocolFeeDestination, protocolFee);
        if (player != address(0)) {
            TransferHelper.safeTransfer(btc, player, playerFee);
        }
    }

    // external

    function buyKeys(uint256 amount) external notContract nonReentrant {
        _buyKeysFor(
            _msgSender(),
            amount.mul(NumberMath.ONE_ETHER),
            _msgSender(),
            TokenTypes.OrderType.SpotOrder
        );
    }

    function buyKeysFor(
        uint256 amount,
        address recipient
    ) external notContract nonReentrant {
        _buyKeysFor(
            _msgSender(),
            amount.mul(NumberMath.ONE_ETHER),
            recipient,
            TokenTypes.OrderType.SpotOrder
        );
    }

    function buyKeysV2(uint256 amountX18) external notContract nonReentrant {
        _buyKeysFor(
            _msgSender(),
            amountX18,
            _msgSender(),
            TokenTypes.OrderType.SpotOrder
        );
    }

    function buyKeysForV2(
        uint256 amountX18,
        address recipient
    ) external notContract nonReentrant {
        _buyKeysFor(
            _msgSender(),
            amountX18,
            recipient,
            TokenTypes.OrderType.SpotOrder
        );
    }

    function permitBuyKeysForV2(
        address from,
        uint256 amountX18,
        address recipient,
        TokenTypes.OrderType orderType
    ) external nonReentrant onlyFactory {
        _buyKeysFor(from, amountX18, recipient, orderType);
    }

    function sellKeys(uint256 amount) external notContract nonReentrant {
        _sellKeysForV2(
            _msgSender(),
            amount.mul(NumberMath.ONE_ETHER),
            _msgSender(),
            TokenTypes.OrderType.SpotOrder
        );
    }

    function sellKeysFor(
        uint256 amount,
        address recipient
    ) external notContract nonReentrant {
        _sellKeysForV2(
            _msgSender(),
            amount.mul(NumberMath.ONE_ETHER),
            recipient,
            TokenTypes.OrderType.SpotOrder
        );
    }

    function sellKeysV2(uint256 amountX18) external notContract nonReentrant {
        _sellKeysForV2(
            _msgSender(),
            amountX18,
            _msgSender(),
            TokenTypes.OrderType.SpotOrder
        );
    }

    function sellKeysForV2(
        uint256 amountX18,
        address recipient
    ) external notContract nonReentrant {
        _sellKeysForV2(
            _msgSender(),
            amountX18,
            recipient,
            TokenTypes.OrderType.SpotOrder
        );
    }

    function permitSellKeysForV2(
        address from,
        uint256 amountX18,
        address recipient,
        TokenTypes.OrderType orderType
    ) external nonReentrant onlyFactory {
        _sellKeysForV2(from, amountX18, recipient, orderType);
    }

    function updateNewPlayer(
        address newPlayer
    ) external nonReentrant onlyFactory {
        require(newPlayer != address(0), "AKT_NPNZA");
        //
        address oldPlayer = _player;
        _player = newPlayer;
        emit PlayerUpdated(oldPlayer, newPlayer);
        // return fee
        if (oldPlayer == address(0)) {
            TransferHelper.safeTransfer(
                address(this),
                newPlayer,
                balanceOf(address(this))
            );
            uint256 feeBTC = getFeeBTC();
            if (feeBTC > 0) {
                TransferHelper.safeTransfer(getBTC(), newPlayer, feeBTC);
            }
        }
    }

    //

    function permitLock30D(address user, uint256 amount) external onlyFactory {
        uint256 duationTs = NumberMath.TS_30_DAYS;
        uint256 expiredTs = _blockTimestamp().add(duationTs);
        _lockedUsers[user][duationTs].push(
            TokenTypes.Locked(amount, expiredTs)
        );
        emit LockedTs(user, amount, duationTs, expiredTs);
    }
}
