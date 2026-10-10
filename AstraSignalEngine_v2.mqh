//+------------------------------------------------------------------+
//|                               AstraSignalEngine_v2.mqh           |
//|            Sains Manajemen - Multi-Asset Industrial EA           |
//|               FMIPA Universitas Gadjah Mada (UGM) 2026           |
//+------------------------------------------------------------------+
//  v2.1 UPDATE:
//    - IsNewBarMacro() / IsNewBarSignal() replace old IsNewBar(tf)
//      so the engine is fully TF-agnostic (works for H4+H1, D1+H4,
//      H4+H4, etc. depending on the instrument profile).
//    - Deinit() lambda replaced with explicit code (broader compat).
//    - GetCurrentATR_Signal() added (ATR on signal TF for SL/TP).
//+------------------------------------------------------------------+
#property copyright "Sains Manajemen Project 2 - UGM 2026"

#ifndef ASTRA_SIGNAL_ENGINE_V2_MQH
#define ASTRA_SIGNAL_ENGINE_V2_MQH

#include <AstraInstrumentProfile_v2.mqh>

//+------------------------------------------------------------------+
//| CAstraSignalEngine — Multi-Timeframe Signal Generator            |
//+------------------------------------------------------------------+
class CAstraSignalEngine
{
private:
    SAstraProfile  m_profile;
    bool           m_initialized;

    //--- Macro TF indicators (tfMacro: H4 for Forex/Index, D1 for Metal/Crypto)
    int m_hEMA200_Macro;    // EMA(200) on macro TF
    int m_hATR_Macro;       // ATR(14) on macro TF

    //--- Signal TF indicators (tfSignal: H1 for Forex, H4 for Metal/Crypto/Energy)
    int m_hKC_EMA;          // EMA(keltnerPeriod) on signal TF — KC middle
    int m_hKC_ATR;          // ATR(keltnerPeriod) on signal TF — KC band width
    int m_hRSI_Signal;      // RSI(rsiPeriod) on signal TF
    int m_hATR_Signal;      // ATR(atrPeriod)  on signal TF — for SL/TP sizing

    //--- New bar timestamps (one per TF, not per hardcoded H4/H1)
    datetime m_lastBarMacro;    // Last processed macro TF bar
    datetime m_lastBarSignal;   // Last processed signal TF bar

    //+--------------------------------------------------------------+
    //| Internal: copy buffer with ArraySetAsSeries and size check   |
    //+--------------------------------------------------------------+
    bool SafeCopyBuf(int handle, int startPos, int count, double &arr[])
    {
        if(handle == INVALID_HANDLE) return false;
        ArraySetAsSeries(arr, true);
        return (CopyBuffer(handle, 0, startPos, count, arr) == count);
    }

    bool SafeCopyClose(ENUM_TIMEFRAMES tf, int startPos, int count, double &arr[])
    {
        ArraySetAsSeries(arr, true);
        return (CopyClose(m_profile.symbol, tf, startPos, count, arr) == count);
    }

    bool SafeCopyHigh(ENUM_TIMEFRAMES tf, int startPos, int count, double &arr[])
    {
        ArraySetAsSeries(arr, true);
        return (CopyHigh(m_profile.symbol, tf, startPos, count, arr) == count);
    }

    bool SafeCopyLow(ENUM_TIMEFRAMES tf, int startPos, int count, double &arr[])
    {
        ArraySetAsSeries(arr, true);
        return (CopyLow(m_profile.symbol, tf, startPos, count, arr) == count);
    }

public:
    //+--------------------------------------------------------------+
    CAstraSignalEngine() : m_initialized(false),
        m_hEMA200_Macro(INVALID_HANDLE), m_hATR_Macro(INVALID_HANDLE),
        m_hKC_EMA(INVALID_HANDLE),       m_hKC_ATR(INVALID_HANDLE),
        m_hRSI_Signal(INVALID_HANDLE),   m_hATR_Signal(INVALID_HANDLE),
        m_lastBarMacro(0),               m_lastBarSignal(0) {}

