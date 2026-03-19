// SPDX-License-Identifier: MIT
// ════════════════════════════════════════════════════════════════════════
//
//   ███╗   ██╗ ██████╗ ██╗   ██╗ █████╗ ██████╗ ██╗   ██╗██╗     ███████╗███████╗
//   ████╗  ██║██╔═══██╗██║   ██║██╔══██╗██╔══██╗██║   ██║██║     ██╔════╝██╔════╝
//   ██╔██╗ ██║██║   ██║██║   ██║███████║██████╔╝██║   ██║██║     ███████╗█████╗
//   ██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║██╔═══╝ ██║   ██║██║     ╚════██║██╔══╝
//   ██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║██║     ╚██████╔╝███████╗███████║███████╗
//   ╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝╚═╝      ╚═════╝ ╚══════╝╚══════╝╚══════╝
//
//   Token   : NovaPulse  (NVPX)
//   Version : v6  —  Production / Open-Source Release
//   Network : BNB Smart Chain (BSC) Mainnet
//   License : MIT  (fully open source — verify on BscScan)
//
// ════════════════════════════════════════════════════════════════════════
//
//   SELL FEE AUTO-SWAP  (new in v6)
//   ─────────────────────────────────────────────────────────────────────
//   The 3% sell fee is collected in NVPX inside the contract.
//   Once accumulated NVPX fees reach the swap threshold (default 20 NVPX),
//   the contract automatically calls PancakeSwap Router to swap
//   all accumulated NVPX → USDT, then sends the USDT directly to
//   the designated feeReceiver wallet.
//
//   FLOW:
//   User sells NVPX on PancakeSwap
//     → 3% intercepted as fee (stored in contract as accumulatedFeeNVPX)
//     → if accumulatedFeeNVPX >= swapThreshold (20 NVPX):
//         → contract approves Router to spend NVPX
//         → calls Router.swapExactTokensForTokens(NVPX → USDT)
//         → USDT arrives directly in feeReceiverWallet
//         → accumulatedFeeNVPX reset to zero
//     → if liquidity check fails: skip swap silently, accumulate more
//
//   REENTRANCY PROTECTION:
//   A swap lock (swapping bool) prevents any re-entrant call to _transfer
//   while a PancakeSwap swap is in progress. This is critical because
//   the Router will call back into the token contract during the swap.
//   While swapping = true, the contract's own transfer mechanics
//   (burn, fees, referrals) are fully bypassed for that internal call.
//
//   SLIPPAGE:
//   Default slippage tolerance is 2% (adjustable by admin before goLive).
//   If the swap would result in less than (1 - slippage%) of expected USDT,
//   the swap is skipped and fees continue to accumulate.
//
//   LIQUIDITY CHECK:
//   Before every swap, the contract reads the NVPX/USDT pair reserves via
//   IPancakePair.getReserves(). If the USDT reserve in the pair is below
//   minLiquidityUSDT (default 1,000 USDT), the swap is skipped safely.
//
// ════════════════════════════════════════════════════════════════════════
//
//   COMPLETE TOKENOMICS
//   ─────────────────────────────────────────────────────────────────────
//   Max Supply      : 21,000,000 NVPX  (hard cap, Bitcoin-like)
//   Mint Price      : 2 USDT = 1 NVPX  (treasury-backed)
//   Buy Fee         : 0%               (zero barrier to entry)
//   Sell Fee        : 3%               (auto-swapped to USDT → feeWallet)
//   Auto-Burn       : 1%               (every transfer, forever)
//   Referral L1     : 3%               (direct referrer, from buyer's NVPX)
//   Referral L2     : 1.5%             (referrer's referrer, from buyer's NVPX)
//   Swap Threshold  : 20 NVPX          (minimum fee before auto-swap fires)
//   Slippage        : 2%               (max acceptable swap slippage)
//
//   PRICE MODEL  (3-Force Bonding Curve):
//   nvpxPrice = floorPrice × scarcityMult × demandMult
//   floorPrice   = treasuryUSDT / circulatingSupply
//   scarcityMult = MAX_SUPPLY   / circulatingSupply
//   demandMult   = 1 + (transferCount / demandSensitivity)
//
// ════════════════════════════════════════════════════════════════════════
pragma solidity ^0.8.19;

// ─────────────────────────────────────────────────────────────────────────
//  IERC20
// ─────────────────────────────────────────────────────────────────────────
interface IERC20 {
    function totalSupply()                                           external view returns (uint256);
    function balanceOf(address account)                              external view returns (uint256);
    function transfer(address to, uint256 amount)                    external returns (bool);
    function allowance(address owner, address spender)               external view returns (uint256);
    function approve(address spender, uint256 amount)                external returns (bool);
    function transferFrom(address from, address to, uint256 amount)  external returns (bool);
    event Transfer(address indexed from, address indexed to,         uint256 value);
    event Approval(address indexed owner, address indexed spender,   uint256 value);
}

// ─────────────────────────────────────────────────────────────────────────
//  PancakeSwap interfaces  (BSC Mainnet)
// ─────────────────────────────────────────────────────────────────────────

/// @dev PancakeSwap V2 Router — fixed BSC address: 0x10ED43C718714eb63d5aA57B78B54704E256024E
interface IPancakeRouter {
    /// @notice Swap exact input tokens for output tokens along a path.
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    /// @notice Get expected output amounts for a given input and path.
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts);
}

