//+------------------------------------------------------------------+
//|                               AstraRiskManager_v2.mqh            |
//|            Sains Manajemen - Multi-Asset Industrial EA           |
//|               FMIPA Universitas Gadjah Mada (UGM) 2026           |
//+------------------------------------------------------------------+
//  PURPOSE  : Handles all risk-related operations:
//             - Cash-equivalent lot sizing (1:1 No-Leverage model)
//             - Dynamic ATR Trailing Stop with activation threshold
//             - Equity Drawdown Circuit Breaker (Max DD 25%)
//             - Buy/Sell execution with ATR-based SL/TP
//  DEPENDS  : AstraInstrumentProfile_v2.mqh, Trade/Trade.mqh
//+------------------------------------------------------------------+
#property copyright "Sains Manajemen Project 2 - UGM 2026"

#ifndef ASTRA_RISK_MANAGER_V2_MQH
#define ASTRA_RISK_MANAGER_V2_MQH

#include <AstraInstrumentProfile_v2.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| CAstraRiskManager — Risk & Execution Module                      |
//+------------------------------------------------------------------+
class CAstraRiskManager
{
private:
    SAstraProfile  m_profile;
    CTrade         m_trade;
    double         m_peakEquity;       // Rolling peak equity for DD calculation
    bool           m_circuitBreaker;   // True = trading halted
    bool           m_initialized;

    //--- Internal helper: get symbol digits for print formatting
    int SymDigits() const
    {
        return (int)SymbolInfoInteger(m_profile.symbol, SYMBOL_DIGITS);
    }

public:
    //+--------------------------------------------------------------+
    CAstraRiskManager() : m_peakEquity(0.0),
                          m_circuitBreaker(false),
                          m_initialized(false) {}

    //+--------------------------------------------------------------+
    //| Initialize — must be called once in OnInit()                 |
    //+--------------------------------------------------------------+
    bool Init(const SAstraProfile &profile)
    {
        m_profile = profile;
        m_trade.SetExpertMagicNumber(m_profile.magicNumber);
        m_trade.SetDeviationInPoints(30);
        m_trade.SetAsyncMode(false);

        m_peakEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
        m_circuitBreaker = false;
        m_initialized    = true;

        Print("[RiskMgr] Initialized | ", m_profile.displayName,
              " | Risk=", m_profile.riskPercent, "% | SL=", m_profile.slMult,
              "xATR | TP=", m_profile.tpMult, "xATR | R:R=1:",
              DoubleToString(m_profile.tpMult / m_profile.slMult, 2),
              " | MaxDD=", m_profile.maxDrawdownPct, "%");
        return true;
    }

    //+--------------------------------------------------------------+
    //| Circuit Breaker: track peak equity, halt if DD exceeded      |
    //| Call this every tick. Returns true when halted.              |
    //+--------------------------------------------------------------+
    bool CheckCircuitBreaker()
    {
        if(!m_initialized) return true;
        if(m_circuitBreaker) return true;

        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(equity > m_peakEquity) m_peakEquity = equity;

        if(m_peakEquity > 0.0)
        {
            double dd = (m_peakEquity - equity) / m_peakEquity * 100.0;
            if(dd >= m_profile.maxDrawdownPct)
            {
                Print("[RiskMgr] *** CIRCUIT BREAKER TRIGGERED ***");
                Print("[RiskMgr] DD=", DoubleToString(dd, 2), "% >= Limit=",
                      m_profile.maxDrawdownPct, "% | PeakEquity=",
                      DoubleToString(m_peakEquity, 2),
                      " | CurrentEquity=", DoubleToString(equity, 2));
                m_circuitBreaker = true;
                CloseAllPositions();
            }
        }
        return m_circuitBreaker;
    }

    bool IsCircuitBreakerTripped()     const { return m_circuitBreaker; }
    bool IsInitialized()               const { return m_initialized;    }
    double GetPeakEquity()             const { return m_peakEquity;     }

    double GetCurrentDrawdownPct() const
    {
        if(m_peakEquity <= 0.0) return 0.0;
        double eq = AccountInfoDouble(ACCOUNT_EQUITY);
        return (m_peakEquity - eq) / m_peakEquity * 100.0;
    }

