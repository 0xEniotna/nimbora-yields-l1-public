// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;
pragma abicoder v2;

import {StrategyBase} from "../StrategyBase.sol";
import {IChainlinkAggregator} from "../../interfaces/IChainlinkAggregator.sol";
import "../../interfaces/IStrategyUniswapV3.sol";
import {ErrorLib} from "../../lib/ErrorLib.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

// import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";

contract UniswapV3StrategyEETHPool is StrategyBase, IERC721Receiver {
    ISwapRouter public uniswapRouter;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    IChainlinkAggregator public chainlinkPricefeed;
    uint256 public pricefeedPrecision;
    uint256 public minReceivedAmountFactor;
    uint24 public poolFee;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    mapping(uint256 => Deposit) public deposits;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        address _poolingManager,
        address _underlyingToken,
        address _yieldToken,
        address _uniswapRouter,
        address _uniswapFactory,
        address _nonfungiblePositionManager,
        address _chainlinkPricefeed,
        uint256 _minReceivedAmountFactor,
        uint24 _poolFee
    ) public virtual initializer {
        initializeStrategyBase(_poolingManager, _underlyingToken, _yieldToken);
        _initializeUniswap(
            _uniswapRouter, _uniswapFactory, _nonfungiblePositionManager, _underlyingToken, _yieldToken, _poolFee
        );
        _initializeChainlink(_chainlinkPricefeed);
        _setSlippage(_minReceivedAmountFactor);
        _checkDecimals(_underlyingToken, _yieldToken);
    }

    function setMinReceivedAmountFactor(uint256 _minReceivedAmountFactor) public {
        _assertOnlyRoleOwner();
        _setSlippage(_minReceivedAmountFactor);
    }

    function chainlinkLatestAnswer() public view returns (int256) {
        return _chainlinkLatestAnswer();
    }

    function applySlippageDepositExactInputSingle(uint256 amount) public view returns (uint256) {
        return _applySlippageDepositExactInputSingle(amount);
    }

    function applySlippageWithdrawExactOutputSingle(uint256 amount) public view returns (uint256) {
        return _applySlippageWithdrawExactOutputSingle(amount);
    }

    function _initializeUniswap(
        address _uniswapRouterAddress,
        address _uniswapFactoryAddress,
        address _nonfungiblePositionManager,
        address _underlyingToken,
        address _yieldToken,
        uint24 _poolFee
    ) internal {
        require(_uniswapRouterAddress != address(0), "Zero address: Uniswap Router");
        uniswapRouter = ISwapRouter(_uniswapRouterAddress);

        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);

        IUniswapV3Factory uniswapFactory = IUniswapV3Factory(_uniswapFactoryAddress);
        address poolAddress = uniswapFactory.getPool(_underlyingToken, _yieldToken, _poolFee);
        require(poolAddress != address(0), "Pool does not exist");
        poolFee = _poolFee;

        IERC20(_underlyingToken).approve(_uniswapRouterAddress, type(uint256).max);

        IERC20(_yieldToken).approve(_uniswapRouterAddress, type(uint256).max);
    }

    function _initializeChainlink(address chainlinkPricefeedAddress) internal {
        require(chainlinkPricefeedAddress != address(0), "Zero address: Chainlink");
        chainlinkPricefeed = IChainlinkAggregator(chainlinkPricefeedAddress);
        pricefeedPrecision = 10 ** chainlinkPricefeed.decimals();
    }

    function _setSlippage(uint256 _minReceivedAmountFactor) internal {
        require(
            _minReceivedAmountFactor <= SLIPPAGE_PRECISION
                && _minReceivedAmountFactor >= (SLIPPAGE_PRECISION * 95) / 100,
            "Invalid slippage"
        );
        minReceivedAmountFactor = _minReceivedAmountFactor;
    }

    function _checkDecimals(address _underlyingToken, address _yieldToken) internal virtual {
        if (IERC20Metadata(_underlyingToken).decimals() != IERC20Metadata(_yieldToken).decimals()) {
            revert ErrorLib.InvalidDecimals();
        }
    }

    function _deposit(uint256 amount) internal override returns (uint256 tokenId) {
        uint256 yieldAmount = _underlyingToYield(amount / 2);
        uint256 amountOutMinimum = _applySlippageDepositExactInputSingle(yieldAmount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: underlyingToken,
            tokenOut: yieldToken,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amount / 2,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = uniswapRouter.exactInputSingle(params);

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = _mintNewPosition(amount / 2, amountOut);
        return tokenId;
    }

    function _createUniswapDeposit(address owner, uint256 tokenId) internal {
        (,, address token0, address token1,,,, uint128 liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        // set the owner and data for position
        // operator is msg.sender
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: token0, token1: token1});
    }

    function _withdraw(uint256 amount) internal override returns (uint256) {
        (uint256 amount0, uint256 amount1) =
            _decreaseLiquidity(deposits[msg.sender].tokenId, deposits[msg.sender].liquidity);

        uint256 chainlinkLatestAnswer = uint256(_chainlinkLatestAnswer());
        uint256 yieldAmount = _calculateUnderlyingToYieldAmount(chainlinkLatestAnswer, amount);
        uint256 amountInMaximum = _applySlippageWithdrawExactOutputSingle(yieldAmount);
        uint256 yieldBalance = yieldBalance();

        if (amountInMaximum > yieldBalance) {
            uint256 underlyingAmount = _calculateYieldToUnderlyingAmount(chainlinkLatestAnswer, yieldBalance);
            uint256 amountOutMinimum = _applySlippageDepositExactInputSingle(underlyingAmount);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: yieldToken,
                tokenOut: underlyingToken,
                fee: poolFee,
                recipient: poolingManager,
                deadline: block.timestamp,
                amountIn: yieldBalance,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });
            uint256 output = uniswapRouter.exactInputSingle(params);
            return (output);
        } else {
            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
                tokenIn: yieldToken,
                tokenOut: underlyingToken,
                fee: poolFee,
                recipient: poolingManager,
                deadline: block.timestamp,
                amountOut: amount,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            });
            uniswapRouter.exactOutputSingle(params);
            return (amount);
        }
    }

    function _mintNewPosition(uint256 amount0ToMint, uint256 amount1ToMint)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        // transfer tokens to contract
        TransferHelper.safeTransferFrom(yieldToken, msg.sender, address(this), amount0ToMint);
        TransferHelper.safeTransferFrom(underlyingToken, msg.sender, address(this), amount1ToMint);

        // Approve the position manager
        TransferHelper.safeApprove(yieldToken, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(underlyingToken, address(nonfungiblePositionManager), amount1ToMint);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: yieldToken,
            token1: underlyingToken,
            fee: poolFee,
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // Note that the pool defined by DAI/USDC and fee tier 0.3% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        _createDeposit(msg.sender, tokenId);

        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(yieldToken, address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(yieldToken, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(underlying, address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(underlying, msg.sender, refund1);
        }
    }

    function _decreaseLiquidity(uint256 tokenId, uint256 liquidity)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        // get liquidity data for tokenId
        // uint128 liquidity = deposits[tokenId].liquidity;

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

        return (amount0, amount1);
    }

    function _collectAllFees(uint256 tokenId) internal returns (uint256 amount0, uint256 amount1) {
        // Caller must own the ERC721 position, meaning it must be a deposit

        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        // send collected feed back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    /// @notice Transfers funds to owner of NFT
    /// @param tokenId The id of the erc721
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    function _sendToOwner(uint256 tokenId, uint256 amount0, uint256 amount1) internal {
        // get owner of contract
        address owner = deposits[tokenId].owner;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send collected fees to owner
        TransferHelper.safeTransfer(token0, owner, amount0);
        TransferHelper.safeTransfer(token1, owner, amount1);
    }

    function _applySlippageDepositExactInputSingle(uint256 amount) internal view returns (uint256) {
        return (minReceivedAmountFactor * amount) / (SLIPPAGE_PRECISION);
    }

    function _applySlippageWithdrawExactOutputSingle(uint256 amount) internal view returns (uint256) {
        return (SLIPPAGE_PRECISION * amount) / (minReceivedAmountFactor);
    }

    function _chainlinkLatestAnswer() internal view returns (int256) {
        return chainlinkPricefeed.latestAnswer();
    }

    function _underlyingToYield(uint256 amount) internal view override returns (uint256) {
        return _calculateUnderlyingToYieldAmount(uint256(_chainlinkLatestAnswer()), amount);
    }

    function _yieldToUnderlying(uint256 amount) internal view override returns (uint256) {
        return _calculateYieldToUnderlyingAmount(uint256(_chainlinkLatestAnswer()), amount);
    }

    function _calculateUnderlyingToYieldAmount(uint256 yieldPrice, uint256 amount)
        internal
        view
        virtual
        returns (uint256)
    {
        return (pricefeedPrecision * amount) / (yieldPrice);
    }

    function _calculateYieldToUnderlyingAmount(uint256 yieldPrice, uint256 amount)
        internal
        view
        virtual
        returns (uint256)
    {
        return (amount * yieldPrice) / (pricefeedPrecision);
    }

    // CALLBACK
    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        // get position information

        _createUniswapDeposit(operator, tokenId);

        return this.onERC721Received.selector;
    }
}