/// @dev PancakeSwap V2 Pair — used to read reserves for liquidity check.
interface IPancakePair {
    function getReserves() external view returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32  blockTimestampLast
    );
    function token0() external view returns (address);
    function token1() external view returns (address);
}

// ─────────────────────────────────────────────────────────────────────────
//  SafeMath
// ─────────────────────────────────────────────────────────────────────────
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) { return a + b; }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: underflow"); return a - b;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: overflow"); return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: div by zero"); return a / b;
    }
}

// ─────────────────────────────────────────────────────────────────────────
//  ReentrancyGuard
// ─────────────────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;
    uint256 private _status;
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ─────────────────────────────────────────────────────────────────────────
//  AccessControl
// ─────────────────────────────────────────────────────────────────────────
abstract contract AccessControl {
    mapping(bytes32 => mapping(address => bool)) private _roles;
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    modifier onlyRole(bytes32 role) {
        require(_roles[role][msg.sender], "AccessControl: caller missing role");
        _;
    }
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }
    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }
    function _revokeRole(bytes32 role, address account) internal {
        if (_roles[role][account]) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }
    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }
    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }
}

// ─────────────────────────────────────────────────────────────────────────
//  IFeeReceiver  (optional callback — referral rewards only)
// ─────────────────────────────────────────────────────────────────────────
interface IFeeReceiver {
    function onFeeReceived(uint256 amount) external;
}

