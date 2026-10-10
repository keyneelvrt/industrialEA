//+------------------------------------------------------------------+
//|                             AstraInstrumentProfile_v2.mqh         |
//|            Sains Manajemen - Multi-Asset Industrial EA           |
//|               FMIPA Universitas Gadjah Mada (UGM) 2026           |
//+------------------------------------------------------------------+
//  v2.1 UPDATE — Volatile asset TF upgrade:
//    Metal (XAU/XAG) : Macro D1 + Signal H4  (was H4+H1)
//    Crypto (BTC/ETH) : Macro D1 + Signal H4  (was H4+H1)
//    Energy (USOIL/UKOIL): Macro H4 + Signal H4 (was H4+H1)
//  Rationale: H1 Keltner Channel too noisy for high-volatility assets.
//             D1/H4 macro captures clean macro trend; H4 KC breakout
//             filters out intraday noise while keeping valid signals.
//+------------------------------------------------------------------+
#property copyright "Sains Manajemen Project 2 - UGM 2026"

#ifndef ASTRA_INSTRUMENT_PROFILE_V2_MQH
#define ASTRA_INSTRUMENT_PROFILE_V2_MQH

//+------------------------------------------------------------------+
//| Instrument Profile — all parameters in one structure             |
//+------------------------------------------------------------------+
struct SAstraProfile
{
    string  symbol;
    string  displayName;

    //--- Timeframes (instrument-specific — NOT always H4+H1)
    ENUM_TIMEFRAMES tfMacro;    // Macro trend TF  : H4 (Forex) / D1 (Metal/Crypto)
    ENUM_TIMEFRAMES tfSignal;   // Signal entry TF : H1 (Forex) / H4 (Metal/Crypto/Energy)

    //--- H4/D1 Macro Filter: EMA200 + ATR Directional
    int     ema200Period;       // EMA macro period (200)
    double  atrDirMult;         // ATR multiplier for directional buffer zone

    //--- Signal TF: Keltner Channel Breakout
    int     keltnerPeriod;      // KC EMA + ATR period (20)
    double  keltnerMult;        // KC band width multiplier — WIDER for volatile assets

    //--- Signal TF: RSI Rebound Filter
    int     rsiPeriod;          // RSI period (14)
    double  rsiBuyMax;          // Max RSI for BUY (not overbought)
    double  rsiSellMin;         // Min RSI for SELL (not oversold)

    //--- ATR for risk and volatility filter
    int     atrPeriod;          // ATR period (14)

    //--- Risk & SL/TP (1:1 Cash Model, R:R >= 1:2.5)
    double  slMult;             // ATR SL multiplier
    double  tpMult;             // ATR TP multiplier
    double  trailMult;          // ATR trailing stop multiplier
    double  trailActiveMult;    // ATR profit before trailing activates
    double  riskPercent;        // Risk % of balance per trade

    //--- Filters
    int     maxSpreadPts;       // Max spread (points)
    double  maxDrawdownPct;     // Circuit breaker threshold (%)
    int     magicNumber;        // Magic number (unique per instrument)
};

//+------------------------------------------------------------------+
//| Helper: enum name for logging                                    |
//+------------------------------------------------------------------+
string TFName(ENUM_TIMEFRAMES tf)
{
    switch(tf)
    {
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN";
        default:         return "TF" + IntegerToString((int)tf);
    }
}