    //--- Manual reset (use with caution in live trading)
    void ResetCircuitBreaker()
    {
        m_circuitBreaker = false;
        m_peakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
        Print("[RiskMgr] Circuit breaker reset. New peak equity=",
              DoubleToString(m_peakEquity, 2));
    }

    //+--------------------------------------------------------------+
    //| Cash-Equivalent Lot Sizing (1:1 No-Leverage Model)           |
    //|                                                              |
    //| Formula:                                                     |
    //|   riskMoney = Balance × (riskPercent / 100)                  |
    //|   slDist    = atrValue × slMult                              |
    //|   lossPerLot= (slDist / tickSize) × tickValue               |
    //|   lot       = riskMoney / lossPerLot                         |
    //|                                                              |
    //| MathMax(minLot, lot) ensures lot > 0 on $100k 1:1 accounts  |
    //+--------------------------------------------------------------+
    double CalculateLotSize(double atrValue)
    {
        if(!m_initialized || atrValue <= 0.0) return 0.0;

        string sym      = m_profile.symbol;
        double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
        double riskMoney= balance * (m_profile.riskPercent / 100.0);
        double slDist   = atrValue * m_profile.slMult;

        double tickVal  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);

        if(tickSize <= 0.0 || tickVal <= 0.0 || slDist <= 0.0)
        {
            Print("[RiskMgr] WARNING: Invalid tick info. tickSize=", tickSize,
                  " tickVal=", tickVal, " slDist=", slDist);
            return 0.0;
        }

        double lossPerLot = (slDist / tickSize) * tickVal;
        if(lossPerLot <= 0.0) return 0.0;

        double lot = riskMoney / lossPerLot;

        // Normalize to broker lot constraints
        double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
        double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

        if(lotStep > 0.0)
            lot = MathFloor(lot / lotStep) * lotStep;

        // MathMax ensures non-zero lot (critical for 1:1 cash model on $100k)
        lot = MathMax(minLot, lot);
        lot = MathMin(maxLot, lot);

