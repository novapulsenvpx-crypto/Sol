// SPDX-License-Identifier: MIT
// NovaPulse (NVPX) v10 | BSC Mainnet | MIT License
// Treasury Model: ALL 21M NVPX held in contract at deploy.
// Tokens released ONLY when user pays 2 USDT each.
// USDT locked forever as price floor. Zero pre-distribution.
// goLive() = one click, renounces ownership permanently.
pragma solidity ^0.8.19;

// -------------------------------------------------------
// Custom Errors  (replaces all require strings -> saves ~3-4 KB)
// -------------------------------------------------------
error EZero();
error EOwner();
error EReentrant();
error ELive();
error ENotLive();
error ESub();
error EDiv();
error EMul();
error ESoldOut();
error EEmpty();
error EInsuf();
error ENetZero();
error EBal();
error EAllowance();
error EApproveFromZero();
error EApproveToZero();
error EFromZero();
error EToZero();
error EUsdtTx();
error ETooSmall();
error EAlreadyLive();
error ENoPair();
error EOverflow();
error ETooHigh();
error EMaxSlip();
error EZeroRef();
error ESelfRef();
error EAlreadySet();
error ECircular();
error ERefNoNvpx();

// -------------------------------------------------------
// IERC20
// -------------------------------------------------------
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// -------------------------------------------------------
// PancakeSwap Router
// -------------------------------------------------------
interface IPancakeRouter02 {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

// -------------------------------------------------------
// PancakeSwap Pair
// -------------------------------------------------------
interface IPancakePair {
    function getReserves() external view returns (uint112 r0, uint112 r1, uint32 ts);
    function token0() external view returns (address);
}

// -------------------------------------------------------
// ReentrancyGuard
// -------------------------------------------------------
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    modifier nonReentrant() {
        if (_status != 1) revert EReentrant();
        _status = 2;
        _;
        _status = 1;
    }
}

