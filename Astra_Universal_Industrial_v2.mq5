//+------------------------------------------------------------------+
//|                         Astra_Universal_Industrial_v2.mq5        |
//|            Sains Manajemen - Multi-Asset Industrial EA           |
//|               FMIPA Universitas Gadjah Mada (UGM) 2026           |
//+------------------------------------------------------------------+
//
//  CARA PEMASANGAN DI METATRADER 5:
//  ─────────────────────────────────────────────────────────────────
//  1. MT5 → [File] → [Open Data Folder]
//  2. Copy 3 file .mqh → [DataFolder]\MQL5\Include\
//  3. Copy file .mq5  → [DataFolder]\MQL5\Experts\
//  4. MetaEditor (F4) → buka .mq5 → F7 (Compile) → 0 errors
//  5. MT5 → Navigator → Experts → Refresh → drag ke chart
//  ─────────────────────────────────────────────────────────────────
//
//  TIMEFRAME PER INSTRUMEN (v2.1):
//    EURUSD / USDJPY        : Macro H4  + Signal H1
//    XAUUSD / XAGUSD        : Macro D1  + Signal H4  ← diperbaiki
//    US30   / JP225         : Macro H4  + Signal H1
//    BTCUSD / ETHUSD        : Macro D1  + Signal H4  ← diperbaiki
//    USOIL  / UKOIL         : Macro H4  + Signal H4  ← diperbaiki
//
//  v2.1 CHANGE: IsNewBarMacro() / IsNewBarSignal() menggantikan
//  IsNewBar(PERIOD_H4/H1) yang hardcoded — kini dinamis sesuai
//  profile instrumen.
//+------------------------------------------------------------------+
#property copyright "Sains Manajemen Project 2 - UGM 2026"
#property version   "2.10"
#property description "Industrial Multi-Asset EA - Strict 1:1 Cash Model"

#include <AstraInstrumentProfile_v2.mqh>
#include <AstraRiskManager_v2.mqh>
#include <AstraSignalEngine_v2.mqh>

//+------------------------------------------------------------------+
//  INPUT PARAMETERS
//+------------------------------------------------------------------+
input string  _Sec1              = "═══ INSTRUMENT SETUP ═══";
input string  InpSymbolOverride  = "";       // Symbol override (blank = chart symbol)

input string  _Sec2              = "═══ RISK MANAGEMENT 1:1 ═══";
input double  InpRiskPct         = 0.0;      // Risk % per trade (0 = use preset, max 1.5)
input double  InpSLMultOverride  = 0.0;      // SL ATR Multiplier override (0 = preset)
input double  InpTPMultOverride  = 0.0;      // TP ATR Multiplier override (0 = preset)
input double  InpMaxDDOverride   = 0.0;      // Max Drawdown % override (0 = preset)

input string  _Sec3              = "═══ EXECUTION CONTROL ═══";
input int     InpCooldownBars    = 4;        // Cooldown bars after each trade close
input bool    InpAllowBuy        = true;     // Allow BUY positions
input bool    InpAllowSell       = true;     // Allow SELL positions
input int     InpMagicOverride   = 0;        // Magic Number override (0 = preset)

input string  _Sec4              = "═══ SIGNAL FILTERS ═══";
input bool    InpUseVolFilter    = true;     // Volatility filter: ATR > SMA(ATR,20)
input int     InpMaxSpreadOvrd   = 0;        // Max spread override in points (0 = preset)

//+------------------------------------------------------------------+
//  GLOBAL STATE
//+------------------------------------------------------------------+
SAstraProfile      g_profile;
CAstraRiskManager  g_risk;
CAstraSignalEngine g_signal;