//+------------------------------------------------------------------+
//| Load preset by symbol — returns false if unknown symbol          |
//+------------------------------------------------------------------+
bool GetAstraProfile(const string symbol, SAstraProfile &p)
{
    //--- Universal defaults
    p.symbol          = symbol;
    p.tfMacro         = PERIOD_H4;
    p.tfSignal        = PERIOD_H1;
    p.ema200Period    = 200;
    p.keltnerPeriod   = 20;
    p.rsiPeriod       = 14;
    p.atrPeriod       = 14;
    p.slMult          = 1.8;
    p.tpMult          = 4.5;
    p.trailMult       = 1.5;
    p.trailActiveMult = 1.0;
    p.riskPercent     = 1.0;
    p.maxDrawdownPct  = 25.0;

    string sym = symbol;
    StringToUpper(sym);

    //=================================================================
    //  FOREX — H4 Macro + H1 Signal (low volatility, tight spread)
    //=================================================================
    if(StringFind(sym, "EURUSD") >= 0)
    {
        p.displayName  = "EUR/USD";
        p.tfMacro      = PERIOD_H4;   // H4 macro is sufficient for Forex
        p.tfSignal     = PERIOD_H1;   // H1 signal for precise entries
        p.atrDirMult   = 2.0;
        p.keltnerMult  = 2.0;
        p.rsiBuyMax    = 72.0;
        p.rsiSellMin   = 28.0;
        p.slMult       = 1.8;
        p.tpMult       = 4.5;         // R:R = 1:2.5
        p.trailMult    = 1.5;
        p.trailActiveMult = 1.0;
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 20;
        p.magicNumber  = 30001;
    }
    else if(StringFind(sym, "USDJPY") >= 0)
    {
        p.displayName  = "USD/JPY";
        p.tfMacro      = PERIOD_H4;
        p.tfSignal     = PERIOD_H1;
        p.atrDirMult   = 2.0;
        p.keltnerMult  = 2.0;
        p.rsiBuyMax    = 72.0;
        p.rsiSellMin   = 28.0;
        p.slMult       = 1.8;
        p.tpMult       = 4.5;
        p.trailMult    = 1.5;
        p.trailActiveMult = 1.0;
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 25;
        p.magicNumber  = 30002;
    }

    //=================================================================
    //  METALS — D1 Macro + H4 Signal (UPGRADED from H4+H1)
    //  Reason: Gold/Silver H1 KC generates 60-70% false breakouts.
    //          D1 EMA200 gives cleaner long-term trend. H4 KC captures
    //          meaningful multi-hour moves with lower noise.
    //=================================================================
    else if(StringFind(sym, "XAUUSD") >= 0)
    {
        p.displayName  = "XAU/USD (Gold)";
        p.tfMacro      = PERIOD_D1;   // ← UPGRADED: D1 macro for Gold
        p.tfSignal     = PERIOD_H4;   // ← UPGRADED: H4 signal (not H1)
        p.atrDirMult   = 2.5;
        p.keltnerMult  = 2.8;         // Wider KC for H4 Gold — catch only strong breaks
        p.rsiBuyMax    = 73.0;        // RSI 48-73 for buy (momentum confirmed)
        p.rsiSellMin   = 27.0;
        p.slMult       = 2.5;         // Wider SL — H4 Gold has 20-40pt noise
        p.tpMult       = 6.25;        // R:R = 1:2.5  (6.25 / 2.5)
        p.trailMult    = 2.0;
        p.trailActiveMult = 1.5;
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 120;
        p.maxDrawdownPct = 25.0;
        p.magicNumber  = 30003;
    }
    else if(StringFind(sym, "XAGUSD") >= 0)
    {
        p.displayName  = "XAG/USD (Silver)";
        p.tfMacro      = PERIOD_D1;   // ← UPGRADED: D1 macro
        p.tfSignal     = PERIOD_H4;   // ← UPGRADED: H4 signal
        p.atrDirMult   = 2.5;
        p.keltnerMult  = 2.8;
        p.rsiBuyMax    = 73.0;
        p.rsiSellMin   = 27.0;
        p.slMult       = 2.5;
        p.tpMult       = 6.25;        // R:R = 1:2.5
        p.trailMult    = 2.0;
        p.trailActiveMult = 1.5;
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 180;
        p.magicNumber  = 30004;
    }

    //=================================================================
    //  INDICES — H4 Macro + H1 Signal (moderate volatility)
    //=================================================================
    else if(StringFind(sym, "US30") >= 0 || StringFind(sym, "DJ30") >= 0)
    {
        p.displayName  = "US30 (Dow Jones)";
        p.tfMacro      = PERIOD_H4;
        p.tfSignal     = PERIOD_H1;
        p.atrDirMult   = 2.8;
        p.keltnerMult  = 2.4;
        p.rsiBuyMax    = 75.0;
        p.rsiSellMin   = 25.0;
        p.slMult       = 2.2;
        p.tpMult       = 5.5;
        p.trailMult    = 2.0;
        p.trailActiveMult = 1.5;
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 500;
        p.magicNumber  = 30005;
    }
    else if(StringFind(sym, "JP225") >= 0 || StringFind(sym, "JPN225") >= 0)
    {
        p.displayName  = "JP225 (Nikkei 225)";
        p.tfMacro      = PERIOD_H4;
        p.tfSignal     = PERIOD_H1;
        p.atrDirMult   = 2.8;
        p.keltnerMult  = 2.4;
        p.rsiBuyMax    = 75.0;
        p.rsiSellMin   = 25.0;
        p.slMult       = 2.2;
        p.tpMult       = 5.5;
        p.trailMult    = 2.0;
        p.trailActiveMult = 1.5;
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 600;
        p.magicNumber  = 30006;
    }

    //=================================================================
    //  CRYPTO — D1 Macro + H4 Signal (UPGRADED from H4+H1)
    //  Reason: BTC/ETH H1 is extremely noisy — 5-10% daily swings mean
    //          H1 KC breaks are mostly noise. D1 EMA200 captures the
    //          multi-week bull/bear cycle. H4 KC catches valid impulse
    //          waves with much better win rate.
    //=================================================================
    else if(StringFind(sym, "BTCUSD") >= 0)
    {
        p.displayName  = "BTC/USD (Bitcoin)";
        p.tfMacro      = PERIOD_D1;   // ← UPGRADED: D1 macro for BTC
        p.tfSignal     = PERIOD_H4;   // ← UPGRADED: H4 signal
        p.atrDirMult   = 3.0;
        p.keltnerMult  = 3.0;         // Very wide KC — only catch dominant H4 moves
        p.rsiBuyMax    = 78.0;        // Crypto can sustain high RSI in bull runs
        p.rsiSellMin   = 22.0;
        p.slMult       = 3.0;         // BTC H4: 3×ATR needed to survive intraday noise
        p.tpMult       = 7.5;         // R:R = 1:2.5  (7.5 / 3.0)
        p.trailMult    = 2.5;
        p.trailActiveMult = 2.0;      // Wait for 2×ATR profit before trailing
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 4000;
        p.maxDrawdownPct = 25.0;
        p.magicNumber  = 30007;
    }
    else if(StringFind(sym, "ETHUSD") >= 0)
    {
        p.displayName  = "ETH/USD (Ethereum)";
        p.tfMacro      = PERIOD_D1;   // ← UPGRADED: D1 macro
        p.tfSignal     = PERIOD_H4;   // ← UPGRADED: H4 signal
        p.atrDirMult   = 3.0;
        p.keltnerMult  = 3.0;
        p.rsiBuyMax    = 78.0;
        p.rsiSellMin   = 22.0;
        p.slMult       = 3.0;
        p.tpMult       = 7.5;         // R:R = 1:2.5
        p.trailMult    = 2.5;
        p.trailActiveMult = 2.0;
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 2000;
        p.magicNumber  = 30008;
    }

    //=================================================================
    //  ENERGY — H4 Macro + H4 Signal (UPGRADED signal TF from H1)
    //  Reason: Oil price on H1 is heavily influenced by intraday news
    //          (EIA reports, OPEC headlines) causing false KC breakouts.
    //          H4 as both macro and signal provides cleaner structure.
    //          Same-TF approach: macro trend + signal evaluated each H4 bar.
    //=================================================================
    else if(StringFind(sym, "USOIL") >= 0 || StringFind(sym, "WTIUSD") >= 0 ||
            StringFind(sym, "XTIUSD") >= 0)
    {
        p.displayName  = "USOIL (WTI Crude)";
        p.tfMacro      = PERIOD_H4;   // H4 macro (EMA200 on H4 = ~200 bars ≈ 33 days)
        p.tfSignal     = PERIOD_H4;   // ← UPGRADED: H4 signal (same TF)
        p.atrDirMult   = 2.5;
        p.keltnerMult  = 2.5;         // Wider KC for H4 oil
        p.rsiBuyMax    = 74.0;
        p.rsiSellMin   = 26.0;
        p.slMult       = 2.2;
        p.tpMult       = 5.5;         // R:R = 1:2.5  (5.5 / 2.2)
        p.trailMult    = 2.0;
        p.trailActiveMult = 1.5;
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 300;
        p.magicNumber  = 30009;
    }
    else if(StringFind(sym, "UKOIL") >= 0 || StringFind(sym, "BRENTUSD") >= 0 ||
            StringFind(sym, "XBRUSD") >= 0)
    {
        p.displayName  = "UKOIL (Brent Crude)";
        p.tfMacro      = PERIOD_H4;
        p.tfSignal     = PERIOD_H4;   // ← UPGRADED: H4 signal
        p.atrDirMult   = 2.5;
        p.keltnerMult  = 2.5;
        p.rsiBuyMax    = 74.0;
        p.rsiSellMin   = 26.0;
        p.slMult       = 2.2;
        p.tpMult       = 5.5;         // R:R = 1:2.5
        p.trailMult    = 2.0;
        p.trailActiveMult = 1.5;
        p.riskPercent  = 1.0;
        p.maxSpreadPts = 300;
        p.magicNumber  = 30010;
    }
    else
    {
        p.displayName  = "Unknown: " + symbol;
        p.atrDirMult   = 2.5;
        p.keltnerMult  = 2.2;
        p.rsiBuyMax    = 72.0;
        p.rsiSellMin   = 28.0;
        p.maxSpreadPts = 200;
        p.magicNumber  = 30000;
        Print("[AstraProfile] WARNING: No preset for '", symbol,
              "' — using defaults. Verify parameters before running.");
        return false;
    }
    return true;
}

#endif // ASTRA_INSTRUMENT_PROFILE_V2_MQH