// ═════════════════════════════════════════════════════════════════════════
//
//   NovaPulse  —  Main Contract  (v6  |  Production  |  Open Source)
//
// ═════════════════════════════════════════════════════════════════════════
contract NovaPulse is IERC20, AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    // ─────────────────────────────────────────────────────────────────
    //  TOKEN METADATA
    // ─────────────────────────────────────────────────────────────────
    string  public constant name     = "NovaPulse";
    string  public constant symbol   = "NVPX";
    uint8   public constant decimals = 18;
    string  public constant version  = "6.0.0";

    uint256 private constant WAD = 1e18;

    // ─────────────────────────────────────────────────────────────────
    //  ROLES
    // ─────────────────────────────────────────────────────────────────
    bytes32 public constant FEE_EXEMPT = keccak256("FEE_EXEMPT");

    // ─────────────────────────────────────────────────────────────────
    //  SUPPLY
    // ─────────────────────────────────────────────────────────────────
    uint256 public constant MAX_SUPPLY    = 21_000_000 * WAD;
    uint256 public constant USDT_PER_NVPX = 2 * WAD;           // 2 USDT = 1 NVPX

    uint256 private _totalSupply;
    uint256 public  totalMinted;
    bool    public  mintingClosed;

    mapping(address => uint256)                     private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ─────────────────────────────────────────────────────────────────
    //  USDT TREASURY
    // ─────────────────────────────────────────────────────────────────

    /// @notice BSC Mainnet USDT: 0x55d398326f99059fF775485246999027B3197955
    address public immutable USDT;
    uint256 public           treasuryUSDT;

    // ─────────────────────────────────────────────────────────────────
    //  PANCAKESWAP  INTEGRATION
    // ─────────────────────────────────────────────────────────────────

    /// @notice PancakeSwap V2 Router — fixed BSC address.
    ///         0x10ED43C718714eb63d5aA57B78B54704E256024E
    address public constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    /// @notice NVPX/USDT LP pair on PancakeSwap.
    ///         Set by admin via setMainPair() before goLive().
    address public mainPair;

    // ─────────────────────────────────────────────────────────────────
    //  FEE CONFIG
    // ─────────────────────────────────────────────────────────────────

    uint256 public constant PRECISION = 100_000;    // 100% = 100_000
    uint256 public sellFeeRatio       = 3_000;      // 3%
    uint256 public burnRatio          = 1_000;      // 1%

    // ─────────────────────────────────────────────────────────────────
    //  AUTO-SWAP  ENGINE
    // ─────────────────────────────────────────────────────────────────

    /// @notice Wallet that receives USDT from auto-swapped sell fees.
    ///         Locked permanently after goLive() is called.
    address public feeReceiverWallet = 0x9504F94B3aE36B84e4a4dFA03BD1851737acf5Ac;

    /// @notice Accumulated NVPX sell fees waiting to be swapped.
    ///         Held inside this contract. Swaps when >= swapThreshold.
    uint256 public accumulatedFeeNVPX;

    /// @notice Minimum NVPX accumulated before auto-swap fires.
    ///         Default: 20 NVPX (20 * 1e18). Adjustable before goLive().
    uint256 public swapThreshold = 20 * WAD;

    /// @notice Slippage tolerance for PancakeSwap swap (default 2%).
    ///         200 = 2% out of 10_000 basis points.
    ///         Adjustable by admin before goLive().
    uint256 public swapSlippageBps = 200;           // 200/10000 = 2%

    /// @notice Minimum USDT liquidity in the pair before swap is allowed.
    ///         Prevents swaps into illiquid pools (default 1,000 USDT).
    uint256 public minLiquidityUSDT = 1_000 * WAD;

    /// @notice Swap lock — prevents reentrancy during PancakeSwap callback.
    ///         While true, _transfer skips all mechanics for internal calls.
    bool private swapping;

    // ─────────────────────────────────────────────────────────────────
    //  PRICE MODEL
    // ─────────────────────────────────────────────────────────────────
    uint256 public transferCount;
    uint256 public demandSensitivity = 10_000;

    // ─────────────────────────────────────────────────────────────────
    //  REFERRAL SYSTEM
    // ─────────────────────────────────────────────────────────────────
    uint256 public refL1Ratio = 3_000;   // 3.0%  — from buyer's purchase
    uint256 public refL2Ratio = 1_500;   // 1.5%  — from buyer's purchase

    mapping(address => address) public referrer;

    struct ReferralStats {
        uint256 totalEarned;
        uint256 totalReferred;
        uint256 referralTxCount;
    }
    mapping(address => ReferralStats) public referralStats;

    uint256 public totalReferralRewardsDistributed;
    uint256 public totalReferralTransactions;

    // ─────────────────────────────────────────────────────────────────
    //  GO-LIVE STATE
    // ─────────────────────────────────────────────────────────────────
    bool    public isLive;
    bool    public ownershipRenounced;
    uint256 public launchTimestamp;

    // ─────────────────────────────────────────────────────────────────
    //  EVENTS
    // ─────────────────────────────────────────────────────────────────

    // Token lifecycle
    event Minted(address indexed to, uint256 nvpxAmount, uint256 usdtPaid);
    event Burned(address indexed from, uint256 amount);
    event SellFeeTaken(address indexed seller, uint256 feeNVPX);
    event PriceSnapshot(uint256 floorPrice, uint256 scarcityMult, uint256 demandMult, uint256 price);

    // Auto-swap
    event FeeSwapExecuted(
        uint256 nvpxSwapped,
        uint256 usdtReceived,
        address indexed sentTo
    );
    event FeeSwapSkipped(string reason);
    event FeeAccumulated(uint256 newTotal);

    // Referral
    event ReferrerRegistered(address indexed referee, address indexed referrerAddr);
    event ReferralRewardPaid(address indexed buyer, address indexed recipient, uint8 level, uint256 amount);
    event ReferralRewardSkipped(address indexed recipient, uint8 level, string reason);

    // Admin config
    event FeeReceiverWalletChanged(address indexed oldWallet, address indexed newWallet);
    event SwapThresholdChanged(uint256 newThreshold);
    event SwapSlippageChanged(uint256 newBps);
    event MinLiquidityChanged(uint256 newMin);
    event SellFeeRatioChanged(uint256 newRatio);
    event BurnRatioChanged(uint256 newRatio);
    event RefRatiosChanged(uint256 l1, uint256 l2);
    event DemandSensitivityChanged(uint256 newValue);
    event MainPairSet(address indexed pair);
    event TreasuryWithdrawn(address indexed to, uint256 amount);

    // Go-live
    event ProjectLaunched(
        address indexed deployedBy,
        uint256         launchTimestamp,
        uint256         totalSupplyAtLaunch,
        uint256         treasuryAtLaunch,
        address         mainPair,
        address         feeReceiverWallet,
        string          message
    );
    event OwnershipRenounced(address indexed previousAdmin);
    event MintingClosed(uint256 totalMintedFinal);

    // ─────────────────────────────────────────────────────────────────
    //  CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────────

    /// @param _usdt  BSC Mainnet USDT: 0x55d398326f99059fF775485246999027B3197955
    ///
    /// @dev  feeReceiverWallet is hardcoded to:
    ///       0x9504F94B3aE36B84e4a4dFA03BD1851737acf5Ac
    ///       All USDT from auto-swapped sell fees will be sent to this address.
    ///       It can be updated via setFeeReceiverWallet() before goLive().
    ///       After goLive() it is locked permanently on-chain forever.
    constructor(address _usdt) {
        require(_usdt != address(0), "NovaPulse: zero USDT");

        USDT = _usdt;
        // feeReceiverWallet already set to 0x9504F94B3aE36B84e4a4dFA03BD1851737acf5Ac

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEE_EXEMPT,         msg.sender);
        _grantRole(FEE_EXEMPT,         feeReceiverWallet);
        // FEE_EXEMPT on Router: bypass fees on internal swap callbacks
        _grantRole(FEE_EXEMPT,         PANCAKE_ROUTER);
    }

    // ─────────────────────────────────────────────────────────────────
    //  MODIFIERS
    // ─────────────────────────────────────────────────────────────────
    modifier notLive() {
        require(!isLive, "NovaPulse: project is live — config locked forever");
        _;
    }

    // ═════════════════════════════════════════════════════════════════
    //  GO-LIVE  —  ONE CLICK, PERMANENT, IRREVERSIBLE
    // ═════════════════════════════════════════════════════════════════

    /// @notice  *** CALL THIS ONCE WHEN YOUR PROJECT IS READY TO LAUNCH ***
    ///
    ///          PRE-CONDITIONS (complete before calling goLive):
    ///          ✓  setMainPair(pancakeswapPairAddress)
    ///          ✓  setFeeReceiverWallet(yourWalletAddress)
    ///          ✓  Verify all ratios and thresholds are correct
    ///          ✓  Add initial liquidity on PancakeSwap
    ///          ✓  Submit source to BscScan → Verify & Publish
    ///
    ///          THIS CALL:
    ///          1. isLive = true              all config locked forever
    ///          2. ownershipRenounced = true  deployer loses all rights
    ///          3. mintingClosed = true       no more minting ever
    ///          4. Admin role revoked         wallet stripped completely
    ///          5. launchTimestamp = now      immutable on-chain proof
    ///          6. ProjectLaunched emitted    permanent public record
    function goLive() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!isLive,                "NovaPulse: already live");
        require(mainPair != address(0), "NovaPulse: set mainPair before going live");

        isLive             = true;
        ownershipRenounced = true;
        mintingClosed      = true;
        launchTimestamp    = block.timestamp;

        address deployer = msg.sender;
        _revokeRole(DEFAULT_ADMIN_ROLE, deployer);

        emit ProjectLaunched(
            deployer,
            launchTimestamp,
            _totalSupply,
            treasuryUSDT,
            mainPair,
            feeReceiverWallet,
            "NovaPulse is LIVE. Open-source. Ownership renounced. Contract is autonomous forever."
        );
        emit OwnershipRenounced(deployer);
        emit MintingClosed(totalMinted);
    }

    // ═════════════════════════════════════════════════════════════════
    //  AUTO-SWAP ENGINE
    //  Converts accumulated NVPX sell fees → USDT → feeReceiverWallet
    // ═════════════════════════════════════════════════════════════════

    /// @dev Called after every sell that accumulates fees.
    ///      Checks threshold, liquidity, then executes swap if safe.
    ///      Protected by swapLock to prevent re-entrant calls from Router.
    function _triggerFeeSwapIfReady() internal {

        // ── Guard 1: threshold not reached yet ───────────────────────
        if (accumulatedFeeNVPX < swapThreshold) return;

        // ── Guard 2: already inside a swap (reentrancy lock) ─────────
        if (swapping) return;

        // ── Guard 3: mainPair must be set ────────────────────────────
        if (mainPair == address(0)) return;

        // ── Guard 4: liquidity check ─────────────────────────────────
        if (!_hasSufficientLiquidity()) {
            emit FeeSwapSkipped("insufficient liquidity in pair");
            return;
        }

        // ── Execute swap ─────────────────────────────────────────────
        uint256 amountToSwap = accumulatedFeeNVPX;
        accumulatedFeeNVPX   = 0;       // reset BEFORE swap (reentrancy safety)

        swapping = true;                // lock transfer mechanics during swap

        _executeSwap(amountToSwap);

        swapping = false;               // unlock
    }

    /// @dev Checks if the NVPX/USDT pair has at least minLiquidityUSDT.
    function _hasSufficientLiquidity() internal view returns (bool) {
        try IPancakePair(mainPair).getReserves() returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32  /*blockTimestampLast*/
        ) {
            // Identify which reserve is USDT
            address token0 = IPancakePair(mainPair).token0();
            uint256 usdtReserve = (token0 == USDT)
                ? uint256(reserve0)
                : uint256(reserve1);

            return usdtReserve >= minLiquidityUSDT;
        } catch {
            return false;
        }
    }

    /// @dev Approves Router and executes NVPX → USDT swap.
    ///      Calculates amountOutMin with slippage tolerance.
    ///      USDT goes directly to feeReceiverWallet.
    function _executeSwap(uint256 nvpxAmount) internal {
        // Build swap path: NVPX → USDT
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = USDT;

        // Calculate expected USDT output
        uint256 expectedUSDT = 0;
        try IPancakeRouter(PANCAKE_ROUTER).getAmountsOut(nvpxAmount, path)
            returns (uint256[] memory amounts)
        {
            expectedUSDT = amounts[1];
        } catch {
            // Router query failed — put fees back and skip
            accumulatedFeeNVPX = accumulatedFeeNVPX.add(nvpxAmount);
            emit FeeSwapSkipped("router getAmountsOut failed");
            return;
        }

        if (expectedUSDT == 0) {
            accumulatedFeeNVPX = accumulatedFeeNVPX.add(nvpxAmount);
            emit FeeSwapSkipped("expected USDT output is zero");
            return;
        }

        // Apply slippage: amountOutMin = expectedUSDT * (10000 - slippageBps) / 10000
        uint256 amountOutMin = expectedUSDT
            .mul(uint256(10_000).sub(swapSlippageBps))
            .div(10_000);

        // Approve Router to spend NVPX from this contract
        // Use internal _approve to avoid event spam on every swap
        _allowances[address(this)][PANCAKE_ROUTER] = nvpxAmount;
        emit Approval(address(this), PANCAKE_ROUTER, nvpxAmount);

        // Execute swap — USDT lands directly in feeReceiverWallet
        try IPancakeRouter(PANCAKE_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                nvpxAmount,
                amountOutMin,
                path,
                feeReceiverWallet,   // ← USDT sent straight to your wallet
                block.timestamp + 300
            )
        {
            // Read actual USDT received by checking wallet balance change
            // (We emit nvpxAmount and let indexers derive USDT from logs)
            emit FeeSwapExecuted(nvpxAmount, expectedUSDT, feeReceiverWallet);
        } catch {
            // Swap failed (slippage exceeded or other) — re-accumulate
            accumulatedFeeNVPX = accumulatedFeeNVPX.add(nvpxAmount);
            emit FeeSwapSkipped("swap execution failed — re-accumulating");
        }
    }

    // ═════════════════════════════════════════════════════════════════
    //  REFERRAL REGISTRATION
    // ═════════════════════════════════════════════════════════════════

    /// @notice Bind your referrer before your first DEX buy.
    ///         One-time. Permanent. Immutable.
    ///
    ///  Rules:
    ///  [1] No self-referral
    ///  [2] Cannot change referrer once set
    ///  [3] No circular chain (A→B→A)
    ///  [4] Referrer must hold NVPX
    function registerReferrer(address _referrer) external {
        require(_referrer != address(0),            "NovaPulse: zero referrer");
        require(_referrer != msg.sender,            "NovaPulse: no self-referral");
        require(referrer[msg.sender] == address(0), "NovaPulse: referrer already set");
        require(referrer[_referrer] != msg.sender,  "NovaPulse: circular chain");
        require(_balances[_referrer] > 0,           "NovaPulse: referrer holds no NVPX");

        referrer[msg.sender] = _referrer;
        referralStats[_referrer].totalReferred =
            referralStats[_referrer].totalReferred.add(1);

        emit ReferrerRegistered(msg.sender, _referrer);
    }

    // ═════════════════════════════════════════════════════════════════
    //  DEFAULT REFERRER
    //  If a buyer has no registered referrer, rewards automatically
    //  flow to DEFAULT_REFERRER instead of being skipped entirely.
    //  This ensures 100% of referral rewards are always distributed.
    // ═════════════════════════════════════════════════════════════════

    /// @notice Fallback referrer wallet — receives L1 (3%) when buyer
    ///         has no registered referrer. Hardcoded. Immutable forever.
    address public constant DEFAULT_REFERRER = 0x131D15d8E58900c934E5C6BE2e9054062CCfB427;

    // ═════════════════════════════════════════════════════════════════
    //  REFERRAL REWARD ENGINE  (internal)
    //  Deducts from buyer's credited balance. Zero new supply minted.
    //  Falls back to DEFAULT_REFERRER when buyer has no referrer set.
    // ═════════════════════════════════════════════════════════════════

    function _distributeReferralRewards(address buyer, uint256 grossBuy) internal {
        // Use registered referrer — fall back to DEFAULT_REFERRER if none set
        address l1 = referrer[buyer];
        if (l1 == address(0)) l1 = DEFAULT_REFERRER;
        // Safety: never reward buyer themselves via default
        if (l1 == buyer) return;

        totalReferralTransactions = totalReferralTransactions.add(1);

        // ── Level 1  (3% from buyer → direct referrer) ───────────────
        uint256 l1Reward = grossBuy.mul(refL1Ratio).div(PRECISION);
        if (l1Reward > 0) {
            if (_balances[l1] == 0) {
                emit ReferralRewardSkipped(l1, 1, "referrer holds no NVPX");
            } else if (_balances[buyer] < l1Reward) {
                emit ReferralRewardSkipped(l1, 1, "buyer insufficient balance");
            } else {
                _balances[buyer] = _balances[buyer].sub(l1Reward);
                _balances[l1]    = _balances[l1].add(l1Reward);
                referralStats[l1].totalEarned     = referralStats[l1].totalEarned.add(l1Reward);
                referralStats[l1].referralTxCount = referralStats[l1].referralTxCount.add(1);
                totalReferralRewardsDistributed   = totalReferralRewardsDistributed.add(l1Reward);
                emit Transfer(buyer, l1, l1Reward);
                emit ReferralRewardPaid(buyer, l1, 1, l1Reward);
            }
        }

        // ── Level 2  (1.5% from buyer → referrer's referrer) ─────────
        address l2 = referrer[l1];
        if (l2 == address(0)) return;

        uint256 l2Reward = grossBuy.mul(refL2Ratio).div(PRECISION);
        if (l2Reward > 0) {
            if (_balances[l2] == 0) {
                emit ReferralRewardSkipped(l2, 2, "referrer holds no NVPX");
            } else if (_balances[buyer] < l2Reward) {
                emit ReferralRewardSkipped(l2, 2, "buyer insufficient balance");
            } else {
                _balances[buyer] = _balances[buyer].sub(l2Reward);
                _balances[l2]    = _balances[l2].add(l2Reward);
                referralStats[l2].totalEarned     = referralStats[l2].totalEarned.add(l2Reward);
                referralStats[l2].referralTxCount = referralStats[l2].referralTxCount.add(1);
                totalReferralRewardsDistributed   = totalReferralRewardsDistributed.add(l2Reward);
                emit Transfer(buyer, l2, l2Reward);
                emit ReferralRewardPaid(buyer, l2, 2, l2Reward);
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════
    //  PRICE MODEL  (3-Force Bonding Curve)
    // ═════════════════════════════════════════════════════════════════

    function floorPrice() public view returns (uint256) {
        if (_totalSupply == 0) return USDT_PER_NVPX;
        return treasuryUSDT.mul(WAD).div(_totalSupply);
    }

    function scarcityMultiplier() public view returns (uint256) {
        if (_totalSupply == 0) return WAD;
        return MAX_SUPPLY.mul(WAD).div(_totalSupply);
    }

    function demandMultiplier() public view returns (uint256) {
        if (demandSensitivity == 0) return WAD;
        return WAD.add(transferCount.mul(WAD).div(demandSensitivity));
    }

    function nvpxPrice() public view returns (uint256) {
        return floorPrice()
            .mul(scarcityMultiplier()).div(WAD)
            .mul(demandMultiplier()).div(WAD);
    }

    function priceBreakdown() external view returns (
        uint256 fp, uint256 sm, uint256 dm, uint256 combined
    ) {
        fp = floorPrice(); sm = scarcityMultiplier();
        dm = demandMultiplier(); combined = nvpxPrice();
    }

    // ═════════════════════════════════════════════════════════════════
    //  MINTING  —  2 USDT → 1 NVPX
    // ═════════════════════════════════════════════════════════════════

    function mintWithUSDT(uint256 usdtAmount) external {
        require(!mintingClosed, "NovaPulse: minting closed");
        require(usdtAmount > 0, "NovaPulse: zero amount");

        uint256 nvpxToMint = usdtAmount.mul(WAD).div(USDT_PER_NVPX);
        require(nvpxToMint > 0, "NovaPulse: amount too small");

        uint256 remaining = MAX_SUPPLY.sub(totalMinted);
        require(remaining > 0, "NovaPulse: max supply reached");

        if (nvpxToMint > remaining) {
            nvpxToMint = remaining;
            usdtAmount = nvpxToMint.mul(USDT_PER_NVPX).div(WAD);
        }

        require(
            IERC20(USDT).transferFrom(msg.sender, address(this), usdtAmount),
            "NovaPulse: USDT transfer failed"
        );

        treasuryUSDT          = treasuryUSDT.add(usdtAmount);
        totalMinted           = totalMinted.add(nvpxToMint);
        _balances[msg.sender] = _balances[msg.sender].add(nvpxToMint);
        _totalSupply          = _totalSupply.add(nvpxToMint);

        emit Transfer(address(0), msg.sender, nvpxToMint);
        emit Minted(msg.sender, nvpxToMint, usdtAmount);

        if (totalMinted >= MAX_SUPPLY) {
            mintingClosed = true;
            emit MintingClosed(totalMinted);
        }
    }

    function remainingMintable() external view returns (uint256) {
        if (mintingClosed) return 0;
        return MAX_SUPPLY.sub(totalMinted);
    }

    function usdtCostFor(uint256 nvpxAmount) external pure returns (uint256) {
        return nvpxAmount.mul(USDT_PER_NVPX).div(WAD);
    }

    // ═════════════════════════════════════════════════════════════════
    //  ERC-20 CORE
    // ═════════════════════════════════════════════════════════════════

    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address a) public view override returns (uint256) { return _balances[a]; }
    function allowance(address o, address s) public view override returns (uint256) { return _allowances[o][s]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount); return true;
    }
    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount); return true;
    }
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 ca = _allowances[from][msg.sender];
        require(ca >= amount, "NovaPulse: exceeds allowance");
        unchecked { _approve(from, msg.sender, ca - amount); }
        _transfer(from, to, amount);
        return true;
    }
    function increaseAllowance(address s, uint256 v) external returns (bool) {
        _approve(msg.sender, s, _allowances[msg.sender][s].add(v)); return true;
    }
    function decreaseAllowance(address s, uint256 v) external returns (bool) {
        uint256 c = _allowances[msg.sender][s];
        require(c >= v, "NovaPulse: below zero");
        _approve(msg.sender, s, c - v); return true;
    }

    // ═════════════════════════════════════════════════════════════════
    //  TRANSFER ENGINE
    //
    //  Execution order (non-exempt transfers):
    //  ┌────┬──────────────────────────────────────────────────────────┐
    //  │ 1  │ swapping check  if true → bypass mechanics (Router cb)  │
    //  │ 2  │ transferCount++          demand rises → price rises      │
    //  │ 3  │ 1% auto-burn             supply falls → price rises      │
    //  │ 4  │ [SELL] 3% fee → accumulatedFeeNVPX (held in contract)   │
    //  │ 5  │ Net credited             recipient gets remainder        │
    //  │ 6  │ [BUY] Referral           L1/L2 deducted from buyer      │
    //  │ 7  │ [SELL] triggerSwap       swap if threshold reached       │
    //  └────┴──────────────────────────────────────────────────────────┘
    //
    //  BUY  (mainPair→buyer):  burn=1%, fee=0%, ref L1+L2 from buyer
    //  SELL (seller→mainPair): burn=1%, fee=3%→USDT auto-swap, no ref
    //  P2P  (wallet→wallet):   burn=1%, fee=0%, no ref
    // ═════════════════════════════════════════════════════════════════

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender    != address(0), "NovaPulse: from zero");
        require(recipient != address(0), "NovaPulse: to zero");
        require(_balances[sender] >= amount, "NovaPulse: insufficient balance");

        unchecked { _balances[sender] -= amount; }

        // ── Step 1: During auto-swap, bypass all mechanics ────────────
        // This handles the internal Router callback cleanly.
        if (swapping) {
            _balances[recipient] = _balances[recipient].add(amount);
            emit Transfer(sender, recipient, amount);
            return;
        }

        bool exemptSender    = hasRole(FEE_EXEMPT, sender);
        bool exemptRecipient = hasRole(FEE_EXEMPT, recipient);
        bool applyMechanics  = !(exemptSender && exemptRecipient);

        uint256 burnAmount = 0;
        uint256 feeAmount  = 0;

        if (applyMechanics) {

            // ── Step 2: Demand counter ─────────────────────────────────
            transferCount = transferCount.add(1);

            // ── Step 3: 1% auto-burn ──────────────────────────────────
            burnAmount = amount.mul(burnRatio).div(PRECISION);
            if (burnAmount > 0) {
                _totalSupply = _totalSupply.sub(burnAmount);
                emit Transfer(sender, address(0), burnAmount);
                emit Burned(sender, burnAmount);
                emit PriceSnapshot(
                    floorPrice(), scarcityMultiplier(),
                    demandMultiplier(), nvpxPrice()
                );
            }

            // ── Step 4: 3% sell fee → held in contract for auto-swap ──
            // Fee is credited to THIS CONTRACT's own balance.
            // _triggerFeeSwapIfReady() will swap it → USDT → your wallet.
            if (recipient == mainPair && mainPair != address(0)) {
                feeAmount = amount.mul(sellFeeRatio).div(PRECISION);
                if (feeAmount > 0) {
                    // Credit contract's own balance (it will be swapped)
                    _balances[address(this)] = _balances[address(this)].add(feeAmount);
                    accumulatedFeeNVPX       = accumulatedFeeNVPX.add(feeAmount);
                    emit Transfer(sender, address(this), feeAmount);
                    emit SellFeeTaken(sender, feeAmount);
                    emit FeeAccumulated(accumulatedFeeNVPX);
                }
            }
        }

        // ── Step 5: Credit recipient ──────────────────────────────────
        uint256 netAmount = amount - burnAmount - feeAmount;
        require(netAmount > 0, "NovaPulse: zero net after deductions");
        _balances[recipient] = _balances[recipient].add(netAmount);
        emit Transfer(sender, recipient, netAmount);

        // ── Step 6: Referral rewards — DEX buys only ──────────────────
        if (
            applyMechanics          &&
            sender   == mainPair    &&
            mainPair != address(0)  &&
            !exemptRecipient
        ) {
            _distributeReferralRewards(recipient, amount);
        }

        // ── Step 7: Trigger auto-swap if threshold reached ────────────
        // Only fires on sells (when feeAmount > 0) and only if safe.
        if (feeAmount > 0) {
            _triggerFeeSwapIfReady();
        }
    }

    // ═════════════════════════════════════════════════════════════════
    //  MANUAL BURN
    // ═════════════════════════════════════════════════════════════════

    function burn(uint256 amount) external {
        require(_balances[msg.sender] >= amount, "NovaPulse: exceeds balance");
        _balances[msg.sender] -= amount;
        _totalSupply          -= amount;
        emit Transfer(msg.sender, address(0), amount);
        emit Burned(msg.sender, amount);
        emit PriceSnapshot(floorPrice(), scarcityMultiplier(), demandMultiplier(), nvpxPrice());
    }

    function burnFrom(address account, uint256 amount) external {
        uint256 ca = _allowances[account][msg.sender];
        require(ca >= amount, "NovaPulse: burn exceeds allowance");
        unchecked { _approve(account, msg.sender, ca - amount); }
        require(_balances[account] >= amount, "NovaPulse: burn exceeds balance");
        _balances[account] -= amount;
        _totalSupply       -= amount;
        emit Transfer(account, address(0), amount);
        emit Burned(account, amount);
        emit PriceSnapshot(floorPrice(), scarcityMultiplier(), demandMultiplier(), nvpxPrice());
    }

    // ═════════════════════════════════════════════════════════════════
    //  ADMIN CONFIG  (all locked after goLive())
    // ═════════════════════════════════════════════════════════════════

    /// @notice *** SET YOUR FEE WALLET HERE before goLive() ***
    function setFeeReceiverWallet(address wallet)
        external onlyRole(DEFAULT_ADMIN_ROLE) notLive
    {
        require(wallet != address(0), "NovaPulse: zero address");
        emit FeeReceiverWalletChanged(feeReceiverWallet, wallet);
        // Update FEE_EXEMPT: remove old, add new
        _revokeRole(FEE_EXEMPT, feeReceiverWallet);
        _grantRole(FEE_EXEMPT, wallet);
        feeReceiverWallet = wallet;
    }

    function setMainPair(address pair)
        external onlyRole(DEFAULT_ADMIN_ROLE) notLive
    {
        require(pair != address(0), "NovaPulse: zero address");
        mainPair = pair;
        // Grant FEE_EXEMPT to the pair so treasury mints bypass fees
        _grantRole(FEE_EXEMPT, pair);
        emit MainPairSet(pair);
    }

    function setSwapThreshold(uint256 threshold)
        external onlyRole(DEFAULT_ADMIN_ROLE) notLive
    {
        require(threshold > 0, "NovaPulse: zero threshold");
        swapThreshold = threshold;
        emit SwapThresholdChanged(threshold);
    }

    function setSwapSlippage(uint256 bps)
        external onlyRole(DEFAULT_ADMIN_ROLE) notLive
    {
        require(bps <= 1_000, "NovaPulse: slippage > 10%");
        swapSlippageBps = bps;
        emit SwapSlippageChanged(bps);
    }

    function setMinLiquidity(uint256 minUSDT)
        external onlyRole(DEFAULT_ADMIN_ROLE) notLive
    {
        minLiquidityUSDT = minUSDT;
        emit MinLiquidityChanged(minUSDT);
    }

    /// @param feeType  0 = sellFee  |  1 = burnRatio
    function setRatio(uint8 feeType, uint256 ratio)
        external onlyRole(DEFAULT_ADMIN_ROLE) notLive
    {
        require(ratio <= PRECISION, "NovaPulse: exceeds 100%");
        if (feeType == 0) { sellFeeRatio = ratio; emit SellFeeRatioChanged(ratio); }
        else              { burnRatio    = ratio; emit BurnRatioChanged(ratio);    }
    }

    function setRefRatios(uint256 l1, uint256 l2)
        external onlyRole(DEFAULT_ADMIN_ROLE) notLive
    {
        require(l1.add(l2) <= 10_000, "NovaPulse: referral > 10%");
        refL1Ratio = l1; refL2Ratio = l2;
        emit RefRatiosChanged(l1, l2);
    }

    function setDemandSensitivity(uint256 sensitivity)
        external onlyRole(DEFAULT_ADMIN_ROLE) notLive
    {
        require(sensitivity > 0, "NovaPulse: zero");
        demandSensitivity = sensitivity;
        emit DemandSensitivityChanged(sensitivity);
    }

    function withdrawTreasury(address to, uint256 amount)
        external onlyRole(DEFAULT_ADMIN_ROLE) notLive
    {
        require(to     != address(0),  "NovaPulse: zero address");
        require(amount <= treasuryUSDT,"NovaPulse: exceeds treasury");
        treasuryUSDT = treasuryUSDT.sub(amount);
        require(IERC20(USDT).transfer(to, amount), "NovaPulse: USDT failed");
        emit TreasuryWithdrawn(to, amount);
    }

    // ═════════════════════════════════════════════════════════════════
    //  VIEW  HELPERS
    // ═════════════════════════════════════════════════════════════════

    function tokenStats() external view returns (
        uint256 circulatingSupply,
        uint256 totalBurned,
        uint256 currentPrice,
        uint256 floor,
        uint256 scarcityMult,
        uint256 demandMult,
        uint256 treasury,
        uint256 minted,
        uint256 txCount,
        uint256 pendingFeeNVPX,
        bool    contractIsLive,
        bool    isMintingClosed
    ) {
        circulatingSupply = _totalSupply;
        totalBurned       = totalMinted > _totalSupply ? totalMinted - _totalSupply : 0;
        floor             = floorPrice();
        scarcityMult      = scarcityMultiplier();
        demandMult        = demandMultiplier();
        currentPrice      = nvpxPrice();
        treasury          = treasuryUSDT;
        minted            = totalMinted;
        txCount           = transferCount;
        pendingFeeNVPX    = accumulatedFeeNVPX;
        contractIsLive    = isLive;
        isMintingClosed   = mintingClosed;
    }

    function referralProgramStats() external view returns (
        uint256 totalDistributed,
        uint256 totalRefTxns,
        uint256 l1Pct,
        uint256 l2Pct
    ) {
        totalDistributed = totalReferralRewardsDistributed;
        totalRefTxns     = totalReferralTransactions;
        l1Pct            = refL1Ratio;
        l2Pct            = refL2Ratio;
    }

    function getReferralProfile(address account) external view returns (
        address level1Referrer,
        address level2Referrer,
        uint256 totalEarnedNVPX,
        uint256 totalReferred,
        uint256 referralTxCount
    ) {
        level1Referrer  = referrer[account];
        level2Referrer  = referrer[referrer[account]];
        totalEarnedNVPX = referralStats[account].totalEarned;
        totalReferred   = referralStats[account].totalReferred;
        referralTxCount = referralStats[account].referralTxCount;
    }

    function simulateBuy(address buyer, uint256 grossBuyAmount) external view returns (
        uint256 burnDeduction,
        uint256 l1Reward,
        uint256 l2Reward,
        uint256 buyerReceives,
        address l1Referrer,
        address l2Referrer
    ) {
        burnDeduction = grossBuyAmount.mul(burnRatio).div(PRECISION);
        l1Referrer    = referrer[buyer];
        l2Referrer    = referrer[l1Referrer];
        l1Reward = (l1Referrer != address(0) && _balances[l1Referrer] > 0)
            ? grossBuyAmount.mul(refL1Ratio).div(PRECISION) : 0;
        l2Reward = (l2Referrer != address(0) && _balances[l2Referrer] > 0)
            ? grossBuyAmount.mul(refL2Ratio).div(PRECISION) : 0;
        uint256 total = burnDeduction.add(l1Reward).add(l2Reward);
        buyerReceives = grossBuyAmount > total ? grossBuyAmount - total : 0;
    }

    function autoSwapStats() external view returns (
        uint256 accumulated,
        uint256 threshold,
        uint256 slippageBps,
        uint256 minLiquidity,
        address feeWallet,
        bool    liquidityOk
    ) {
        accumulated  = accumulatedFeeNVPX;
        threshold    = swapThreshold;
        slippageBps  = swapSlippageBps;
        minLiquidity = minLiquidityUSDT;
        feeWallet    = feeReceiverWallet;
        liquidityOk  = mainPair != address(0) && _hasSufficientLiquidity();
    }

    function launchInfo() external view returns (
        bool    live,
        bool    renounced,
        uint256 launchedAt,
        address pair,
        address feeWallet,
        string  memory status
    ) {
        live      = isLive;
        renounced = ownershipRenounced;
        launchedAt = launchTimestamp;
        pair      = mainPair;
        feeWallet = feeReceiverWallet;
        status    = isLive
            ? "LIVE: open-source, ownership renounced, config locked forever"
            : "PRE-LAUNCH: admin config still possible";
    }

    // ── Internal ─────────────────────────────────────────────────────

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner   != address(0), "NovaPulse: approve from zero");
        require(spender != address(0), "NovaPulse: approve to zero");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}