int  g_macroTrend  = 0;     // Cached macro trend: 1=bull, -1=bear, 0=neutral
int  g_cooldown    = 0;     // Cooldown bars remaining
bool g_wasInTrade  = false;  // Previous bar position state

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    string sym = (InpSymbolOverride != "") ? InpSymbolOverride : Symbol();

    //--- Load preset
    bool presetFound = GetAstraProfile(sym, g_profile);
    if(!presetFound)
        Print("[Astra] WARNING: No preset for '", sym, "'. Using defaults.");

    //--- Apply overrides
    if(InpRiskPct        > 0.0) g_profile.riskPercent   = MathMin(1.5, InpRiskPct);
    if(InpSLMultOverride > 0.0) g_profile.slMult         = InpSLMultOverride;
    if(InpTPMultOverride > 0.0) g_profile.tpMult         = InpTPMultOverride;
    if(InpMaxDDOverride  > 0.0) g_profile.maxDrawdownPct = InpMaxDDOverride;
    if(InpMagicOverride  > 0)   g_profile.magicNumber    = InpMagicOverride;
    if(InpMaxSpreadOvrd  > 0)   g_profile.maxSpreadPts   = InpMaxSpreadOvrd;

    //--- Validate R:R
    double rr = g_profile.tpMult / g_profile.slMult;
    if(rr < 1.8)
        Print("[Astra] WARNING: R:R=1:", DoubleToString(rr, 2),
              " below 1:1.8 — profitability at risk. Increase TP multiplier.");

    //--- Initialize modules
    if(!g_risk.Init(g_profile))
    {
        Print("[Astra] ERROR: RiskManager init failed");
        return INIT_FAILED;
    }
    if(!g_signal.Init(g_profile))
    {
        Print("[Astra] ERROR: SignalEngine init failed");
        return INIT_FAILED;
    }

    //--- Warm-up macro trend
    g_macroTrend = g_signal.GetMacroTrend();
    g_cooldown   = 0;
    g_wasInTrade = g_risk.HasOpenPosition();

    //--- Startup summary
    string tStr = (g_macroTrend ==  1) ? "BULL ↑" :
                  (g_macroTrend == -1) ? "BEAR ↓" : "NEUTRAL ─";

    Print("╔══════════════════════════════════════════════════════╗");
    Print("║  Astra Universal Industrial EA  v2.10                ║");
    Print("║  Sains Manajemen — FMIPA UGM 2026                    ║");
    Print("╠══════════════════════════════════════════════════════╣");
    Print("║  Symbol     : ", g_profile.displayName, " (", sym, ")");
    Print("║  Preset     : ", presetFound ? "Auto-loaded ✓" : "Default ⚠");
    Print("║  Magic #    : ", g_profile.magicNumber);
    Print("╠══════════════════════════════════════════════════════╣");
    Print("║  Macro TF   : ", TFName(g_profile.tfMacro),
          " | EMA(", g_profile.ema200Period, ") + ATR Dir (", g_profile.atrDirMult, "x)");
    Print("║  Signal TF  : ", TFName(g_profile.tfSignal),
          " | KC(EMA", g_profile.keltnerPeriod, "±", g_profile.keltnerMult,
          "×ATR) + RSI(", g_profile.rsiPeriod, ")");
    Print("║  Vol Filter : ATR > SMA(ATR,20) [",
          InpUseVolFilter ? "ENABLED" : "DISABLED", "]");
    Print("╠══════════════════════════════════════════════════════╣");
    Print("║  Risk Model : 1:1 Cash Equivalent (No Leverage)");
    Print("║  Risk/Trade : ", DoubleToString(g_profile.riskPercent, 2), "% of Balance");
    Print("║  SL / TP    : ", g_profile.slMult, "x / ", g_profile.tpMult,
          "x ATR  [R:R 1:", DoubleToString(rr, 2), "]");
    Print("║  Trail      : ", g_profile.trailMult, "x ATR | Activates @ ",
          g_profile.trailActiveMult, "x ATR profit");
    Print("║  MaxDD CB   : ", g_profile.maxDrawdownPct, "%");
    Print("╠══════════════════════════════════════════════════════╣");
    Print("║  Cooldown   : ", InpCooldownBars, " bars | MaxSpread: ",
          g_profile.maxSpreadPts, " pts");
    Print("║  Allow      : Buy=", InpAllowBuy ? "YES" : "NO",
          " | Sell=", InpAllowSell ? "YES" : "NO");
    Print("║  Macro Trend: ", tStr);
    Print("╚══════════════════════════════════════════════════════╝");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    g_signal.Deinit();
    string rStr;
    switch(reason)
    {
        case REASON_REMOVE:     rStr = "Removed from chart";   break;
        case REASON_RECOMPILE:  rStr = "Recompiled";           break;
        case REASON_CHARTCHANGE:rStr = "Chart changed";        break;
        case REASON_CLOSE:      rStr = "Terminal closed";      break;
        default:                rStr = "Code " + IntegerToString(reason); break;
    }
    Print("[Astra] EA stopped — ", rStr);
}

