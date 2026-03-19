// SPDX-License-Identifier: MIT
// ════════════════════════════════════════════════════════════════════════
//
//   NovaPulse Token  (NVPX)  —  v7  |  Production  |  Open-Source
//   Network  : BNB Smart Chain (BSC) Mainnet
//   License  : MIT
//
// ════════════════════════════════════════════════════════════════════════
//
//   TREASURY MODEL  (How Tokens & USDT Flow)
//   ─────────────────────────────────────────────────────────────────────
//
//   AT DEPLOYMENT:
//   • ALL 21,000,000 NVPX are minted ONCE into the TREASURY WALLET
//   • Treasury wallet = this contract address itself
//   • The contract owns all tokens at start
//   • No tokens go to the deployer
//   • No pre-distribution, no team allocation, nothing
//
//   WHEN A USER WANTS NVPX:
//   • User calls swapUSDTforNVPX(usdtAmount)
//   • User sends USDT → contract treasury
//   • Contract releases NVPX from treasury → user wallet
//   • Rate: 2 USDT = 1 NVPX (fixed)
//   • USDT stays locked in contract FOREVER as price floor backing
//   • NVPX leaves treasury only on paid demand — never pre-distributed
//
//   TREASURY WALLET:
//   • IS the contract address itself (address(this))
//   • Holds all unsold NVPX tokens
//   • Holds all USDT paid by users
//   • After goLive() — ownership renounced — nobody controls it
//   • Purely autonomous — runs by math forever
//
//   EXAMPLE FLOW:
//   ┌────────────────────────────────────────────────────────────┐
//   │  Deploy  →  21,000,000 NVPX sit in contract treasury       │
//   │                                                            │
//   │  Alice sends 200 USDT                                      │
//   │  Contract releases 100 NVPX to Alice  (2 USDT = 1 NVPX)   │
//   │  200 USDT stays locked in treasury forever                 │
//   │                                                            │
//   │  Bob sends 400 USDT                                        │
//   │  Contract releases 200 NVPX to Bob                        │
//   │  400 USDT stays locked in treasury forever                 │
//   │                                                            │
//   │  Treasury now holds:                                       │
//   │    20,999,700 NVPX (still unsold)                         │
//   │    600 USDT (locked — backs floor price)                   │
//   └────────────────────────────────────────────────────────────┘
//
//   PRICE FORMULA  (3-Force Bonding Curve):
//   ─────────────────────────────────────────────────────────────────────
//   nvpxPrice = floorPrice × scarcityMultiplier × demandMultiplier
//
//   floorPrice        = lockedUSDT / circulatingSupply
//   scarcityMultiplier= MAX_SUPPLY / circulatingSupply
//   demandMultiplier  = 1 + (transferCount / demandSensitivity)
//
//   TOKENOMICS:
//   ─────────────────────────────────────────────────────────────────────
//   Max Supply      : 21,000,000 NVPX (hard cap, Bitcoin-like)
//   Swap Rate       : 2 USDT = 1 NVPX (fixed, on-demand only)
//   Buy Fee         : 0%  (zero barrier to entry)
//   Sell Fee        : 3%  (auto-swapped to USDT → fee wallet)
//   Auto-Burn       : 1%  (every transfer, forever)
//   Referral L1     : 3%  (direct referrer, from buyer's amount)
//   Referral L2     : 1.5%(referrer's referrer, from buyer's amount)
//   Default Referrer: 0x131D15d8E58900c934E5C6BE2e9054062CCfB427
//   Fee Wallet      : 0x9504F94B3aE36B84e4a4dFA03BD1851737acf5Ac
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
//  PancakeSwap Interfaces
// ─────────────────────────────────────────────────────────────────────────
interface IPancakeRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn, uint256 amountOutMin,
        address[] calldata path, address to, uint256 deadline
    ) external;
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts);
}

interface IPancakePair {
    function getReserves() external view returns (uint112,uint112,uint32);
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
        if (a == 0) return 0; uint256 c = a * b;
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
    uint256 private constant _NOT = 1; uint256 private constant _IN = 2;
    uint256 private _s; constructor() { _s = _NOT; }
    modifier nonReentrant() {
        require(_s != _IN, "ReentrancyGuard: reentrant"); _s = _IN; _; _s = _NOT;
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
        require(_roles[role][msg.sender], "AccessControl: missing role"); _;
    }
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }
    function _grantRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) { _roles[role][account] = true; emit RoleGranted(role, account, msg.sender); }
    }
    function _revokeRole(bytes32 role, address account) internal {
        if (_roles[role][account]) { _roles[role][account] = false; emit RoleRevoked(role, account, msg.sender); }
    }
    function grantRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) { _grantRole(role, account); }
    function revokeRole(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) { _revokeRole(role, account); }
}