        return lot;
    }

    //+--------------------------------------------------------------+
    //| Dynamic ATR Trailing Stop                                    |
    //| - Activates only after floating profit >= trailActiveMult×ATR|
    //| - Trails at trailMult × ATR distance from current price      |
    //| - Call this every tick for open positions                    |
    //+--------------------------------------------------------------+
    void ManageTrailingStop(double atrValue)
    {
        if(!m_initialized || m_circuitBreaker || atrValue <= 0.0) return;

        string sym          = m_profile.symbol;
        double trailDist    = atrValue * m_profile.trailMult;
        double activateDist = atrValue * m_profile.trailActiveMult;
        double point        = SymbolInfoDouble(sym, SYMBOL_POINT);
        double stopsLevel   = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;

        // Ensure trailing distance respects broker's minimum stop level
        if(trailDist < stopsLevel)
            trailDist = stopsLevel * 1.1;  // 10% buffer above minimum

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(!PositionSelectByTicket(ticket)) continue;
            if(PositionGetString(POSITION_SYMBOL) != sym)    continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_profile.magicNumber) continue;

            long   posType   = PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double curSL     = PositionGetDouble(POSITION_SL);
            double curTP     = PositionGetDouble(POSITION_TP);
            double bid       = SymbolInfoDouble(sym, SYMBOL_BID);
            double ask       = SymbolInfoDouble(sym, SYMBOL_ASK);

            if(posType == POSITION_TYPE_BUY)
            {
                // Only activate after profit >= activation threshold
                if((bid - openPrice) < activateDist) continue;

                double newSL = NormalizeDouble(bid - trailDist,
                                              SymDigits());
                // Move SL only if it improves (higher than current)
                if(newSL > curSL + point)
                    m_trade.PositionModify(ticket, newSL, curTP);
            }
            else if(posType == POSITION_TYPE_SELL)
            {
                if((openPrice - ask) < activateDist) continue;

                double newSL = NormalizeDouble(ask + trailDist,
                                              SymDigits());
                // Move SL only if it improves (lower than current)
                if(newSL < curSL - point || curSL == 0.0)
                    m_trade.PositionModify(ticket, newSL, curTP);
            }
        }
    }

    //+--------------------------------------------------------------+
    //| Close all open positions managed by this EA                  |
    //+--------------------------------------------------------------+
    void CloseAllPositions()
    {
        string sym = m_profile.symbol;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(!PositionSelectByTicket(ticket)) continue;
            if(PositionGetString(POSITION_SYMBOL) != sym)    continue;
            if(PositionGetInteger(POSITION_MAGIC) != m_profile.magicNumber) continue;
            bool res = m_trade.PositionClose(ticket);
            if(!res)
                Print("[RiskMgr] WARNING: Failed to close ticket #", ticket,
                      " | Error: ", m_trade.ResultRetcode());
        }
    }

    //+--------------------------------------------------------------+
    //| Check if position is open for this EA on this symbol        |
    //+--------------------------------------------------------------+
    bool HasOpenPosition() const
    {
        string sym = m_profile.symbol;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == sym &&
               PositionGetInteger(POSITION_MAGIC) == m_profile.magicNumber)
                return true;
        }
        return false;
    }

    //+--------------------------------------------------------------+
    //| Spread filter — reject if spread too wide                   |
    //+--------------------------------------------------------------+
    bool IsSpreadAcceptable() const
    {
        string sym   = m_profile.symbol;
        double point = SymbolInfoDouble(sym, SYMBOL_POINT);
        if(point <= 0.0) return false;
        double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
        double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
        int spreadPts= (int)MathRound((ask - bid) / point);
        return (spreadPts <= m_profile.maxSpreadPts);
    }

    //+--------------------------------------------------------------+
    //| Execute BUY order with ATR-based SL and TP                  |
    //+--------------------------------------------------------------+
    bool ExecuteBuy(double atrValue, const string comment = "Astra Buy")
    {
        if(!m_initialized || m_circuitBreaker) return false;
        if(atrValue <= 0.0)
        {
            Print("[RiskMgr] ExecuteBuy: invalid ATR=", atrValue);
            return false;
        }

        string sym    = m_profile.symbol;
        int    digits = SymDigits();
        double ask    = SymbolInfoDouble(sym, SYMBOL_ASK);
        double slDist = atrValue * m_profile.slMult;
        double tpDist = atrValue * m_profile.tpMult;
        double sl     = NormalizeDouble(ask - slDist, digits);
        double tp     = NormalizeDouble(ask + tpDist, digits);
        double lot    = CalculateLotSize(atrValue);

        if(lot <= 0.0)
        {
            Print("[RiskMgr] ExecuteBuy: lot=0 — check balance/tick values");
            return false;
        }

        Print("[RiskMgr] BUY | Lot=", DoubleToString(lot, 2),
              " | Entry=", DoubleToString(ask, digits),
              " | SL=", DoubleToString(sl, digits),
              " | TP=", DoubleToString(tp, digits),
              " | ATR=", DoubleToString(atrValue, digits));

        return m_trade.Buy(lot, sym, ask, sl, tp, comment);
    }

    //+--------------------------------------------------------------+
    //| Execute SELL order with ATR-based SL and TP                 |
    //+--------------------------------------------------------------+
    bool ExecuteSell(double atrValue, const string comment = "Astra Sell")
    {
        if(!m_initialized || m_circuitBreaker) return false;
        if(atrValue <= 0.0)
        {
            Print("[RiskMgr] ExecuteSell: invalid ATR=", atrValue);
            return false;
        }

        string sym    = m_profile.symbol;
        int    digits = SymDigits();
        double bid    = SymbolInfoDouble(sym, SYMBOL_BID);
        double slDist = atrValue * m_profile.slMult;
        double tpDist = atrValue * m_profile.tpMult;
        double sl     = NormalizeDouble(bid + slDist, digits);
        double tp     = NormalizeDouble(bid - tpDist, digits);
        double lot    = CalculateLotSize(atrValue);

        if(lot <= 0.0)
        {
            Print("[RiskMgr] ExecuteSell: lot=0 — check balance/tick values");
            return false;
        }

        Print("[RiskMgr] SELL | Lot=", DoubleToString(lot, 2),
              " | Entry=", DoubleToString(bid, digits),
              " | SL=", DoubleToString(sl, digits),
              " | TP=", DoubleToString(tp, digits),
              " | ATR=", DoubleToString(atrValue, digits));

        return m_trade.Sell(lot, sym, bid, sl, tp, comment);
    }
};

#endif // ASTRA_RISK_MANAGER_V2_MQH