    //+--------------------------------------------------------------+
    //| Initialize indicator handles                                 |
    //+--------------------------------------------------------------+
    bool Init(const SAstraProfile &profile)
    {
        m_profile = profile;
        string sym = m_profile.symbol;

        //--- Macro TF handles (H4 for Forex/Index, D1 for Metal/Crypto)
        m_hEMA200_Macro = iMA(sym, m_profile.tfMacro,
                              m_profile.ema200Period, 0, MODE_EMA, PRICE_CLOSE);
        m_hATR_Macro    = iATR(sym, m_profile.tfMacro, m_profile.atrPeriod);

        //--- Signal TF handles (H1 for Forex, H4 for Metal/Crypto/Energy)
        m_hKC_EMA       = iMA(sym, m_profile.tfSignal,
                              m_profile.keltnerPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_hKC_ATR       = iATR(sym, m_profile.tfSignal, m_profile.keltnerPeriod);
        m_hRSI_Signal   = iRSI(sym, m_profile.tfSignal,
                               m_profile.rsiPeriod, PRICE_CLOSE);
        m_hATR_Signal   = iATR(sym, m_profile.tfSignal, m_profile.atrPeriod);

        if(m_hEMA200_Macro == INVALID_HANDLE || m_hATR_Macro    == INVALID_HANDLE ||
           m_hKC_EMA        == INVALID_HANDLE || m_hKC_ATR       == INVALID_HANDLE ||
           m_hRSI_Signal    == INVALID_HANDLE || m_hATR_Signal   == INVALID_HANDLE)
        {
            Print("[SignalEngine] ERROR: Failed to create handles for ", sym);
            return false;
        }

        m_initialized = true;
        Print("[SignalEngine] Initialized | ", m_profile.displayName);
        Print("[SignalEngine]   Macro TF : ", TFName(m_profile.tfMacro),
              " | EMA(", m_profile.ema200Period, ") + ATR Dir (mult=",
              m_profile.atrDirMult, ")");
        Print("[SignalEngine]   Signal TF: ", TFName(m_profile.tfSignal),
              " | KC(EMA", m_profile.keltnerPeriod, " ±",
              m_profile.keltnerMult, "×ATR) + RSI(", m_profile.rsiPeriod, ")");
        Print("[SignalEngine]   Volatility: ATR(", m_profile.atrPeriod,
              ") > SMA(ATR,20) on ", TFName(m_profile.tfSignal));
        return true;
    }

    //+--------------------------------------------------------------+
    //| Release all indicator handles                                |
    //+--------------------------------------------------------------+
    void Deinit()
    {
        if(m_hEMA200_Macro != INVALID_HANDLE) { IndicatorRelease(m_hEMA200_Macro); m_hEMA200_Macro = INVALID_HANDLE; }
        if(m_hATR_Macro    != INVALID_HANDLE) { IndicatorRelease(m_hATR_Macro);    m_hATR_Macro    = INVALID_HANDLE; }
        if(m_hKC_EMA       != INVALID_HANDLE) { IndicatorRelease(m_hKC_EMA);       m_hKC_EMA       = INVALID_HANDLE; }
        if(m_hKC_ATR       != INVALID_HANDLE) { IndicatorRelease(m_hKC_ATR);       m_hKC_ATR       = INVALID_HANDLE; }
        if(m_hRSI_Signal   != INVALID_HANDLE) { IndicatorRelease(m_hRSI_Signal);   m_hRSI_Signal   = INVALID_HANDLE; }
        if(m_hATR_Signal   != INVALID_HANDLE) { IndicatorRelease(m_hATR_Signal);   m_hATR_Signal   = INVALID_HANDLE; }
        m_initialized = false;
    }

    //+--------------------------------------------------------------+
    //| New bar detection — MACRO timeframe                          |
    //| Returns true once per new bar on m_profile.tfMacro           |
    //+--------------------------------------------------------------+
    bool IsNewBarMacro()
    {
        datetime t = iTime(m_profile.symbol, m_profile.tfMacro, 0);
        if(t != m_lastBarMacro) { m_lastBarMacro = t; return true; }
        return false;
    }

    //+--------------------------------------------------------------+
    //| New bar detection — SIGNAL timeframe                         |
    //| Returns true once per new bar on m_profile.tfSignal          |
    //| NOTE: If tfMacro == tfSignal (e.g. Energy H4+H4), both       |
    //|       IsNewBarMacro() and IsNewBarSignal() fire on the same  |
    //|       bar — macro updates first, then signal is evaluated.   |
    //+--------------------------------------------------------------+
    bool IsNewBarSignal()
    {
        datetime t = iTime(m_profile.symbol, m_profile.tfSignal, 0);
        if(t != m_lastBarSignal) { m_lastBarSignal = t; return true; }
        return false;
    }

    //+--------------------------------------------------------------+
    //| LAYER 1: Macro Trend (on macro TF)                           |
    //|                                                              |
    //| H4 (Forex/Index): EMA200_H4 + ATR Directional Buffer         |
    //| D1 (Metal/Crypto): EMA200_D1 + ATR Directional Buffer        |
    //|                                                              |
    //| Returns: 1=BULL, -1=BEAR, 0=NEUTRAL                          |
    //+--------------------------------------------------------------+
    int GetMacroTrend()
    {
        if(!m_initialized) return 0;

        double ema200[3], atr_mac[3], close_mac[3];

        // All reads from bar-1 onwards (confirmed closed bars only)
        if(!SafeCopyBuf(m_hEMA200_Macro, 1, 3, ema200))              return 0;
        if(!SafeCopyBuf(m_hATR_Macro,    1, 3, atr_mac))             return 0;
        if(!SafeCopyClose(m_profile.tfMacro, 1, 3, close_mac))       return 0;

        // [0]=bar-1 (most recent closed), [1]=bar-2, [2]=bar-3

        // EMA200 momentum: is EMA200 trending?
        bool ema200Up = (ema200[0] > ema200[2]);
        bool ema200Dn = (ema200[0] < ema200[2]);

        // Price position vs EMA200 with noise buffer
        double bufBasic = atr_mac[0] * 0.15;          // ±15% ATR neutral zone
        bool priceAbove = (close_mac[0] > ema200[0] + bufBasic);
        bool priceBelow = (close_mac[0] < ema200[0] - bufBasic);

        // ATR Directional: price must be clearly away from EMA200
        // atrDirMult: 2.0 (Forex) / 2.5 (Metal/Energy) / 3.0 (Crypto)
        double bufStrong = atr_mac[0] * m_profile.atrDirMult * 0.4;
        bool strongBull  = (close_mac[0] > ema200[0] + bufStrong);
        bool strongBear  = (close_mac[0] < ema200[0] - bufStrong);

        // Decision (strongest condition takes priority)
        if(strongBull && ema200Up)   return  1;  // Strong bull: away from EMA + trending up
        if(strongBear && ema200Dn)   return -1;  // Strong bear
        if(priceAbove && ema200Up)   return  1;  // Moderate bull
        if(priceBelow && ema200Dn)   return -1;  // Moderate bear
        if(strongBull)               return  1;  // Weak bull (EMA200 not trending yet)
        if(strongBear)               return -1;  // Weak bear

        return 0;  // Neutral — stay out of market
    }

    //+--------------------------------------------------------------+
    //| LAYER 2: Signal Trigger (on signal TF)                       |
    //|                                                              |
    //| H1 (Forex): KC(EMA20 ± 2.0×ATR_H1) + RSI(14)               |
    //| H4 (Metal/Crypto/Energy): KC(EMA20 ± 2.5-3.0×ATR_H4) + RSI |
    //|                                                              |
    //| BUY : KC breakout UP + RSI in [40, rsiBuyMax] + rising RSI   |
    //| SELL: KC breakout DOWN + RSI in [rsiSellMin, 60] + falling   |
    //|                                                              |
    //| Returns: 1=BUY, -1=SELL, 0=NONE                             |
    //+--------------------------------------------------------------+
    int GetSignal(int macroTrend)
    {
        if(!m_initialized || macroTrend == 0) return 0;

        double kcEMA[3], kcATR[3], rsi[3], close_sig[3];

        // All from bar-1 offset (last confirmed closed bars on signal TF)
        if(!SafeCopyBuf(m_hKC_EMA,     1, 3, kcEMA))            return 0;
        if(!SafeCopyBuf(m_hKC_ATR,     1, 3, kcATR))            return 0;
        if(!SafeCopyBuf(m_hRSI_Signal, 1, 3, rsi))              return 0;
        if(!SafeCopyClose(m_profile.tfSignal, 1, 3, close_sig)) return 0;

        // Keltner Channel bands (bar-1 and bar-2)
        double kcU_b1 = kcEMA[0] + m_profile.keltnerMult * kcATR[0];
        double kcL_b1 = kcEMA[0] - m_profile.keltnerMult * kcATR[0];
        double kcU_b2 = kcEMA[1] + m_profile.keltnerMult * kcATR[1];
        double kcL_b2 = kcEMA[1] - m_profile.keltnerMult * kcATR[1];

        // KC Breakout: bar-2 inside/at band, bar-1 outside (fresh break)
        bool kcBreakUp   = (close_sig[0] > kcU_b1) && (close_sig[1] <= kcU_b2);
        bool kcBreakDown = (close_sig[0] < kcL_b1) && (close_sig[1] >= kcL_b2);

        // RSI Rebound Confirmation:
        //   BUY : RSI > 40 (momentum present) AND < rsiBuyMax (not overbought)
        //   SELL: RSI < 60 AND > rsiSellMin
        double rsiNow = rsi[0];
        bool rsiOkBuy  = (rsiNow > 40.0) && (rsiNow < m_profile.rsiBuyMax);
        bool rsiOkSell = (rsiNow < 60.0) && (rsiNow > m_profile.rsiSellMin);

        // RSI momentum direction
        bool rsiRising  = (rsi[0] > rsi[1]);
        bool rsiFalling = (rsi[0] < rsi[1]);

        // Final signal — all 3 conditions (macro + KC + RSI) must align
        if(macroTrend ==  1 && kcBreakUp   && rsiOkBuy  && rsiRising)  return  1;
        if(macroTrend == -1 && kcBreakDown && rsiOkSell && rsiFalling) return -1;

        return 0;
    }

    //+--------------------------------------------------------------+
    //| LAYER 3: Volatility Filter                                   |
    //| ATR(signal TF) > SMA(ATR, 20 bars)                          |
    //| Prevents entries during low-volatility sideways periods      |
    //+--------------------------------------------------------------+
    bool IsVolatilityOK()
    {
        if(!m_initialized) return false;

        double atrBuf[21];
        ArraySetAsSeries(atrBuf, true);
        // Copy 21 bars from bar-1 (closed bars only, offset=1)
        if(CopyBuffer(m_hATR_Signal, 0, 1, 21, atrBuf) < 21)
            return true;  // Not enough history → allow trade

        double currentATR = atrBuf[0];  // bar-1 ATR

        // SMA of the 20 bars BEFORE bar-1 (bars 1..20 in reversed array)
        double sumATR = 0.0;
        for(int i = 1; i <= 20; i++) sumATR += atrBuf[i];
        double smaATR = sumATR / 20.0;

        // Signal TF ATR must be above its own 20-bar average
        return (currentATR > smaATR);
    }

    //+--------------------------------------------------------------+
    //| ATR on SIGNAL timeframe — used by RiskManager for SL/TP     |
    //+--------------------------------------------------------------+
    double GetCurrentATR_Signal()
    {
        if(!m_initialized || m_hATR_Signal == INVALID_HANDLE) return 0.0;
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(m_hATR_Signal, 0, 1, 1, buf) < 1) return 0.0;
        return buf[0];
    }

    //+--------------------------------------------------------------+
    //| ATR on MACRO timeframe — for logging / dashboard             |
    //+--------------------------------------------------------------+
    double GetCurrentATR_Macro()
    {
        if(!m_initialized || m_hATR_Macro == INVALID_HANDLE) return 0.0;
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(m_hATR_Macro, 0, 1, 1, buf) < 1) return 0.0;
        return buf[0];
    }

    //+--------------------------------------------------------------+
    //| EMA200 on macro TF — for dashboard / chart comment           |
    //+--------------------------------------------------------------+
    double GetEMA200_Macro()
    {
        if(!m_initialized || m_hEMA200_Macro == INVALID_HANDLE) return 0.0;
        double buf[1];
        ArraySetAsSeries(buf, true);
        if(CopyBuffer(m_hEMA200_Macro, 0, 1, 1, buf) < 1) return 0.0;
        return buf[0];
    }

    //--- Expose profile TF info for OnTick logging
    ENUM_TIMEFRAMES GetMacroTF()  const { return m_profile.tfMacro;  }
    ENUM_TIMEFRAMES GetSignalTF() const { return m_profile.tfSignal; }
};

#endif // ASTRA_SIGNAL_ENGINE_V2_MQH