//+------------------------------------------------------------------+
//| OnTick — Main execution loop (4-step pipeline)                  |
//+------------------------------------------------------------------+
void OnTick()
{
    //=================================================================
    //  STEP 1 — Circuit Breaker (every tick)
    //=================================================================
    if(g_risk.CheckCircuitBreaker())
    {
        static int cbLog = 0;
        if(++cbLog % 200 == 0)
            Print("[Astra] *** CIRCUIT BREAKER ACTIVE — DD limit reached. Trading halted. ***");
        return;
    }

    //=================================================================
    //  STEP 2 — Dynamic Trailing Stop (every tick)
    //  Uses ATR from SIGNAL timeframe (H1 for Forex, H4 for Metal/Crypto)
    //=================================================================
    double atr_signal = g_signal.GetCurrentATR_Signal();
    if(atr_signal > 0.0)
        g_risk.ManageTrailingStop(atr_signal);

    //=================================================================
    //  STEP 3 — Macro Trend Update (on new MACRO bar only)
    //  H4 bar for Forex/Index/Energy, D1 bar for Metal/Crypto
    //=================================================================
    if(g_signal.IsNewBarMacro())
    {
        int prevTrend = g_macroTrend;
        g_macroTrend  = g_signal.GetMacroTrend();

        if(g_macroTrend != prevTrend)
        {
            string tStr = (g_macroTrend ==  1) ? "BULL ↑" :
                          (g_macroTrend == -1) ? "BEAR ↓" : "NEUTRAL ─";
            Print("[Astra] [", TFName(g_profile.tfMacro), "] Macro Trend → ", tStr,
                  " | EMA200=", DoubleToString(g_signal.GetEMA200_Macro(),
                  (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)),
                  " | ATR_Macro=", DoubleToString(g_signal.GetCurrentATR_Macro(), 5));
        }
    }

    //=================================================================
    //  STEP 4 — Signal Processing (on new SIGNAL bar only — Anti-HFT)
    //  H1 bar for Forex, H4 bar for Metal/Crypto/Energy
    //=================================================================
    if(!g_signal.IsNewBarSignal()) return;

    //--- [4a] Cooldown management
    bool inTrade = g_risk.HasOpenPosition();
    if(g_wasInTrade && !inTrade)
    {
        g_cooldown = InpCooldownBars;
        Print("[Astra] Trade closed → Cooldown: ", InpCooldownBars,
              " ", TFName(g_profile.tfSignal), " bars");
    }
    g_wasInTrade = inTrade;
    if(!inTrade && g_cooldown > 0) g_cooldown--;

    //--- [4b] Skip if already in position or cooling down
    if(inTrade || g_cooldown > 0) return;

    //--- [4c] Trade authorization check
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
       !MQLInfoInteger(MQL_TRADE_ALLOWED)) return;

    //--- [4d] Spread filter
    if(!g_risk.IsSpreadAcceptable()) return;

    //--- [4e] ATR validity
    if(atr_signal <= 0.0) { Print("[Astra] ATR_Signal=0, skip bar"); return; }

    //--- [4f] Volatility filter: ATR > SMA(ATR, 20)
    if(InpUseVolFilter && !g_signal.IsVolatilityOK()) return;

    //--- [4g] Macro trend must be directional
    if(g_macroTrend == 0) return;

    //--- [4h] Get entry signal from signal TF
    int signal = g_signal.GetSignal(g_macroTrend);
    if(signal == 0) return;

    //=================================================================
    //  STEP 5 — Execute (1 position, bar-close, anti-martingale)
    //=================================================================
    if(signal ==  1 && InpAllowBuy)
        g_risk.ExecuteBuy(atr_signal, "Astra|BUY|KC+RSI|" + TFName(g_profile.tfSignal));
    else if(signal == -1 && InpAllowSell)
        g_risk.ExecuteSell(atr_signal, "Astra|SELL|KC+RSI|" + TFName(g_profile.tfSignal));
}

//+------------------------------------------------------------------+
//| OnTrade — Audit trail logging                                   |
//+------------------------------------------------------------------+
void OnTrade()
{
    static int lastTotal = -1;
    int curTotal = PositionsTotal();
    if(curTotal != lastTotal)
    {
        lastTotal = curTotal;
        Print("[Astra] OnTrade | Positions=", curTotal,
              " | Equity=", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
              " | Balance=", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
              " | DD=", DoubleToString(g_risk.GetCurrentDrawdownPct(), 2), "%");
    }
}

//+------------------------------------------------------------------+
//| OnTester — Custom fitness for MT5 Genetic Optimization           |
//| Criterion: Balance × (1 - DD%) × ProfitFactor × Sharpe          |
//| Rewards: high profit, low drawdown, consistent gains             |
//+------------------------------------------------------------------+
double OnTester()
{
    double balance  = TesterStatistics(STAT_PROFIT) +
                      TesterStatistics(STAT_INITIAL_DEPOSIT);
    double maxDD    = TesterStatistics(STAT_EQUITY_DD);
    double profFact = TesterStatistics(STAT_PROFIT_FACTOR);
    double sharpe   = TesterStatistics(STAT_SHARPE_RATIO);
    double trades   = TesterStatistics(STAT_TRADES);

    if(trades < 12) return -1.0;  // Too few trades = not statistically valid

    double ddPct = (balance > 0) ? (maxDD / balance) * 100.0 : 100.0;
    if(ddPct > 28.0) return -1.0;  // Reject strategies with excessive DD

    double pfScore = MathMax(0.0, profFact - 1.0);
    return balance * pfScore * MathMax(0.01, sharpe);
}
//+------------------------------------------------------------------+