interface IFeeReceiver { function onFeeReceived(uint256 amount) external; }

// ════════════════════════════════════════════════════════════════════════
//  NovaPulse — Main Contract  (v7)
// ════════════════════════════════════════════════════════════════════════
contract NovaPulse is IERC20, AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    // ── Token Metadata ───────────────────────────────────────────────
    string  public constant name     = "NovaPulse";
    string  public constant symbol   = "NVPX";
    uint8   public constant decimals = 18;
    string  public constant version  = "7.0.0";
    uint256 private constant WAD     = 1e18;

    // ── Roles ────────────────────────────────────────────────────────
    bytes32 public constant FEE_EXEMPT = keccak256("FEE_EXEMPT");

    // ── Supply ───────────────────────────────────────────────────────
    uint256 public constant MAX_SUPPLY    = 21_000_000 * WAD;  // 21M hard cap
    uint256 public constant USDT_PER_NVPX = 2 * WAD;           // 2 USDT = 1 NVPX

    // _totalSupply = ALL tokens ever minted (21M at deploy, never increases)
    // circulatingSupply = tokens outside treasury = totalSupply - treasuryBalance
    uint256 private _totalSupply;

    mapping(address => uint256)                     private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ── Treasury ─────────────────────────────────────────────────────
    // The treasury IS this contract (address(this)).
    // treasuryBalance = NVPX tokens still held by contract, not yet sold.
    // lockedUSDT      = USDT received from swaps, locked forever as price floor.

    uint256 public lockedUSDT;       // USDT locked in treasury (price floor backing)
    uint256 public totalSoldNVPX;    // cumulative NVPX released from treasury to users
    bool    public swapClosed;       // true when all 21M NVPX have been sold

    // ── USDT contract ────────────────────────────────────────────────
    /// @notice BSC Mainnet USDT: 0x55d398326f99059fF775485246999027B3197955
    address public immutable USDT;

    // ── PancakeSwap ──────────────────────────────────────────────────
    address public constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public mainPair;   // NVPX/USDT LP pair — set before goLive()

    // ── Fee Config ───────────────────────────────────────────────────
    uint256 public constant PRECISION = 100_000;
    uint256 public sellFeeRatio       = 3_000;   // 3%  sell fee
    uint256 public burnRatio          = 1_000;   // 1%  auto-burn

    // ── Auto-Swap Engine ─────────────────────────────────────────────
    /// @notice YOUR wallet — receives USDT from auto-swapped sell fees
    address public feeReceiverWallet  = 0x9504F94B3aE36B84e4a4dFA03BD1851737acf5Ac;
    uint256 public accumulatedFeeNVPX;           // NVPX fees pending swap
    uint256 public swapThreshold      = 20 * WAD;// min NVPX before auto-swap
    uint256 public swapSlippageBps    = 200;     // 2% slippage tolerance
    uint256 public minLiquidityUSDT   = 1_000 * WAD;
    bool    private swapping;

    // ── Price Model ──────────────────────────────────────────────────
    uint256 public transferCount;
    uint256 public demandSensitivity  = 10_000;

    // ── Referral System ──────────────────────────────────────────────
    /// @notice DEFAULT_REFERRER earns L1 reward when buyer has no referrer
    address public constant DEFAULT_REFERRER = 0x131D15d8E58900c934E5C6BE2e9054062CCfB427;
    uint256 public refL1Ratio = 3_000;   // 3.0%
    uint256 public refL2Ratio = 1_500;   // 1.5%

    mapping(address => address) public referrer;
    struct ReferralStats {
        uint256 totalEarned;
        uint256 totalReferred;
        uint256 referralTxCount;
    }
    mapping(address => ReferralStats) public referralStats;
    uint256 public totalReferralRewardsDistributed;
    uint256 public totalReferralTransactions;

    // ── Go-Live State ────────────────────────────────────────────────
    bool    public isLive;
    bool    public ownershipRenounced;
    uint256 public launchTimestamp;

    // ── Events ───────────────────────────────────────────────────────
    event TokensSwapped(address indexed buyer, uint256 usdtPaid, uint256 nvpxReceived);
    event Burned(address indexed from, uint256 amount);
    event SellFeeTaken(address indexed seller, uint256 feeNVPX);
    event PriceSnapshot(uint256 floor, uint256 scarcity, uint256 demand, uint256 combined);
    event FeeSwapExecuted(uint256 nvpxSwapped, uint256 usdtReceived, address indexed sentTo);
    event FeeSwapSkipped(string reason);
    event FeeAccumulated(uint256 newTotal);
    event ReferrerRegistered(address indexed referee, address indexed ref);
    event ReferralRewardPaid(address indexed buyer, address indexed recipient, uint8 level, uint256 amount);
    event ReferralRewardSkipped(address indexed recipient, uint8 level, string reason);
    event MainPairSet(address indexed pair);
    event FeeReceiverWalletChanged(address indexed old_, address indexed new_);
    event SwapThresholdChanged(uint256 v);
    event SwapSlippageChanged(uint256 v);
    event MinLiquidityChanged(uint256 v);
    event SellFeeRatioChanged(uint256 v);
    event BurnRatioChanged(uint256 v);
    event RefRatiosChanged(uint256 l1, uint256 l2);
    event DemandSensitivityChanged(uint256 v);
    event SwapClosed(uint256 totalSold);
    event ProjectLaunched(
        address indexed deployer, uint256 ts,
        uint256 treasuryNVPX, address pair, address feeWallet,
        string message
    );
    event OwnershipRenounced(address indexed prev);

    // ── Constructor ──────────────────────────────────────────────────
    /// @notice Deploys contract and mints ALL 21M NVPX into treasury (this contract).
    ///         No tokens go to deployer. No pre-distribution. Ever.
    /// @param _usdt  0x55d398326f99059fF775485246999027B3197955
    constructor(address _usdt) {
        require(_usdt != address(0), "NovaPulse: zero USDT");
        USDT = _usdt;

        // ── Mint ALL 21M NVPX into treasury (this contract) ──────────
        // The contract IS the treasury.
        // Tokens sit here until users pay USDT to release them.
        _totalSupply             = MAX_SUPPLY;
        _balances[address(this)] = MAX_SUPPLY;
        emit Transfer(address(0), address(this), MAX_SUPPLY);

        // ── Roles ─────────────────────────────────────────────────────
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEE_EXEMPT, msg.sender);
        _grantRole(FEE_EXEMPT, feeReceiverWallet);
        _grantRole(FEE_EXEMPT, PANCAKE_ROUTER);
        _grantRole(FEE_EXEMPT, address(this));  // treasury is exempt from fees
    }

    // ── Modifiers ────────────────────────────────────────────────────
    modifier notLive() {
        require(!isLive, "NovaPulse: config locked after goLive");
        _;
    }

    // ════════════════════════════════════════════════════════════════
    //  VIEW HELPERS — Treasury & Supply
    // ════════════════════════════════════════════════════════════════

    /// @notice NVPX tokens still held in treasury (unsold)
    function treasuryBalance() public view returns (uint256) {
        return _balances[address(this)];
    }

    /// @notice NVPX tokens in circulation (sold to users, excluding treasury)
    function circulatingSupply() public view returns (uint256) {
        return _totalSupply.sub(_balances[address(this)]);
    }

    /// @notice NVPX tokens remaining available for purchase
    function availableForSwap() external view returns (uint256) {
        if (swapClosed) return 0;
        return _balances[address(this)] > accumulatedFeeNVPX
            ? _balances[address(this)].sub(accumulatedFeeNVPX)
            : 0;
    }

    // ════════════════════════════════════════════════════════════════
    //  PRICE MODEL  (3-Force Bonding Curve)
    //
    //  Uses circulatingSupply (tokens outside treasury) — NOT totalSupply
    //  This way, unsold treasury tokens don't dilute the price.
    //  Price only reflects tokens actually in user hands.
    // ════════════════════════════════════════════════════════════════

    /// @notice USDT locked per circulating NVPX — the floor price
    function floorPrice() public view returns (uint256) {
        uint256 circ = circulatingSupply();
        if (circ == 0) return USDT_PER_NVPX;
        return lockedUSDT.mul(WAD).div(circ);
    }

    /// @notice Scarcity multiplier — grows as circulating supply shrinks via burns
    function scarcityMultiplier() public view returns (uint256) {
        uint256 circ = circulatingSupply();
        if (circ == 0) return WAD;
        return MAX_SUPPLY.mul(WAD).div(circ);
    }

    /// @notice Demand multiplier — grows with every transfer
    function demandMultiplier() public view returns (uint256) {
        if (demandSensitivity == 0) return WAD;
        return WAD.add(transferCount.mul(WAD).div(demandSensitivity));
    }

    /// @notice Combined bonding curve price in USDT per NVPX
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

    // ════════════════════════════════════════════════════════════════
    //  SWAP USDT → NVPX  (the ONLY way tokens leave the treasury)
    //
    //  User pays USDT → treasury releases NVPX to user.
    //  USDT is locked in contract forever as price floor backing.
    //  No minting occurs here — tokens already exist in treasury.
    //  Rate: 2 USDT = 1 NVPX (fixed)
    //
    //  HOW TO CALL:
    //  1. USDT.approve(NovaPulseAddress, usdtAmount)
    //  2. NovaPulse.swapUSDTforNVPX(usdtAmount)
    // ════════════════════════════════════════════════════════════════

    function swapUSDTforNVPX(uint256 usdtAmount) external nonReentrant {
        require(!swapClosed,  "NovaPulse: all tokens have been distributed");
        require(usdtAmount > 0, "NovaPulse: zero USDT amount");

        // Calculate NVPX to release: usdtAmount / 2
        uint256 nvpxToRelease = usdtAmount.mul(WAD).div(USDT_PER_NVPX);
        require(nvpxToRelease > 0, "NovaPulse: amount too small");

        // Available treasury tokens (excluding accumulated fee NVPX)
        uint256 available = _balances[address(this)] > accumulatedFeeNVPX
            ? _balances[address(this)].sub(accumulatedFeeNVPX)
            : 0;
        require(available > 0, "NovaPulse: treasury empty");

        // Cap to available tokens
        if (nvpxToRelease > available) {
            nvpxToRelease = available;
            usdtAmount    = nvpxToRelease.mul(USDT_PER_NVPX).div(WAD);
        }

        // Pull USDT from user into treasury (this contract)
        require(
            IERC20(USDT).transferFrom(msg.sender, address(this), usdtAmount),
            "NovaPulse: USDT transfer failed — approve first"
        );

        // Lock USDT as price floor
        lockedUSDT    = lockedUSDT.add(usdtAmount);
        totalSoldNVPX = totalSoldNVPX.add(nvpxToRelease);

        // Transfer NVPX from treasury (this contract) to buyer
        // Uses internal _transfer so burn + referral still fire
        _releaseFromTreasury(msg.sender, nvpxToRelease);

        emit TokensSwapped(msg.sender, usdtAmount, nvpxToRelease);

        // Close swap gate if treasury is fully sold
        if (_balances[address(this)] <= accumulatedFeeNVPX) {
            swapClosed = true;
            emit SwapClosed(totalSoldNVPX);
        }
    }

    /// @notice How much USDT is needed to receive a given NVPX amount
    function usdtCostFor(uint256 nvpxAmount) external pure returns (uint256) {
        return nvpxAmount.mul(USDT_PER_NVPX).div(WAD);
    }

    // ════════════════════════════════════════════════════════════════
    //  RELEASE FROM TREASURY (internal)
    //  Moves NVPX from contract treasury to buyer.
    //  Triggers burn + referral but NOT sell fee (this is a buy).
    // ════════════════════════════════════════════════════════════════

    function _releaseFromTreasury(address buyer, uint256 amount) internal {
        require(_balances[address(this)] >= amount, "NovaPulse: treasury insufficient");

        // Deduct from treasury
        unchecked { _balances[address(this)] -= amount; }

        // 1% auto-burn — taken from the release amount
        uint256 burnAmount = amount.mul(burnRatio).div(PRECISION);
        if (burnAmount > 0) {
            _totalSupply = _totalSupply.sub(burnAmount);
            emit Transfer(address(this), address(0), burnAmount);
            emit Burned(address(this), burnAmount);
            emit PriceSnapshot(floorPrice(), scarcityMultiplier(), demandMultiplier(), nvpxPrice());
        }

        // Demand counter
        transferCount = transferCount.add(1);

        // Net NVPX to buyer after burn
        uint256 netAmount = amount.sub(burnAmount);
        require(netAmount > 0, "NovaPulse: zero net after burn");

        _balances[buyer] = _balances[buyer].add(netAmount);
        emit Transfer(address(this), buyer, netAmount);

        // Distribute referral rewards from buyer's received amount
        _distributeReferralRewards(buyer, netAmount);
    }

    // ════════════════════════════════════════════════════════════════
    //  ERC-20 CORE
    // ════════════════════════════════════════════════════════════════

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
        _transfer(from, to, amount); return true;
    }
    function increaseAllowance(address s, uint256 v) external returns (bool) {
        _approve(msg.sender, s, _allowances[msg.sender][s].add(v)); return true;
    }
    function decreaseAllowance(address s, uint256 v) external returns (bool) {
        uint256 c = _allowances[msg.sender][s];
        require(c >= v, "NovaPulse: below zero");
        _approve(msg.sender, s, c - v); return true;
    }

    // ════════════════════════════════════════════════════════════════
    //  TRANSFER ENGINE  (wallet-to-wallet and DEX sells)
    //
    //  NOTE: Buying from PancakeSwap DEX = mainPair sends tokens
    //        to buyer. This path goes through _transfer.
    //        DEX sells = user sends to mainPair.
    //
    //  STEPS PER NON-EXEMPT TRANSFER:
    //  1. transferCount++       → demand rises → price rises
    //  2. 1% auto-burn          → supply falls → price rises
    //  3. 3% sell fee [sells]   → accumulated for auto-swap to USDT
    //  4. Net to recipient
    //  5. Referral [DEX buys]   → L1+L2 deducted from buyer
    // ════════════════════════════════════════════════════════════════

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender    != address(0), "NovaPulse: from zero");
        require(recipient != address(0), "NovaPulse: to zero");
        require(_balances[sender] >= amount, "NovaPulse: insufficient balance");

        unchecked { _balances[sender] -= amount; }

        // During auto-swap: bypass all mechanics for internal router call
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

            // 1. Demand counter
            transferCount = transferCount.add(1);

            // 2. 1% auto-burn
            burnAmount = amount.mul(burnRatio).div(PRECISION);
            if (burnAmount > 0) {
                _totalSupply = _totalSupply.sub(burnAmount);
                emit Transfer(sender, address(0), burnAmount);
                emit Burned(sender, burnAmount);
                emit PriceSnapshot(floorPrice(), scarcityMultiplier(), demandMultiplier(), nvpxPrice());
            }

            // 3. 3% sell fee (DEX sells only → accumulated for USDT auto-swap)
            if (recipient == mainPair && mainPair != address(0)) {
                feeAmount = amount.mul(sellFeeRatio).div(PRECISION);
                if (feeAmount > 0) {
                    _balances[address(this)] = _balances[address(this)].add(feeAmount);
                    accumulatedFeeNVPX       = accumulatedFeeNVPX.add(feeAmount);
                    emit Transfer(sender, address(this), feeAmount);
                    emit SellFeeTaken(sender, feeAmount);
                    emit FeeAccumulated(accumulatedFeeNVPX);
                }
            }
        }

        // 4. Credit recipient
        uint256 netAmount = amount - burnAmount - feeAmount;
        require(netAmount > 0, "NovaPulse: zero net");
        _balances[recipient] = _balances[recipient].add(netAmount);
        emit Transfer(sender, recipient, netAmount);

        // 5. Referral rewards — DEX buys only (mainPair → buyer)
        if (applyMechanics && sender == mainPair && mainPair != address(0) && !exemptRecipient) {
            _distributeReferralRewards(recipient, amount);
        }

        // 6. Trigger auto-swap if fee threshold reached
        if (feeAmount > 0) _triggerFeeSwapIfReady();
    }

    // ════════════════════════════════════════════════════════════════
    //  AUTO-SWAP ENGINE
    // ════════════════════════════════════════════════════════════════

    function _triggerFeeSwapIfReady() internal {
        if (accumulatedFeeNVPX < swapThreshold) return;
        if (swapping) return;
        if (mainPair == address(0)) return;
        if (!_hasSufficientLiquidity()) { emit FeeSwapSkipped("insufficient liquidity"); return; }
        uint256 toSwap = accumulatedFeeNVPX;
        accumulatedFeeNVPX = 0;
        swapping = true;
        _executeSwap(toSwap);
        swapping = false;
    }

    function _hasSufficientLiquidity() internal view returns (bool) {
        try IPancakePair(mainPair).getReserves() returns (uint112 r0, uint112 r1, uint32) {
            address t0 = IPancakePair(mainPair).token0();
            uint256 usdtR = (t0 == USDT) ? uint256(r0) : uint256(r1);
            return usdtR >= minLiquidityUSDT;
        } catch { return false; }
    }

    function _executeSwap(uint256 nvpxAmount) internal {
        address[] memory path = new address[](2);
        path[0] = address(this); path[1] = USDT;
        uint256 expected = 0;
        try IPancakeRouter(PANCAKE_ROUTER).getAmountsOut(nvpxAmount, path) returns (uint256[] memory amounts) {
            expected = amounts[1];
        } catch {
            accumulatedFeeNVPX = accumulatedFeeNVPX.add(nvpxAmount);
            emit FeeSwapSkipped("getAmountsOut failed"); return;
        }
        if (expected == 0) {
            accumulatedFeeNVPX = accumulatedFeeNVPX.add(nvpxAmount);
            emit FeeSwapSkipped("zero expected output"); return;
        }
        uint256 minOut = expected.mul(uint256(10_000).sub(swapSlippageBps)).div(10_000);
        _allowances[address(this)][PANCAKE_ROUTER] = nvpxAmount;
        emit Approval(address(this), PANCAKE_ROUTER, nvpxAmount);
        try IPancakeRouter(PANCAKE_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            nvpxAmount, minOut, path, feeReceiverWallet, block.timestamp + 300
        ) {
            emit FeeSwapExecuted(nvpxAmount, expected, feeReceiverWallet);
        } catch {
            accumulatedFeeNVPX = accumulatedFeeNVPX.add(nvpxAmount);
            emit FeeSwapSkipped("swap execution failed");
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  REFERRAL REGISTRATION
    // ════════════════════════════════════════════════════════════════

    function registerReferrer(address _referrer) external {
        require(_referrer != address(0),             "NovaPulse: zero address");
        require(_referrer != msg.sender,             "NovaPulse: no self-referral");
        require(referrer[msg.sender] == address(0),  "NovaPulse: already set");
        require(referrer[_referrer] != msg.sender,   "NovaPulse: circular chain");
        require(_balances[_referrer] > 0,            "NovaPulse: referrer holds no NVPX");
        referrer[msg.sender] = _referrer;
        referralStats[_referrer].totalReferred = referralStats[_referrer].totalReferred.add(1);
        emit ReferrerRegistered(msg.sender, _referrer);
    }

    // ════════════════════════════════════════════════════════════════
    //  REFERRAL REWARD ENGINE (internal)
    //  Rewards deducted from buyer's received amount.
    //  Falls back to DEFAULT_REFERRER when buyer has no referrer.
    //  Zero new tokens created. Zero supply inflation.
    // ════════════════════════════════════════════════════════════════

    function _distributeReferralRewards(address buyer, uint256 grossBuy) internal {
        address l1 = referrer[buyer];
        if (l1 == address(0)) l1 = DEFAULT_REFERRER;
        if (l1 == buyer) return;

        totalReferralTransactions = totalReferralTransactions.add(1);

        // Level 1 — 3%
        uint256 l1r = grossBuy.mul(refL1Ratio).div(PRECISION);
        if (l1r > 0) {
            if (_balances[l1] == 0) { emit ReferralRewardSkipped(l1, 1, "zero balance"); }
            else if (_balances[buyer] < l1r) { emit ReferralRewardSkipped(l1, 1, "buyer low balance"); }
            else {
                _balances[buyer] = _balances[buyer].sub(l1r);
                _balances[l1]    = _balances[l1].add(l1r);
                referralStats[l1].totalEarned     = referralStats[l1].totalEarned.add(l1r);
                referralStats[l1].referralTxCount = referralStats[l1].referralTxCount.add(1);
                totalReferralRewardsDistributed   = totalReferralRewardsDistributed.add(l1r);
                emit Transfer(buyer, l1, l1r);
                emit ReferralRewardPaid(buyer, l1, 1, l1r);
            }
        }

        // Level 2 — 1.5%
        address l2 = referrer[l1];
        if (l2 == address(0)) return;
        uint256 l2r = grossBuy.mul(refL2Ratio).div(PRECISION);
        if (l2r > 0) {
            if (_balances[l2] == 0) { emit ReferralRewardSkipped(l2, 2, "zero balance"); }
            else if (_balances[buyer] < l2r) { emit ReferralRewardSkipped(l2, 2, "buyer low balance"); }
            else {
                _balances[buyer] = _balances[buyer].sub(l2r);
                _balances[l2]    = _balances[l2].add(l2r);
                referralStats[l2].totalEarned     = referralStats[l2].totalEarned.add(l2r);
                referralStats[l2].referralTxCount = referralStats[l2].referralTxCount.add(1);
                totalReferralRewardsDistributed   = totalReferralRewardsDistributed.add(l2r);
                emit Transfer(buyer, l2, l2r);
                emit ReferralRewardPaid(buyer, l2, 2, l2r);
            }
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  MANUAL BURN
    // ════════════════════════════════════════════════════════════════

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

    // ════════════════════════════════════════════════════════════════
    //  SIMULATE SWAP  (read-only preview)
    // ════════════════════════════════════════════════════════════════

    function simulateSwap(address buyer, uint256 usdtAmount) external view returns (
        uint256 grossNVPX,     // NVPX released from treasury
        uint256 burnDeduction, // 1% burned
        uint256 l1Reward,      // 3% to L1 referrer
        uint256 l2Reward,      // 1.5% to L2 referrer
        uint256 buyerReceives, // net NVPX buyer gets
        address l1Referrer,
        address l2Referrer
    ) {
        grossNVPX     = usdtAmount.mul(WAD).div(USDT_PER_NVPX);
        burnDeduction = grossNVPX.mul(burnRatio).div(PRECISION);
        uint256 net   = grossNVPX.sub(burnDeduction);

        l1Referrer = referrer[buyer];
        if (l1Referrer == address(0)) l1Referrer = DEFAULT_REFERRER;
        l2Referrer = referrer[l1Referrer];

        l1Reward = (_balances[l1Referrer] > 0)
            ? net.mul(refL1Ratio).div(PRECISION) : 0;
        l2Reward = (l2Referrer != address(0) && _balances[l2Referrer] > 0)
            ? net.mul(refL2Ratio).div(PRECISION) : 0;

        uint256 total = l1Reward.add(l2Reward);
        buyerReceives = net > total ? net - total : 0;
    }

    // ════════════════════════════════════════════════════════════════
    //  GO-LIVE  —  ONE CLICK, PERMANENT, IRREVERSIBLE
    // ════════════════════════════════════════════════════════════════

    /// @notice Call once when project is ready.
    ///         PRE-CONDITIONS:
    ///         ✓ setMainPair(pancakeswapPairAddress)
    ///         ✓ Verify feeReceiverWallet is correct
    ///         ✓ Verify all ratios
    ///         ✓ Add initial liquidity on PancakeSwap
    ///         ✓ Submit source to BscScan → Verify & Publish
    ///
    ///         AFTER goLive():
    ///         • Ownership permanently renounced
    ///         • All config locked forever
    ///         • Contract 100% autonomous
    function goLive() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!isLive,                "NovaPulse: already live");
        require(mainPair != address(0), "NovaPulse: setMainPair first");

        isLive             = true;
        ownershipRenounced = true;
        launchTimestamp    = block.timestamp;

        address deployer = msg.sender;
        _revokeRole(DEFAULT_ADMIN_ROLE, deployer);

        emit ProjectLaunched(
            deployer, launchTimestamp,
            _balances[address(this)], mainPair, feeReceiverWallet,
            "NovaPulse LIVE. Treasury holds all unsold NVPX. Ownership renounced forever."
        );
        emit OwnershipRenounced(deployer);
    }

    // ════════════════════════════════════════════════════════════════
    //  ADMIN CONFIG  (locked after goLive)
    // ════════════════════════════════════════════════════════════════

    function setMainPair(address pair) external onlyRole(DEFAULT_ADMIN_ROLE) notLive {
        require(pair != address(0), "NovaPulse: zero"); mainPair = pair;
        _grantRole(FEE_EXEMPT, pair);
        emit MainPairSet(pair);
    }
    function setFeeReceiverWallet(address w) external onlyRole(DEFAULT_ADMIN_ROLE) notLive {
        require(w != address(0), "NovaPulse: zero");
        emit FeeReceiverWalletChanged(feeReceiverWallet, w);
        _revokeRole(FEE_EXEMPT, feeReceiverWallet);
        _grantRole(FEE_EXEMPT, w);
        feeReceiverWallet = w;
    }
    function setSwapThreshold(uint256 v) external onlyRole(DEFAULT_ADMIN_ROLE) notLive {
        require(v > 0, "NovaPulse: zero"); swapThreshold = v; emit SwapThresholdChanged(v);
    }
    function setSwapSlippage(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) notLive {
        require(bps <= 1000, "NovaPulse: >10%"); swapSlippageBps = bps; emit SwapSlippageChanged(bps);
    }
    function setMinLiquidity(uint256 v) external onlyRole(DEFAULT_ADMIN_ROLE) notLive {
        minLiquidityUSDT = v; emit MinLiquidityChanged(v);
    }
    function setRatio(uint8 t, uint256 v) external onlyRole(DEFAULT_ADMIN_ROLE) notLive {
        require(v <= PRECISION, "NovaPulse: >100%");
        if (t == 0) { sellFeeRatio = v; emit SellFeeRatioChanged(v); }
        else        { burnRatio    = v; emit BurnRatioChanged(v); }
    }
    function setRefRatios(uint256 l1, uint256 l2) external onlyRole(DEFAULT_ADMIN_ROLE) notLive {
        require(l1.add(l2) <= 10_000, "NovaPulse: >10%");
        refL1Ratio = l1; refL2Ratio = l2; emit RefRatiosChanged(l1, l2);
    }
    function setDemandSensitivity(uint256 v) external onlyRole(DEFAULT_ADMIN_ROLE) notLive {
        require(v > 0, "NovaPulse: zero"); demandSensitivity = v; emit DemandSensitivityChanged(v);
    }

    // ════════════════════════════════════════════════════════════════
    //  VIEW HELPERS
    // ════════════════════════════════════════════════════════════════

    function tokenStats() external view returns (
        uint256 totalSupply_,
        uint256 circulatingSupply_,
        uint256 treasuryNVPX,
        uint256 totalSold,
        uint256 currentPrice,
        uint256 floor,
        uint256 scarcity,
        uint256 demand,
        uint256 usdtLocked,
        uint256 txCount,
        bool    live,
        bool    swapOpen
    ) {
        totalSupply_       = _totalSupply;
        circulatingSupply_ = circulatingSupply();
        treasuryNVPX       = _balances[address(this)];
        totalSold          = totalSoldNVPX;
        floor              = floorPrice();
        scarcity           = scarcityMultiplier();
        demand             = demandMultiplier();
        currentPrice       = nvpxPrice();
        usdtLocked         = lockedUSDT;
        txCount            = transferCount;
        live               = isLive;
        swapOpen           = !swapClosed;
    }

    function getReferralProfile(address account) external view returns (
        address level1Referrer, address level2Referrer,
        uint256 totalEarned, uint256 totalReferred, uint256 refTxCount
    ) {
        level1Referrer = referrer[account];
        level2Referrer = referrer[referrer[account]];
        totalEarned    = referralStats[account].totalEarned;
        totalReferred  = referralStats[account].totalReferred;
        refTxCount     = referralStats[account].referralTxCount;
    }

    function autoSwapStats() external view returns (
        uint256 accumulated, uint256 threshold,
        uint256 slippageBps, uint256 minLiquidity,
        address feeWallet, bool liquidityOk
    ) {
        accumulated  = accumulatedFeeNVPX;
        threshold    = swapThreshold;
        slippageBps  = swapSlippageBps;
        minLiquidity = minLiquidityUSDT;
        feeWallet    = feeReceiverWallet;
        liquidityOk  = mainPair != address(0) && _hasSufficientLiquidity();
    }

    function launchInfo() external view returns (
        bool live, bool renounced, uint256 launchedAt,
        address pair, address feeWallet, string memory status
    ) {
        live       = isLive;
        renounced  = ownershipRenounced;
        launchedAt = launchTimestamp;
        pair       = mainPair;
        feeWallet  = feeReceiverWallet;
        status     = isLive
            ? "LIVE: open-source, renounced, treasury model, autonomous forever"
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