// -------------------------------------------------------
// Ownable
// -------------------------------------------------------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next);
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }
    function owner() public view returns (address) { return _owner; }
    modifier onlyOwner() {
        if (msg.sender != _owner) revert EOwner();
        _;
    }
    function _renounceOwnership() internal {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

// -------------------------------------------------------
// FeeExempt registry
// -------------------------------------------------------
abstract contract FeeExempt is Ownable {
    mapping(address => bool) private _exempt;
    function isExempt(address account) public view returns (bool) { return _exempt[account]; }
    function _setExempt(address account, bool status) internal { _exempt[account] = status; }
}

// =======================================================
//   NovaPulse (NVPX) v10 - Main Contract
// =======================================================
contract NovaPulse is IERC20, FeeExempt, ReentrancyGuard {

    // ---- Token metadata ----
    string  public constant name     = "NovaPulse";
    string  public constant symbol   = "NVPX";
    uint8   public constant decimals = 18;

    uint256 private constant WAD = 1e18;

    // ---- Supply ----
    uint256 public constant MAX_SUPPLY = 21_000_000 * WAD;
    uint256 public constant RATE_USDT  = 2 * WAD;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ---- Treasury ----
    address public immutable USDT_TOKEN;
    uint256 public lockedUSDT;
    uint256 public totalSoldNVPX;
    bool    public saleClosed;

    // ---- DEX ----
    address private constant SWAP_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public tradingPair;

    // ---- Fee config ----
    uint256 public constant BASIS = 100_000;
    uint256 public sellFeeRate   = 3_000;
    uint256 public autoBurnRate  = 1_000;

    // ---- Auto-swap ----
    address public feeRecipient  = 0x9504F94B3aE36B84e4a4dFA03BD1851737acf5Ac;
    uint256 public pendingFeeNVPX;
    uint256 public swapTrigger   = 20 * WAD;
    uint256 public maxSlippageBps = 200;
    uint256 public minPoolUSDT   = 1_000 * WAD;
    bool    private _inSwap;

    // ---- Price model ----
    uint256 public transferCount;
    uint256 public demandDivisor = 10_000;

    // ---- Referral ----
    address public constant DEFAULT_REFERRER = 0x131D15d8E58900c934E5C6BE2e9054062CCfB427;
    uint256 public level1Rate  = 3_000;
    uint256 public level2Rate  = 1_500;
    mapping(address => address) public myReferrer;

    struct RefData {
        uint256 totalEarned;
        uint256 directCount;
        uint256 rewardTxCount;
    }
    mapping(address => RefData) public refData;
    uint256 public globalRefPaid;
    uint256 public globalRefTxCount;

    // ---- Launch ----
    bool    public launched;
    uint256 public launchTime;

    // ---- Events ----
    event TokensPurchased(address indexed buyer, uint256 usdtIn, uint256 nvpxOut);
    event TokenBurned(address indexed burner, uint256 amount);
    event SellFeeCollected(address indexed seller, uint256 amount);
    event AutoSwapSuccess(uint256 nvpxIn, address indexed recipient);
    event AutoSwapFailed(bytes4 reason);
    event ReferrerLinked(address indexed user, address indexed ref);
    event ReferralReward(address indexed buyer, address indexed earner, uint8 level, uint256 amount);
    event ReferralMissed(address indexed earner, uint8 level, bytes4 reason);
    event TradingPairSet(address indexed pair);
    event ProjectLive(address indexed by, uint256 timestamp);

    // ---- Modifiers ----
    modifier notYetLive() {
        if (launched) revert ELive();
        _;
    }

    // =======================================================
    //  CONSTRUCTOR
    // =======================================================
    constructor(address usdtToken) {
        if (usdtToken == address(0)) revert EZero();
        USDT_TOKEN = usdtToken;
        _totalSupply = MAX_SUPPLY;
        _balances[address(this)] = MAX_SUPPLY;
        emit Transfer(address(0), address(this), MAX_SUPPLY);
        _setExempt(msg.sender,    true);
        _setExempt(feeRecipient,  true);
        _setExempt(SWAP_ROUTER,   true);
        _setExempt(address(this), true);
    }

    // =======================================================
    //  PRICE ORACLE
    // =======================================================
    function getCirculating() public view returns (uint256) {
        return _totalSupply - _balances[address(this)];
    }

    function getFloorPrice() public view returns (uint256) {
        uint256 circ = getCirculating();
        if (circ == 0) return RATE_USDT;
        return lockedUSDT * WAD / circ;
    }

    function getScarcityMult() public view returns (uint256) {
        uint256 circ = getCirculating();
        if (circ == 0) return WAD;
        return MAX_SUPPLY * WAD / circ;
    }

    function getDemandMult() public view returns (uint256) {
        if (demandDivisor == 0) return WAD;
        return WAD + transferCount * WAD / demandDivisor;
    }

    function getNVPXPrice() public view returns (uint256) {
        return getFloorPrice() * getScarcityMult() / WAD * getDemandMult() / WAD;
    }

    function getPriceComponents() external view returns (
        uint256 floorP, uint256 scarcityM, uint256 demandM, uint256 combinedPrice
    ) {
        floorP        = getFloorPrice();
        scarcityM     = getScarcityMult();
        demandM       = getDemandMult();
        combinedPrice = getNVPXPrice();
    }

    // =======================================================
    //  BUY NVPX WITH USDT
    // =======================================================
    function buyWithUSDT(uint256 usdtAmount) external nonReentrant {
        if (saleClosed)    revert ESoldOut();
        if (usdtAmount == 0) revert EZero();

        uint256 nvpxAmount = usdtAmount * WAD / RATE_USDT;
        if (nvpxAmount == 0) revert ETooSmall();

        uint256 treasuryHeld = _balances[address(this)];
        uint256 spendable    = treasuryHeld > pendingFeeNVPX
            ? treasuryHeld - pendingFeeNVPX : 0;
        if (spendable == 0) revert EEmpty();

        if (nvpxAmount > spendable) {
            nvpxAmount = spendable;
            usdtAmount = nvpxAmount * RATE_USDT / WAD;
        }

        if (!IERC20(USDT_TOKEN).transferFrom(msg.sender, address(this), usdtAmount))
            revert EUsdtTx();

        lockedUSDT    += usdtAmount;
        totalSoldNVPX += nvpxAmount;

        _deliverFromTreasury(msg.sender, nvpxAmount);
        emit TokensPurchased(msg.sender, usdtAmount, nvpxAmount);

        if (_balances[address(this)] <= pendingFeeNVPX) saleClosed = true;
    }

    function usdtNeeded(uint256 nvpxWanted) external pure returns (uint256) {
        return nvpxWanted * RATE_USDT / WAD;
    }

    // =======================================================
    //  INTERNAL: DELIVER FROM TREASURY
    // =======================================================
    function _deliverFromTreasury(address buyer, uint256 grossAmount) internal {
        if (_balances[address(this)] < grossAmount) revert EInsuf();
        unchecked { _balances[address(this)] -= grossAmount; }

        uint256 burnAmount = grossAmount * autoBurnRate / BASIS;
        if (burnAmount > 0) {
            _totalSupply -= burnAmount;
            emit Transfer(address(this), address(0), burnAmount);
            emit TokenBurned(address(this), burnAmount);
        }

        unchecked { transferCount++; }

        uint256 netAmount = grossAmount - burnAmount;
        if (netAmount == 0) revert ENetZero();

        _balances[buyer] += netAmount;
        emit Transfer(address(this), buyer, netAmount);

        _handleReferrals(buyer, netAmount);
    }

    // =======================================================
    //  ERC-20 STANDARD FUNCTIONS
    // =======================================================
    function totalSupply() public view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address owner_, address spender) public view override returns (uint256) { return _allowances[owner_][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        uint256 cur = _allowances[sender][msg.sender];
        if (cur < amount) revert EAllowance();
        unchecked { _approve(sender, msg.sender, cur - amount); }
        _transfer(sender, recipient, amount);
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 cur = _allowances[msg.sender][spender];
        if (cur < subtractedValue) revert ESub();
        unchecked { _approve(msg.sender, spender, cur - subtractedValue); }
        return true;
    }

    // =======================================================
    //  TRANSFER ENGINE
    // =======================================================
    function _transfer(address sender, address recipient, uint256 amount) internal {
        if (sender    == address(0)) revert EFromZero();
        if (recipient == address(0)) revert EToZero();
        if (_balances[sender] < amount) revert EBal();
        unchecked { _balances[sender] -= amount; }

        if (_inSwap) {
            _balances[recipient] += amount;
            emit Transfer(sender, recipient, amount);
            return;
        }

        bool feesEnabled = !(isExempt(sender) && isExempt(recipient));
        uint256 burnAmt;
        uint256 feeAmt;

        if (feesEnabled) {
            unchecked { transferCount++; }

            burnAmt = amount * autoBurnRate / BASIS;
            if (burnAmt > 0) {
                _totalSupply -= burnAmt;
                emit Transfer(sender, address(0), burnAmt);
                emit TokenBurned(sender, burnAmt);
            }

            bool isSell = (recipient == tradingPair && tradingPair != address(0));
            if (isSell) {
                feeAmt = amount * sellFeeRate / BASIS;
                if (feeAmt > 0) {
                    _balances[address(this)] += feeAmt;
                    pendingFeeNVPX += feeAmt;
                    emit Transfer(sender, address(this), feeAmt);
                    emit SellFeeCollected(sender, feeAmt);
                }
            }
        }

        uint256 netAmt = amount - burnAmt - feeAmt;
        if (netAmt == 0) revert ENetZero();
        _balances[recipient] += netAmt;
        emit Transfer(sender, recipient, netAmt);

        bool isBuy = (sender == tradingPair && tradingPair != address(0));
        if (feesEnabled && isBuy && !isExempt(recipient)) {
            _handleReferrals(recipient, amount);
        }

        if (feeAmt > 0) _triggerAutoSwap();
    }

    // =======================================================
    //  AUTO-SWAP ENGINE
    // =======================================================
    function _triggerAutoSwap() internal {
        if (pendingFeeNVPX < swapTrigger) return;
        if (_inSwap) return;
        if (tradingPair == address(0)) return;
        if (!_poolHasLiquidity()) {
            emit AutoSwapFailed(bytes4(keccak256("low_liquidity")));
            return;
        }
        uint256 nvpxToSwap = pendingFeeNVPX;
        pendingFeeNVPX = 0;
        _inSwap = true;
        _executeSwap(nvpxToSwap);
        _inSwap = false;
    }

    function _poolHasLiquidity() internal view returns (bool) {
        try IPancakePair(tradingPair).getReserves() returns (uint112 r0, uint112 r1, uint32) {
            address t0 = IPancakePair(tradingPair).token0();
            return ((t0 == USDT_TOKEN) ? uint256(r0) : uint256(r1)) >= minPoolUSDT;
        } catch { return false; }
    }

    function _executeSwap(uint256 nvpxAmount) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = USDT_TOKEN;

        uint256 expectedOut;
        try IPancakeRouter02(SWAP_ROUTER).getAmountsOut(nvpxAmount, path) returns (uint256[] memory amounts) {
            expectedOut = amounts[1];
        } catch {
            pendingFeeNVPX += nvpxAmount;
            emit AutoSwapFailed(bytes4(keccak256("quote_failed")));
            return;
        }

        if (expectedOut == 0) {
            pendingFeeNVPX += nvpxAmount;
            emit AutoSwapFailed(bytes4(keccak256("zero_output")));
            return;
        }

        uint256 minOutput = expectedOut * (10_000 - maxSlippageBps) / 10_000;
        _allowances[address(this)][SWAP_ROUTER] = nvpxAmount;
        emit Approval(address(this), SWAP_ROUTER, nvpxAmount);

        try IPancakeRouter02(SWAP_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            nvpxAmount, minOutput, path, feeRecipient, block.timestamp + 300
        ) {
            emit AutoSwapSuccess(nvpxAmount, feeRecipient);
        } catch {
            pendingFeeNVPX += nvpxAmount;
            emit AutoSwapFailed(bytes4(keccak256("swap_reverted")));
        }
    }

    // =======================================================
    //  REFERRAL SYSTEM
    // =======================================================
    function registerReferrer(address referrerAddress) external {
        if (referrerAddress == address(0))             revert EZeroRef();
        if (referrerAddress == msg.sender)             revert ESelfRef();
        if (myReferrer[msg.sender] != address(0))      revert EAlreadySet();
        if (myReferrer[referrerAddress] == msg.sender) revert ECircular();
        if (_balances[referrerAddress] == 0)           revert ERefNoNvpx();
        myReferrer[msg.sender] = referrerAddress;
        refData[referrerAddress].directCount++;
        emit ReferrerLinked(msg.sender, referrerAddress);
    }

    function _handleReferrals(address buyer, uint256 grossAmount) internal {
        address l1Ref = myReferrer[buyer];
        if (l1Ref == address(0)) l1Ref = DEFAULT_REFERRER;
        if (l1Ref == buyer) return;

        unchecked { globalRefTxCount++; }

        uint256 reward1 = grossAmount * level1Rate / BASIS;
        if (reward1 > 0) {
            if (_balances[l1Ref] == 0) {
                emit ReferralMissed(l1Ref, 1, bytes4(keccak256("no_nvpx")));
            } else if (_balances[buyer] < reward1) {
                emit ReferralMissed(l1Ref, 1, bytes4(keccak256("buyer_low")));
            } else {
                unchecked {
                    _balances[buyer]  -= reward1;
                    _balances[l1Ref]  += reward1;
                    refData[l1Ref].totalEarned  += reward1;
                    refData[l1Ref].rewardTxCount++;
                    globalRefPaid += reward1;
                }
                emit Transfer(buyer, l1Ref, reward1);
                emit ReferralReward(buyer, l1Ref, 1, reward1);
            }
        }

        address l2Ref = myReferrer[l1Ref];
        if (l2Ref == address(0)) return;

        uint256 reward2 = grossAmount * level2Rate / BASIS;
        if (reward2 > 0) {
            if (_balances[l2Ref] == 0) {
                emit ReferralMissed(l2Ref, 2, bytes4(keccak256("no_nvpx")));
            } else if (_balances[buyer] < reward2) {
                emit ReferralMissed(l2Ref, 2, bytes4(keccak256("buyer_low")));
            } else {
                unchecked {
                    _balances[buyer]  -= reward2;
                    _balances[l2Ref]  += reward2;
                    refData[l2Ref].totalEarned  += reward2;
                    refData[l2Ref].rewardTxCount++;
                    globalRefPaid += reward2;
                }
                emit Transfer(buyer, l2Ref, reward2);
                emit ReferralReward(buyer, l2Ref, 2, reward2);
            }
        }
    }

    // =======================================================
    //  MANUAL BURN
    // =======================================================
    function burn(uint256 amount) external {
        if (_balances[msg.sender] < amount) revert EBal();
        unchecked {
            _balances[msg.sender] -= amount;
            _totalSupply          -= amount;
        }
        emit Transfer(msg.sender, address(0), amount);
        emit TokenBurned(msg.sender, amount);
    }

    // =======================================================
    //  SIMULATE PURCHASE (read-only preview)
    // =======================================================
    function simulatePurchase(
        address buyer,
        uint256 usdtAmount
    ) external view returns (
        uint256 grossNVPX,
        uint256 burnDeducted,
        uint256 level1Reward,
        uint256 level2Reward,
        uint256 buyerReceives,
        address level1Ref,
        address level2Ref
    ) {
        grossNVPX    = usdtAmount * WAD / RATE_USDT;
        burnDeducted = grossNVPX * autoBurnRate / BASIS;
        uint256 netNVPX = grossNVPX - burnDeducted;

        level1Ref = myReferrer[buyer];
        if (level1Ref == address(0)) level1Ref = DEFAULT_REFERRER;
        level2Ref = myReferrer[level1Ref];

        level1Reward = (_balances[level1Ref] > 0) ? netNVPX * level1Rate / BASIS : 0;
        level2Reward = (level2Ref != address(0) && _balances[level2Ref] > 0)
            ? netNVPX * level2Rate / BASIS : 0;

        uint256 totalDeductions = level1Reward + level2Reward;
        buyerReceives = netNVPX > totalDeductions ? netNVPX - totalDeductions : 0;
    }

    // =======================================================
    //  GO LIVE
    // =======================================================
    function goLive() external onlyOwner {
        if (launched)              revert EAlreadyLive();
        if (tradingPair == address(0)) revert ENoPair();
        launched   = true;
        launchTime = block.timestamp;
        _renounceOwnership();
        emit ProjectLive(msg.sender, launchTime);
    }

    // =======================================================
    //  ADMIN CONFIG  (all blocked after goLive)
    // =======================================================
    function setTradingPair(address pairAddress) external onlyOwner notYetLive {
        if (pairAddress == address(0)) revert EZero();
        tradingPair = pairAddress;
        _setExempt(pairAddress, true);
        emit TradingPairSet(pairAddress);
    }

    function setFeeRecipient(address newRecipient) external onlyOwner notYetLive {
        if (newRecipient == address(0)) revert EZero();
        _setExempt(feeRecipient, false);
        _setExempt(newRecipient, true);
        feeRecipient = newRecipient;
    }

    function setSwapTrigger(uint256 newMin) external onlyOwner notYetLive {
        if (newMin == 0) revert EZero();
        swapTrigger = newMin;
    }

    function setMaxSlippage(uint256 bps) external onlyOwner notYetLive {
        if (bps > 1000) revert EMaxSlip();
        maxSlippageBps = bps;
    }

    function setMinPoolUSDT(uint256 newMin) external onlyOwner notYetLive { minPoolUSDT = newMin; }

    function setSellFeeRate(uint256 newRate) external onlyOwner notYetLive {
        if (newRate > BASIS) revert EOverflow();
        sellFeeRate = newRate;
    }

    function setAutoBurnRate(uint256 newRate) external onlyOwner notYetLive {
        if (newRate > BASIS) revert EOverflow();
        autoBurnRate = newRate;
    }

    function setRefRates(uint256 l1, uint256 l2) external onlyOwner notYetLive {
        if (l1 + l2 > 10_000) revert ETooHigh();
        level1Rate = l1;
        level2Rate = l2;
    }

    function setDemandDivisor(uint256 newDivisor) external onlyOwner notYetLive {
        if (newDivisor == 0) revert EZero();
        demandDivisor = newDivisor;
    }

    function setExemptAddress(address account, bool status) external onlyOwner notYetLive {
        _setExempt(account, status);
    }

    // =======================================================
    //  VIEW HELPERS
    // =======================================================
    function getTokenStats() external view returns (
        uint256 totalSupply_,
        uint256 circulatingSupply,
        uint256 treasuryNVPX,
        uint256 soldSoFar,
        uint256 currentPrice,
        uint256 floorPriceNow,
        uint256 scarcityMultNow,
        uint256 demandMultNow,
        uint256 usdtLockedNow,
        uint256 txCountNow,
        bool    isLive,
        bool    saleOpen
    ) {
        totalSupply_      = _totalSupply;
        circulatingSupply = getCirculating();
        treasuryNVPX      = _balances[address(this)];
        soldSoFar         = totalSoldNVPX;
        floorPriceNow     = getFloorPrice();
        scarcityMultNow   = getScarcityMult();
        demandMultNow     = getDemandMult();
        currentPrice      = getNVPXPrice();
        usdtLockedNow     = lockedUSDT;
        txCountNow        = transferCount;
        isLive            = launched;
        saleOpen          = !saleClosed;
    }

    function getMyReferralData(address account) external view returns (
        address level1Referrer,
        address level2Referrer,
        uint256 totalNVPXEarned,
        uint256 directReferrals,
        uint256 rewardTransactions
    ) {
        level1Referrer     = myReferrer[account];
        level2Referrer     = myReferrer[level1Referrer];
        RefData memory rd  = refData[account];
        totalNVPXEarned    = rd.totalEarned;
        directReferrals    = rd.directCount;
        rewardTransactions = rd.rewardTxCount;
    }

    function getAutoSwapStatus() external view returns (
        uint256 pendingNVPX,
        uint256 triggerAmount,
        address recipientWallet,
        bool    poolOk
    ) {
        pendingNVPX     = pendingFeeNVPX;
        triggerAmount   = swapTrigger;
        recipientWallet = feeRecipient;
        poolOk          = tradingPair != address(0) && _poolHasLiquidity();
    }

    function getLaunchInfo() external view returns (
        bool isLive, uint256 timestamp, address pairAddress, address feeAddress
    ) {
        isLive      = launched;
        timestamp   = launchTime;
        pairAddress = tradingPair;
        feeAddress  = feeRecipient;
    }

    function getTreasuryInfo() external view returns (
        uint256 nvpxInTreasury,
        uint256 usdtLocked,
        uint256 nvpxSold,
        uint256 nvpxAvailable,
        bool    saleOpen
    ) {
        nvpxInTreasury = _balances[address(this)];
        usdtLocked     = lockedUSDT;
        nvpxSold       = totalSoldNVPX;
        uint256 held   = _balances[address(this)];
        nvpxAvailable  = held > pendingFeeNVPX ? held - pendingFeeNVPX : 0;
        saleOpen       = !saleClosed;
    }

    // ---- Internal ----
    function _approve(address owner_, address spender, uint256 amount) internal {
        if (owner_  == address(0)) revert EApproveFromZero();
        if (spender == address(0)) revert EApproveToZero();
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }
}
