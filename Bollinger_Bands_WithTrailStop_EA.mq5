//+--------------------------------------------------------------------------+
//|                                     Bollinger_Bands_EA.mq5               |
//|                                                                          |
//| This Expert Advisor implements a strategy based on Bollinger Bands:      |
//| 1. NEW: Doji Reversal Bounce from Upper/Lower Bands, with confirmation.  |
//| 2. Mean Reversion (Bounces) with candlestick confirmation.               |
//|    Trades only in ranging markets.                                       |
//| 3. Breakout from a Bollinger Band Squeeze.                               |
//| Includes dynamic (ATR-based) Stop Loss and fixed Take Profit.            |
//| Dynamic position sizing and max lot size (1.0).                          |
//| Includes minimum volatility filter for all trades.                       |
//| NEW: Breakeven logic and stricter squeeze width filter.                  |
//| NEW: Trend-Following Strategy based on EMA Crossover with Trailing SL.   |
//+--------------------------------------------------------------------------+
#property copyright "Shoxwaves Labratory"
#property link      "https://www.mql5.com"
#property version   "1.09" // Updated version: Added Doji Bounce BB strategy
#property description "Bollinger Bands & Trend-Following Combined Strategy"
#property strict

//--- Input parameters
input string            EA_Name                 = "Bollinger_Bands_EA";    // EA Name for comments/logs
input double            RiskPerTradePercent     = 1.0;                     // Risk percentage per trade (e.g., 1.0 for 1%)
input double            StopLossATRMultiplier   = 2.5;                     // Adjusted: Stop Loss as a multiplier of ATR (e.g., 2.5 * ATR)
input int               TakeProfitPips          = 750;                     // Take Profit in pips (from entry price) - Original 1:3 RRR with 250 SL
input int               BBPeriod                = 20;                      // Bollinger Bands Period
input double            BBDeviation             = 2.0;                     // Bollinger Bands Standard Deviations
input ENUM_MA_METHOD    BBMethod                = MODE_SMA;                // Bollinger Bands Moving Average Method (kept for clarity in inputs)
input ENUM_APPLIED_PRICE BBAppliedPrice         = PRICE_CLOSE;             // Bollinger Bands Applied Price
input int               SqueezeLookbackBars     = 100;                     // Bars to look back for the lowest Bollinger Band Width
input int               ATRPeriod               = 14;                      // Period for ATR calculation for dynamic SL and candle body check
input double            MinConfirmationBodyATRMultiplier = 0.3;            // Minimum confirmation candle body size as a multiplier of ATR
input double            MaxDojiBodyRatio        = 0.1;                     // Max body size relative to range for a Doji (e.g., 0.1 for 10%)
input int               LongEMAPeriodForRanging = 200;                     // Period for EMA to check ranging market
input double            MaxEMASlopeForRanging   = 0.00001;                 // Max slope for EMA to consider market ranging (adjust based on symbol's point size)
input double            MinATRForTradingMultiplier = 0.5;                  // Minimum current ATR (as multiplier of ATR) required for any trade
input double            MaxSqueezeWidthATRMultiplier = 1.0;                // Max BB Width (as ATR multiplier) for a squeeze to be considered valid
input int               BreakevenTriggerPips    = 100;                      // Profit in pips to move SL to breakeven
input int               BreakevenBufferPips     = 50;                       // Pips to add to breakeven SL (to cover spread/commission)
input double            MaxLotSize              = 1.0;                     // Maximum lot size to trade
input bool              EnableTrading           = true;                    // Enable/Disable trading by this EA
input long              MagicNumber             = 223344;                  // Unique ID for Bollinger Bands strategy trades

//--- NEW: Trend Following Strategy Inputs
input bool              EnableTrendFollowing    = true;                    // Enable/Disable Trend Following Strategy
input int               TrendFastEMAPeriod      = 10;                      // Fast EMA period for Trend Following
input int               TrendSlowEMAPeriod      = 20;                      // Slow EMA period for Trend Following
input int               TrendTrailingStopPips   = 50;                      // Trailing Stop in pips for Trend Following trades (0 to disable)
input long              TrendMagicNumber        = 334455;                  // Unique ID for Trend Following strategy trades

//--- Global variables
datetime                lastBarTime             = 0;                       // To track the time of the last processed bar

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print(EA_Name, " initialized.");

    //--- Validate common input parameters
    if (RiskPerTradePercent <= 0 || RiskPerTradePercent > 5)
    {
        Print("ERROR: RiskPerTradePercent must be between 0.1 and 5.0.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (StopLossATRMultiplier <= 0 || TakeProfitPips <= 0)
    {
        Print("ERROR: StopLossATRMultiplier and TakeProfitPips must be greater than 0.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (MaxLotSize <= 0)
    {
        Print("ERROR: MaxLotSize must be greater than 0.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (ATRPeriod <= 0)
    {
        Print("ERROR: ATRPeriod must be greater than 0.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (MinATRForTradingMultiplier <= 0)
    {
        Print("ERROR: MinATRForTradingMultiplier must be greater than 0.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (BreakevenTriggerPips <= 0)
    {
        Print("ERROR: BreakevenTriggerPips must be greater than 0.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (BreakevenBufferPips < 0)
    {
        Print("ERROR: BreakevenBufferPips cannot be negative.");
        return INIT_PARAMETERS_INCORRECT;
    }

    //--- Validate Bollinger Bands specific parameters if enabled
    if (EnableTrading) // This refers to the BB strategy
    {
        if (BBPeriod <= 0 || BBDeviation <= 0)
        {
            Print("ERROR: BBPeriod and BBDeviation must be greater than 0 for Bollinger Bands strategy.");
            return INIT_PARAMETERS_INCORRECT;
        }
        if (SqueezeLookbackBars <= 0)
        {
            Print("ERROR: SqueezeLookbackBars must be greater than 0 for Bollinger Bands strategy.");
            return INIT_PARAMETERS_INCORRECT;
        }
        if (MinConfirmationBodyATRMultiplier <= 0)
        {
            Print("ERROR: MinConfirmationBodyATRMultiplier must be greater than 0 for Bollinger Bands strategy.");
            return INIT_PARAMETERS_INCORRECT;
        }
        if (MaxDojiBodyRatio <= 0 || MaxDojiBodyRatio >= 1.0)
        {
            Print("ERROR: MaxDojiBodyRatio must be between 0.01 and 0.99 for Bollinger Bands strategy.");
            return INIT_PARAMETERS_INCORRECT;
        }
        if (LongEMAPeriodForRanging <= 0)
        {
            Print("ERROR: LongEMAPeriodForRanging must be greater than 0 for Bollinger Bands strategy.");
            return INIT_PARAMETERS_INCORRECT;
        }
        if (MaxSqueezeWidthATRMultiplier <= 0)
        {
            Print("ERROR: MaxSqueezeWidthATRMultiplier must be greater than 0 for Bollinger Bands strategy.");
            return INIT_PARAMETERS_INCORRECT;
        }
    }

    //--- Validate Trend Following specific parameters if enabled
    if (EnableTrendFollowing)
    {
        if (TrendFastEMAPeriod <= 0 || TrendSlowEMAPeriod <= 0 || TrendFastEMAPeriod >= TrendSlowEMAPeriod)
        {
            Print("ERROR: Invalid Trend EMA periods. FastEMAPeriod must be less than SlowEMAPeriod and both > 0.");
            return INIT_PARAMETERS_INCORRECT;
        }
        if (TrendTrailingStopPips < 0)
        {
            Print("ERROR: TrendTrailingStopPips cannot be negative.");
            return INIT_PARAMETERS_INCORRECT;
        }
    }

    //--- Check if the symbol is available for trading
    if (!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
    {
    Print("ERROR: Symbol ", _Symbol, " is not available for trading.");
        return INIT_FAILED;
    }

    //--- Get the last bar time to prevent re-entry on the same bar
    lastBarTime = iTime(_Symbol, _Period, 0);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print(EA_Name, " deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check and manage open trades on every tick
    CheckAndMoveToBreakeven();
    CheckAndCloseTrendTrade();
    CheckAndMoveTrailingStop();

    //--- Check for a new bar on the current chart timeframe
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if (currentBarTime == lastBarTime)
    {
        return; 
    }
    lastBarTime = currentBarTime; // Update last bar time

    //--- Check for minimum volatility before considering any new trade
    double currentATR = GetATRValue(_Symbol, _Period, ATRPeriod, 1); // ATR of previous closed bar
    double minATRThreshold = currentATR * MinATRForTradingMultiplier; // Define minimum volatility based on current ATR
    double actualATR = GetATRValue(_Symbol, _Period, ATRPeriod, 0); // Current ATR for comparison
    
    if (actualATR < minATRThreshold)
    {
        // Print("DEBUG: Market not volatile enough (ATR: ", NormalizeDouble(actualATR, _Point), ", Min Threshold: ", NormalizeDouble(minATRThreshold, _Point), "). Skipping new trade signal check.");
        return;
    }
    // Print("DEBUG: Market volatile enough (ATR: ", NormalizeDouble(actualATR, _Point), ").");


    ENUM_ORDER_TYPE orderType = WRONG_VALUE;
    string tradeComment = "";
    long currentStrategyMagic = 0;

    //--- Try Bollinger Bands Strategy if enabled
    if (EnableTrading)
    {
        // Check if there's already an open trade for the Bollinger Bands strategy
        if (!IsTradeOrPendingOrderOpen(MagicNumber))
        {
            //--- NEW: Prioritize Doji Reversal Bounce from BB
            int dojiBBBounceSignal = IsDojiBBBounce(_Symbol, _Period, BBPeriod, BBDeviation, BBMethod, BBAppliedPrice, MaxDojiBodyRatio);
            if (dojiBBBounceSignal == 1) // Buy signal from Doji Bounce
            {
                orderType = ORDER_TYPE_BUY;
                tradeComment = EA_Name + " BUY (Doji BB Bounce)";
                currentStrategyMagic = MagicNumber;
                Print("DEBUG: Doji Bollinger Bands BUY bounce detected.");
            }
            else if (dojiBBBounceSignal == -1) // Sell signal from Doji Bounce
            {
                orderType = ORDER_TYPE_SELL;
                tradeComment = EA_Name + " SELL (Doji BB Bounce)";
                currentStrategyMagic = MagicNumber;
                Print("DEBUG: Doji Bollinger Bands SELL bounce detected.");
            }


            //--- If no Doji signal, try Mean Reversion Strategy First (only if market is ranging)
            if (orderType == WRONG_VALUE && IsMarketRanging(_Symbol, _Period, LongEMAPeriodForRanging, MaxEMASlopeForRanging))
            {
                int meanReversionSignal = IsMeanReversionBounce(_Symbol, _Period, BBPeriod, BBDeviation, BBMethod, BBAppliedPrice, ATRPeriod, MinConfirmationBodyATRMultiplier);
                if (meanReversionSignal == 1) // Buy signal from Mean Reversion
                {
                    orderType = ORDER_TYPE_BUY;
                    tradeComment = EA_Name + " BUY (Mean Reversion)";
                    currentStrategyMagic = MagicNumber;
                    Print("DEBUG: Mean Reversion BUY signal detected in ranging market.");
                }
                else if (meanReversionSignal == -1) // Sell signal from Mean Reversion
                {
                    orderType = ORDER_TYPE_SELL;
                    tradeComment = EA_Name + " SELL (Mean Reversion)";
                    currentStrategyMagic = MagicNumber;
                    Print("DEBUG: Mean Reversion SELL signal detected in ranging market.");
                }
            }
            // else if (orderType == WRONG_VALUE)
            // {
            //     Print("DEBUG: Market is trending, skipping Mean Reversion check.");
            // }


            //--- If no Mean Reversion signal, try Breakout Strategy (regardless of ranging/trending)
            if (orderType == WRONG_VALUE)
            {
                int breakoutSignal = IsBreakoutFromSqueeze(_Symbol, _Period, BBPeriod, BBDeviation, BBMethod, BBAppliedPrice, SqueezeLookbackBars, MaxSqueezeWidthATRMultiplier);
                if (breakoutSignal == 1) // Buy signal from Breakout
                {
                    orderType = ORDER_TYPE_BUY;
                    tradeComment = EA_Name + " BUY (Squeeze Breakout)";
                    currentStrategyMagic = MagicNumber;
                    Print("DEBUG: Squeeze Breakout BUY signal detected.");
                }
                else if (breakoutSignal == -1) // Sell signal from Breakout
                {
                    orderType = ORDER_TYPE_SELL;
                    tradeComment = EA_Name + " SELL (Squeeze Breakout)";
                    currentStrategyMagic = MagicNumber;
                    Print("DEBUG: Squeeze Breakout SELL signal detected.");
                }
            }
        }
    } // End if (EnableTrading)

    //--- Try Trend Following Strategy if enabled AND no Bollinger Bands signal
    if (orderType == WRONG_VALUE && EnableTrendFollowing)
    {
        // Check if there's already an open trade for the Trend Following strategy
        if (!IsTradeOrPendingOrderOpen(TrendMagicNumber))
        {
            int trendSignal = CheckTrendFollowingSignal(_Symbol, _Period, TrendFastEMAPeriod, TrendSlowEMAPeriod, BBMethod, BBAppliedPrice);
            if (trendSignal == 1) // Buy signal from Trend Following
            {
                orderType = ORDER_TYPE_BUY;
                tradeComment = EA_Name + " BUY (Trend Follow)";
                currentStrategyMagic = TrendMagicNumber;
                Print("DEBUG: Trend Following BUY signal detected.");
            }
            else if (trendSignal == -1) // Sell signal from Trend Following
            {
                orderType = ORDER_TYPE_SELL;
                tradeComment = EA_Name + " SELL (Trend Follow)";
                currentStrategyMagic = TrendMagicNumber;
                Print("DEBUG: Trend Following SELL signal detected.");
            }
        }
    }

    if (orderType == WRONG_VALUE)
    {
        // No valid signal from any enabled strategy, or trade already open for that strategy
        return; 
    }

    //--- All conditions met: Prepare to open a trade
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    // Calculate dynamic Stop Loss in points based on ATR
    double atrForSL = GetATRValue(_Symbol, _Period, ATRPeriod, 1); 
    if (atrForSL == 0.0)
    {
        Print("ERROR: ATR value is zero or invalid for SL calculation. Skipping trade.");
        return;
    }
    int dynamicStopLossPoints = (int)MathRound(atrForSL * StopLossATRMultiplier / point);
    if (dynamicStopLossPoints <= 0) 
    {
        dynamicStopLossPoints = 10; // Default to 10 points if calculated SL is too small
        Print("WARNING: Dynamic SL was too small, defaulted to 10 points.");
    }
    
    // Calculate Lot Size using the Stop Loss in points
    double lotSize = CalculateLotSize(RiskPerTradePercent, dynamicStopLossPoints, MaxLotSize);
    if (lotSize <= 0)
    {
        Print("ERROR: Calculated lot size is zero or negative. Cannot open trade.");
        return;
    }

    double entryPrice;
    double slPrice;
    double tpPrice;

    // Adjust TP based on new dynamic SL to maintain RRR (1:3)
    int dynamicTakeProfitPoints = dynamicStopLossPoints * 3; // Maintain 1:3 RRR

    if (orderType == ORDER_TYPE_BUY)
    {
        entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        slPrice = NormalizeDouble(entryPrice - (dynamicStopLossPoints * point), digits);
        tpPrice = NormalizeDouble(entryPrice + (dynamicTakeProfitPoints * point), digits);
    }
    else // ORDER_TYPE_SELL
    {
        entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        slPrice = NormalizeDouble(entryPrice + (dynamicStopLossPoints * point), digits);
        tpPrice = NormalizeDouble(entryPrice - (dynamicTakeProfitPoints * point), digits);
    }

    //--- Create a new trade request
    MqlTradeRequest request;
    MqlTradeResult  result;

    ZeroMemory(request);
    request.action      = TRADE_ACTION_DEAL;              // Direct market execution
    request.symbol      = _Symbol;                        // Symbol
    request.volume      = lotSize;                        // Trade volume
    request.type        = orderType;                      // Order type (BUY/SELL)
    request.price       = entryPrice;                     // Current market price
    request.sl          = slPrice;                        // Stop Loss price
    request.tp          = tpPrice;                        // Take Profit price
    request.deviation   = 10;                             // Allowed deviation from current price in points
    request.magic       = currentStrategyMagic;           // Use the magic number of the strategy that generated the signal
    request.comment     = tradeComment;                   // Comment for the order
    request.type_filling = ORDER_FILLING_IOC;             // Immediate or Cancel

    //--- Send the order
    if (!OrderSend(request, result))
    {
        Print("OrderSend failed, error code: ", GetLastError());
    }
    else
    {
        if (result.retcode == TRADE_RETCODE_DONE)
        {
            Print(EnumToString(orderType), " order opened successfully! Ticket: ", result.deal,
                  " | Entry: ", NormalizeDouble(entryPrice, digits),
                  " | SL: ", NormalizeDouble(slPrice, digits), " (", dynamicStopLossPoints, " pts)",
                  " | TP: ", NormalizeDouble(tpPrice, digits), " (", dynamicTakeProfitPoints, " pts)",
                  " | Strategy Magic: ", currentStrategyMagic);
        }
        else
        {
            Print("OrderSend failed. Return code: ", result.retcode);
            Print("Reason: ", result.comment);
        }
    }
}

//+------------------------------------------------------------------+
//| Helper function to check if a trade or pending order managed by  |
//| this EA is already open for the current symbol, optionally by magic number. |
//+------------------------------------------------------------------+
bool IsTradeOrPendingOrderOpen(long magic = 0) // Default 0 means check for any magic number from this EA
{
    // Check for open positions
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong position_ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(position_ticket))
        {
            if (PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                if (magic == 0 || PositionGetInteger(POSITION_MAGIC) == magic)
                {
                    return true;
                }
            }
        }
    }

    // Check for pending orders
    for (int i = 0; i < OrdersTotal(); i++)
    {
        ulong order_ticket = OrderGetTicket(i);
        if (OrderGetString(ORDER_SYMBOL) == _Symbol)
        {
            if (magic == 0 || OrderGetInteger(ORDER_MAGIC) == magic)
            {
                if (OrderGetInteger(ORDER_TYPE) >= ORDER_TYPE_BUY_LIMIT && OrderGetInteger(ORDER_TYPE) <= ORDER_TYPE_SELL_STOP_LIMIT)
                {
                    return true;
                }
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Helper function to move SL to breakeven if profit target is met. |
//+------------------------------------------------------------------+
void CheckAndMoveToBreakeven()
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong position_ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(position_ticket))
        {
            // Only check positions opened by THIS EA's magic numbers
            long posMagic = PositionGetInteger(POSITION_MAGIC);
            if (PositionGetString(POSITION_SYMBOL) == _Symbol && (posMagic == MagicNumber || posMagic == TrendMagicNumber))
            {
                double currentSL = PositionGetDouble(POSITION_SL);
                double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double currentProfit = PositionGetDouble(POSITION_PROFIT); // Profit in deposit currency
                
                double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
                double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                double volume = PositionGetDouble(POSITION_VOLUME);

                // Convert BreakevenTriggerPips to profit in currency
                double breakevenTriggerProfit = BreakevenTriggerPips * (point / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)) * tickValue * volume;
                
                // Calculate breakeven SL price
                double newSLPrice = 0.0;
                if (posType == POSITION_TYPE_BUY)
                {
                    // If current profit meets trigger AND current SL is below new breakeven SL
                    if (currentProfit >= breakevenTriggerProfit && currentSL < (entryPrice + BreakevenBufferPips * point))
                    {
                        newSLPrice = NormalizeDouble(entryPrice + BreakevenBufferPips * point, digits);
                    }
                }
                else if (posType == POSITION_TYPE_SELL)
                {
                    // If current profit meets trigger AND current SL is above new breakeven SL
                    if (currentProfit >= breakevenTriggerProfit && currentSL > (entryPrice - BreakevenBufferPips * point))
                    {
                        newSLPrice = NormalizeDouble(entryPrice - BreakevenBufferPips * point, digits);
                    }
                }

                if (newSLPrice != 0.0)
                {
                    MqlTradeRequest request;
                    MqlTradeResult result;
                    ZeroMemory(request);

                    request.action = TRADE_ACTION_SLTP;
                    request.position = position_ticket;
                    request.sl = newSLPrice;
                    request.tp = PositionGetDouble(POSITION_TP); // Keep original TP

                    if (!OrderSend(request, result))
                    {
                        Print("Failed to move SL to breakeven for ticket ", position_ticket, ". Error: ", GetLastError());
                    }
                    else
                    {
                        if (result.retcode == TRADE_RETCODE_DONE)
                        {
                            Print("Moved SL to breakeven for ticket ", position_ticket, " at ", NormalizeDouble(newSLPrice, digits));
                        }
                        else
                        {
                            Print("Failed to move SL to breakeven for ticket ", position_ticket, ". Return code: ", result.retcode);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper function to close trend-following trades on reversal.     |
//+------------------------------------------------------------------+
void CheckAndCloseTrendTrade()
{
    // Get current EMA values for exit check
    double fastMA_current = GetMAValue(_Symbol, _Period, TrendFastEMAPeriod, BBMethod, BBAppliedPrice, 1);
    double slowMA_current = GetMAValue(_Symbol, _Period, TrendSlowEMAPeriod, BBMethod, BBAppliedPrice, 1);
    double fastMA_prev = GetMAValue(_Symbol, _Period, TrendFastEMAPeriod, BBMethod, BBAppliedPrice, 2);
    double slowMA_prev = GetMAValue(_Symbol, _Period, TrendSlowEMAPeriod, BBMethod, BBAppliedPrice, 2);

    if (fastMA_current == 0.0 || slowMA_current == 0.0 || fastMA_prev == 0.0 || slowMA_prev == 0.0)
    {
        // Print("ERROR: Could not retrieve MA values for trend exit check.");
        return;
    }

    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong position_ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(position_ticket))
        {
            // Only manage positions opened by the Trend Following strategy
            if (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == TrendMagicNumber)
            {
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                bool closeSignal = false;

                if (posType == POSITION_TYPE_BUY)
                {
                    // Close BUY if Fast EMA crosses below Slow EMA
                    if (fastMA_current < slowMA_current && fastMA_prev >= slowMA_prev)
                    {
                        closeSignal = true;
                        Print("DEBUG: Trend Follow BUY exit signal detected (bearish crossover).");
                    }
                }
                else if (posType == POSITION_TYPE_SELL)
                {
                    // Close SELL if Fast EMA crosses above Slow EMA
                    if (fastMA_current > slowMA_current && fastMA_prev <= slowMA_prev)
                    {
                        closeSignal = true;
                        Print("DEBUG: Trend Follow SELL exit signal detected (bullish crossover).");
                    }
                }

                if (closeSignal)
                {
                    MqlTradeRequest request;
                    MqlTradeResult result;
                    ZeroMemory(request);

                    request.action = TRADE_ACTION_DEAL;
                    request.position = position_ticket;
                    request.symbol = PositionGetString(POSITION_SYMBOL);
                    request.volume = PositionGetDouble(POSITION_VOLUME);
                    request.deviation = 10;
                    request.magic = TrendMagicNumber;
                    request.comment = EA_Name + " Trend Exit";

                    if (posType == POSITION_TYPE_BUY)
                    {
                        request.type = ORDER_TYPE_SELL;
                        request.price = SymbolInfoDouble(request.symbol, SYMBOL_BID);
                    }
                    else // POSITION_TYPE_SELL
                    {
                        request.type = ORDER_TYPE_BUY;
                        request.price = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
                    }

                    if (!OrderSend(request, result))
                    {
                        Print("Failed to close trend trade ", position_ticket, ". Error: ", GetLastError());
                    }
                    else
                    {
                        if (result.retcode == TRADE_RETCODE_DONE)
                        {
                            Print("Trend trade ", position_ticket, " closed successfully by reversal.");
                        }
                        else
                        {
                            Print("Failed to close trend trade ", position_ticket, ". Return code: ", result.retcode);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper function to move trailing stop for trend-following trades.|
//+------------------------------------------------------------------+
void CheckAndMoveTrailingStop()
{
    if (TrendTrailingStopPips <= 0) return; // Trailing stop disabled

    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong position_ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(position_ticket))
        {
            // Apply trailing stop to ALL trades opened by this EA (both BB and Trend-Following)
            long posMagic = PositionGetInteger(POSITION_MAGIC);
            if (PositionGetString(POSITION_SYMBOL) == _Symbol && (posMagic == MagicNumber || posMagic == TrendMagicNumber))
            {
                double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentSL = PositionGetDouble(POSITION_SL);
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                
                double newSLPrice = 0.0;
                double potentialNewSL; // Correctly declared here
                
                // Calculate minimum profit in pips required to activate trailing stop
                double profitInPips = (posType == POSITION_TYPE_BUY) ? 
                                      (currentPrice - entryPrice) / point : 
                                      (entryPrice - currentPrice) / point;

                if (profitInPips >= TrendTrailingStopPips) // Only activate/move if price is far enough in profit
                {
                    if (posType == POSITION_TYPE_BUY)
                    {
                        potentialNewSL = NormalizeDouble(currentPrice - (TrendTrailingStopPips * point), digits);
                        
                        // Only move SL if it's better than current SL and better than entry
                        if (potentialNewSL > currentSL && potentialNewSL > entryPrice)
                        {
                            newSLPrice = potentialNewSL;
                        }
                    }
                    else if (posType == POSITION_TYPE_SELL)
                    {
                        potentialNewSL = NormalizeDouble(currentPrice + (TrendTrailingStopPips * point), digits);
                        
                        // Only move SL if it's better than current SL and better than entry
                        if (potentialNewSL < currentSL && potentialNewSL < entryPrice)
                        {
                            newSLPrice = potentialNewSL;
                        }
                    }
                }

                if (newSLPrice != 0.0 && newSLPrice != currentSL) // Only modify if actual change
                {
                    MqlTradeRequest request;
                    MqlTradeResult result;
                    ZeroMemory(request);

                    request.action = TRADE_ACTION_SLTP;
                    request.position = position_ticket;
                    request.sl = newSLPrice;
                    request.tp = PositionGetDouble(POSITION_TP); // Keep original TP

                    if (!OrderSend(request, result))
                    {
                        Print("Failed to move Trailing SL for ticket ", position_ticket, ". Error: ", GetLastError());
                    }
                    else
                    {
                        if (result.retcode == TRADE_RETCODE_DONE)
                        {
                            Print("Moved Trailing SL for ticket ", position_ticket, " to ", NormalizeDouble(newSLPrice, digits));
                        }
                        else
                        {
                            Print("Failed to move Trailing SL for ticket ", position_ticket, ". Return code: ", result.retcode);
                        }
                    }
                }
            }
        }
    }
}


//+------------------------------------------------------------------+
//| Helper function to get MA value for a given symbol and timeframe|
//+------------------------------------------------------------------+
double GetMAValue(string symbol, ENUM_TIMEFRAMES timeframe, int maPeriod, ENUM_MA_METHOD maMethod, ENUM_APPLIED_PRICE appliedPrice, int shift)
{
    double ma_array[];
    int ma_handle = iMA(symbol, timeframe, maPeriod, 0, maMethod, appliedPrice);
    if (ma_handle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create MA handle for ", symbol, " ", timeframe, " period ", maPeriod, ", error: ", GetLastError());
        return 0.0;
    }

    if (CopyBuffer(ma_handle, 0, shift, 1, ma_array) <= 0)
    {
        Print("ERROR: Failed to copy MA buffer for ", symbol, " ", timeframe, ", error: ", GetLastError());
        return 0.0;
    }
    return ma_array[0];
}

//+------------------------------------------------------------------+
//| Helper function to get Bollinger Band values.                    |
//| band_index: 0=Middle, 1=Upper, 2=Lower                           |
//+------------------------------------------------------------------+
double GetBollingerBandValue(string symbol, ENUM_TIMEFRAMES timeframe, int bbPeriod, double bbDeviation, ENUM_MA_METHOD bbMethod, ENUM_APPLIED_PRICE appliedPrice, int shift, int band_index)
{
    double bb_array[];
    // Corrected the iBands function call to match the signature required by the user's environment.
    // The `bbMethod` parameter was removed, as per the original code's comment, to fix the parameter count mismatch.
    int bb_handle = iBands(symbol, timeframe, bbPeriod, 0, bbDeviation, appliedPrice);
    if (bb_handle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create BB handle for ", symbol, " ", timeframe, ", error: ", GetLastError());
        return 0.0;
    }

    if (CopyBuffer(bb_handle, band_index, shift, 1, bb_array) <= 0)
    {
        Print("ERROR: Failed to copy BB buffer for ", symbol, " ", timeframe, ", error: ", GetLastError());
        return 0.0;
    }
    return bb_array[0];
}

//+------------------------------------------------------------------+
//| Helper function to calculate Bollinger Band Width.               |
//+------------------------------------------------------------------+
double GetBollingerBandWidth(string symbol, ENUM_TIMEFRAMES timeframe, int bbPeriod, double bbDeviation, ENUM_MA_METHOD bbMethod, ENUM_APPLIED_PRICE appliedPrice, int shift)
{
    double upperBand = GetBollingerBandValue(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, shift, 1); // Upper Band
    double lowerBand = GetBollingerBandValue(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, shift, 2); // Lower Band
    double middleBand = GetBollingerBandValue(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, shift, 0); // Middle Band

    if (middleBand == 0.0) return 0.0; // Avoid division by zero

    return (upperBand - lowerBand) / middleBand;
}

//+------------------------------------------------------------------+
//| Helper function to get ATR value for a given symbol and timeframe|
//+------------------------------------------------------------------+
double GetATRValue(string symbol, ENUM_TIMEFRAMES timeframe, int atrPeriod, int shift)
{
    double atr_array[];
    int atr_handle = iATR(symbol, timeframe, atrPeriod);
    if (atr_handle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create ATR handle for ", symbol, " ", timeframe, " period ", atrPeriod, ", error: ", GetLastError());
        return 0.0;
    }

    if (CopyBuffer(atr_handle, 0, shift, 1, atr_array) <= 0)
    {
        Print("ERROR: Failed to copy ATR buffer for ", symbol, " ", timeframe, ", error: ", GetLastError());
        return 0.0;
    }
    return atr_array[0];
}

//+------------------------------------------------------------------+
//| Helper function to check if the market is ranging based on EMA slope.|
//| Returns true if the EMA is relatively flat.                      |
//+------------------------------------------------------------------+
bool IsMarketRanging(string symbol, ENUM_TIMEFRAMES timeframe, int emaPeriod, double maxSlope)
{
    // Get EMA values for previous two closed bars
    double ema_current = GetMAValue(symbol, timeframe, emaPeriod, MODE_EMA, PRICE_CLOSE, 1);
    double ema_prev = GetMAValue(symbol, timeframe, emaPeriod, MODE_EMA, PRICE_CLOSE, 2);

    if (ema_current == 0.0 || ema_prev == 0.0) return false;

    // Calculate slope (change in EMA value over 1 bar)
    double slope = MathAbs(ema_current - ema_prev);
    
    // Normalize slope by symbol's point size to make it more universal
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    slope = slope / point; // Slope in terms of points per bar

    // Market is ranging if the absolute slope is less than maxSlope
    return slope <= maxSlope;
}

//+------------------------------------------------------------------+
//| Helper function to detect Mean Reversion (Bounce) signal with    |
//| candlestick confirmation.                                        |
//| Returns 1 for BUY, -1 for SELL, 0 for no signal.                 |
//+------------------------------------------------------------------+
int IsMeanReversionBounce(string symbol, ENUM_TIMEFRAMES timeframe, int bbPeriod, double bbDeviation, ENUM_MA_METHOD bbMethod, ENUM_APPLIED_PRICE appliedPrice, int atrPeriod, double minConfirmationBodyATRMultiplier)
{
    MqlRates rates[2]; // rates[0] is previous closed bar, rates[1] is two bars ago
    if (CopyRates(symbol, timeframe, 1, 1, rates) != 1) // Get previous closed bar
    {
        Print("ERROR: Failed to copy rates for Mean Reversion check.");
        return 0;
    }

    double prevLow = rates[0].low;
    double prevHigh = rates[0].high;
    double prevClose = rates[0].close;

    double upperBand = GetBollingerBandValue(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, 1, 1);
    double lowerBand = GetBollingerBandValue(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, 1, 2);

    if (upperBand == 0.0 || lowerBand == 0.0) return 0; // Error in getting BB values

    // Bullish Bounce (Buy Signal): Low crossed below LB, but closed above LB, AND strong bullish candle
    if (prevLow < lowerBand && prevClose > lowerBand)
    {
        if (IsBullishEngulfing(symbol, timeframe, 1, atrPeriod, minConfirmationBodyATRMultiplier) ||
            IsHammer(symbol, timeframe, 1, atrPeriod, minConfirmationBodyATRMultiplier))
        {
            return 1; // BUY
        }
    }
    // Bearish Bounce (Sell Signal): High crossed above UB, but closed below UB, AND strong bearish candle
    else if (prevHigh > upperBand && prevClose < upperBand)
    {
        if (IsBearishEngulfing(symbol, timeframe, 1, atrPeriod, minConfirmationBodyATRMultiplier) ||
            IsShootingStar(symbol, timeframe, 1, atrPeriod, minConfirmationBodyATRMultiplier))
        {
            return -1; // SELL
        }
    }

    return 0; // No signal
}

//+------------------------------------------------------------------+
//| Helper function to check if a Bollinger Band Squeeze is active.  |
//| Returns true if current width is lowest in lookback period AND   |
//| below a maximum ATR-based threshold.                             |
//+------------------------------------------------------------------+
bool IsSqueezeActive(string symbol, ENUM_TIMEFRAMES timeframe, int bbPeriod, double bbDeviation, ENUM_MA_METHOD bbMethod, ENUM_APPLIED_PRICE appliedPrice, int lookbackBars, double maxSqueezeWidthATRMultiplier)
{
    double currentWidth = GetBollingerBandWidth(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, 1); // Current closed bar's width
    if (currentWidth == 0.0) return false;

    // NEW: Check if current width is below the maximum allowed for a squeeze (ATR based)
    double currentATR = GetATRValue(symbol, timeframe, ATRPeriod, 1);
    if (currentATR == 0.0) return false;
    double maxAllowedSqueezeWidth = currentATR * maxSqueezeWidthATRMultiplier;
    
    if (currentWidth > maxAllowedSqueezeWidth)
    {
        // Print("DEBUG: Squeeze width (", NormalizeDouble(currentWidth, _Point), ") is too wide (Max allowed: ", NormalizeDouble(maxAllowedSqueezeWidth, _Point), ").");
        return false; // Not a tight enough squeeze
    }

    // Check if current width is the lowest in the lookback period
    double minWidthInLookback = currentWidth;

    for (int i = 2; i <= lookbackBars; i++) // Check previous bars within lookback
    {
        double historyWidth = GetBollingerBandWidth(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, i);
        if (historyWidth == 0.0) continue; // Skip if error getting width

        if (historyWidth < minWidthInLookback)
        {
            minWidthInLookback = historyWidth;
        }
    }
    
    return (currentWidth <= minWidthInLookback); // Squeeze is active if current width is the lowest in the lookback period
}

//+------------------------------------------------------------------+
//| Helper function to detect a Breakout from a Squeeze.             |
//| Returns 1 for BUY, -1 for SELL, 0 for no signal.                 |
//+------------------------------------------------------------------+
int IsBreakoutFromSqueeze(string symbol, ENUM_TIMEFRAMES timeframe, int bbPeriod, double bbDeviation, ENUM_MA_METHOD bbMethod, ENUM_APPLIED_PRICE appliedPrice, int lookbackBars, double maxSqueezeWidthATRMultiplier)
{
    // First, check if a squeeze is active (using the stricter definition)
    if (!IsSqueezeActive(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, lookbackBars, maxSqueezeWidthATRMultiplier))
    {
        return 0; // No squeeze, no breakout
    }
    Print("DEBUG: Squeeze is active.");

    MqlRates rates[2]; // rates[0] is previous closed bar, rates[1] is two bars ago
    if (CopyRates(symbol, timeframe, 1, 1, rates) != 1) // Get previous closed bar
    {
        Print("ERROR: Failed to copy rates for Breakout check.");
        return 0;
    }

    double prevClose = rates[0].close;

    double upperBand = GetBollingerBandValue(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, 1, 1);
    double lowerBand = GetBollingerBandValue(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, 1, 2);

    if (upperBand == 0.0 || lowerBand == 0.0) return 0; // Error in getting BB values

    // Bullish Breakout: Previous candle closed above Upper Band
    if (prevClose > upperBand)
    {
        return 1; // BUY
    }
    // Bearish Breakout: Previous candle closed below Lower Band
    else if (prevClose < lowerBand)
    {
        return -1; // SELL
    }

    return 0; // No signal
}

//+------------------------------------------------------------------+
//| Helper function to detect a Bullish Engulfing pattern.           |
//| shift: 1 for previous bar and 2 for the bar before that.         |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(string symbol, ENUM_TIMEFRAMES timeframe, int shift, int atrPeriod, double minBodyATRMultiplier)
{
    MqlRates rates[2]; // rates[0] is 'shift', rates[1] is 'shift+1'
    if (CopyRates(symbol, timeframe, shift, 2, rates) != 2)
    {
        Print("ERROR: Failed to copy rates for Bullish Engulfing detection at shift ", shift);
        return false;
    }

    // Previous bar (rates[1]) is bearish
    bool prevBarBearish = (rates[1].close < rates[1].open);
    // Current bar being checked (rates[0]) is bullish
    bool currBarBullish = (rates[0].close > rates[0].open);

    double bodySize = MathAbs(rates[0].close - rates[0].open);
    double currentATR = GetATRValue(symbol, timeframe, atrPeriod, shift);
    if (currentATR == 0.0) return false;
    double minBodySize = currentATR * minBodyATRMultiplier;

    if (prevBarBearish && currBarBullish)
    {
        // Current bullish candle's body completely engulfs previous bearish candle's body
        if (rates[0].close > rates[1].open && rates[0].open < rates[1].close)
        {
            if (bodySize >= minBodySize)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Helper function to detect a Bearish Engulfing pattern.           |
//| shift: 1 for previous bar and 2 for the bar before that.         |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(string symbol, ENUM_TIMEFRAMES timeframe, int shift, int atrPeriod, double minBodyATRMultiplier)
{
    MqlRates rates[2]; // rates[0] is 'shift', rates[1] is 'shift+1'
    if (CopyRates(symbol, timeframe, shift, 2, rates) != 2)
    {
        Print("ERROR: Failed to copy rates for Bearish Engulfing detection at shift ", shift);
        return false;
    }

    // Previous bar (rates[1]) is bullish
    bool prevBarBullish = (rates[1].close > rates[1].open);
    // Current bar being checked (rates[0]) is bearish
    bool currBarBearish = (rates[0].close < rates[0].open);

    double bodySize = MathAbs(rates[0].close - rates[0].open);
    double currentATR = GetATRValue(symbol, timeframe, atrPeriod, shift);
    if (currentATR == 0.0) return false;
    double minBodySize = currentATR * minBodyATRMultiplier;

    if (prevBarBullish && currBarBearish)
    {
        // Current bearish candle's body completely engulfs previous bullish candle's body
        if (rates[0].close < rates[1].open && rates[0].open > rates[1].close)
        {
            if (bodySize >= minBodySize)
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Helper function to detect a Hammer pattern.                      |
//+------------------------------------------------------------------+
bool IsHammer(string symbol, ENUM_TIMEFRAMES timeframe, int shift, int atrPeriod, double minBodyATRMultiplier)
{
    MqlRates rates[1];
    if (CopyRates(symbol, timeframe, shift, 1, rates) != 1)
    {
        Print("ERROR: Failed to copy rates for Hammer detection at shift ", shift);
        return false;
    }

    double open = rates[0].open;
    double close = rates[0].close;
    double high = rates[0].high;
    double low = rates[0].low;

    double body = MathAbs(close - open);
    double lowerShadow = (open > close) ? (open - low) : (close - low);
    double upperShadow = (open > close) ? (high - open) : (high - close);

    double totalRange = high - low;
    if (totalRange == 0) return false; // Avoid division by zero

    double currentATR = GetATRValue(symbol, timeframe, atrPeriod, shift);
    if (currentATR == 0.0) return false;
    double minBodySize = currentATR * minBodyATRMultiplier;

    // Hammer conditions:
    // 1. Small body relative to total range (e.g., body < 30% of range)
    // 2. Long lower shadow (at least twice the size of the body)
    // 3. Little or no upper shadow (e.g., upperShadow <= body * 0.2)
    // 4. Body must meet minimum size for confirmation
    if (body > 0 && (body / totalRange <= 0.3) && // Small body relative to range
        lowerShadow >= 2 * body &&                // Long lower shadow
        upperShadow <= body * 0.2 &&              // Little upper shadow
        body >= minBodySize)                      // Body meets minimum size
    {
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Helper function to detect a Shooting Star pattern.               |
//+------------------------------------------------------------------+
bool IsShootingStar(string symbol, ENUM_TIMEFRAMES timeframe, int shift, int atrPeriod, double minBodyATRMultiplier)
{
    MqlRates rates[1];
    if (CopyRates(symbol, timeframe, shift, 1, rates) != 1)
    {
        Print("ERROR: Failed to copy rates for Shooting Star detection at shift ", shift);
        return false;
    }

    double open = rates[0].open;
    double close = rates[0].close;
    double high = rates[0].high;
    double low = rates[0].low;

    double body = MathAbs(close - open);
    double lowerShadow = (open > close) ? (open - low) : (close - low);
    double upperShadow = (open > close) ? (high - open) : (high - close);

    // Shooting Star conditions:
    // 1. Small body relative to total range
    // 2. Long upper shadow (at least twice the size of the body)
    // 3. Little or no lower shadow (e.g., lowerShadow <= body * 0.2)
    // 4. Body must meet minimum size for confirmation
    double totalRange = high - low;
    if (totalRange == 0) return false; // Avoid division by zero

    double currentATR = GetATRValue(symbol, timeframe, atrPeriod, shift);
    if (currentATR == 0.0) return false;
    double minBodySize = currentATR * minBodyATRMultiplier;

    if (body > 0 && (body / totalRange <= 0.3) && // Small body relative to range
        upperShadow >= 2 * body &&                // Long upper shadow
        lowerShadow <= body * 0.2 &&              // Little lower shadow
        body >= minBodySize)                      // Body meets minimum size
    {
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Helper function to check if a candle is a Doji.                  |
//| A Doji has a very small body relative to its total range.        |
//+------------------------------------------------------------------+
bool IsDoji(string symbol, ENUM_TIMEFRAMES timeframe, int shift, double maxDojiBodyRatio)
{
    MqlRates rates[1];
    if (CopyRates(symbol, timeframe, shift, 1, rates) != 1)
    {
        Print("ERROR: Failed to copy rates for Doji detection at shift ", shift);
        return false;
    }

    double open = rates[0].open;
    double close = rates[0].close;
    double high = rates[0].high;
    double low = rates[0].low;

    double bodySize = MathAbs(close - open);
    double totalRange = high - low;

    if (totalRange == 0) return false; // Avoid division by zero

    // Doji condition: body is very small relative to the total range
    return (bodySize / totalRange <= maxDojiBodyRatio);
}

//+------------------------------------------------------------------+
//| Helper function to detect a Doji that has pierced a Bollinger Band.|
//| Returns 1 for bullish bounce, -1 for bearish bounce, 0 for no signal. |
//+------------------------------------------------------------------+
int IsDojiBBBounce(string symbol, ENUM_TIMEFRAMES timeframe, int bbPeriod, double bbDeviation, ENUM_MA_METHOD bbMethod, ENUM_APPLIED_PRICE appliedPrice, double maxDojiBodyRatio)
{
    MqlRates rates[2]; // rates[0] is 'shift 0', rates[1] is 'shift 1'
    if (CopyRates(symbol, timeframe, 0, 2, rates) != 2)
    {
        Print("ERROR: Failed to copy rates for Doji BB Bounce detection.");
        return 0;
    }

    // Check if the previous bar is a Doji
    if (!IsDoji(symbol, timeframe, 1, maxDojiBodyRatio))
    {
        return 0;
    }
    
    // Get Bollinger Band values for the previous bar (where the Doji is)
    double upperBand = GetBollingerBandValue(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, 1, 1);
    double lowerBand = GetBollingerBandValue(symbol, timeframe, bbPeriod, bbDeviation, bbMethod, appliedPrice, 1, 2);

    double dojiHigh = rates[1].high;
    double dojiLow = rates[1].low;
    
    // Check for a bullish bounce (Doji low pierced LB)
    if (dojiLow < lowerBand)
    {
        // Check for confirmation on the current bar
        if (rates[0].close > rates[0].open && rates[0].close > dojiHigh)
        {
            return 1; // Bullish bounce confirmed
        }
    }
    
    // Check for a bearish bounce (Doji high pierced UB)
    if (dojiHigh > upperBand)
    {
        // Check for confirmation on the current bar
        if (rates[0].close < rates[0].open && rates[0].close < dojiLow)
        {
            return -1; // Bearish bounce confirmed
        }
    }
    
    return 0;
}


//+------------------------------------------------------------------+
//| Helper function to check for EMA crossover signal for Trend Following. |
//| Returns 1 for BUY, -1 for SELL, 0 for no signal.                 |
//+------------------------------------------------------------------+
int CheckTrendFollowingSignal(string symbol, ENUM_TIMEFRAMES timeframe, int fastPeriod, int slowPeriod, ENUM_MA_METHOD maMethod, ENUM_APPLIED_PRICE appliedPrice)
{
    // Get MA values for the previous two closed bars
    double fastMA_current = GetMAValue(symbol, timeframe, fastPeriod, maMethod, appliedPrice, 1);
    double slowMA_current = GetMAValue(symbol, timeframe, slowPeriod, maMethod, appliedPrice, 1);
    double fastMA_prev = GetMAValue(symbol, timeframe, fastPeriod, maMethod, appliedPrice, 2);
    double slowMA_prev = GetMAValue(symbol, timeframe, slowPeriod, maMethod, appliedPrice, 2);

    if (fastMA_current == 0.0 || slowMA_current == 0.0 || fastMA_prev == 0.0 || slowMA_prev == 0.0)
    {
        return 0; // Error in getting MA values
    }

    // Bullish Crossover
    if (fastMA_current > slowMA_current && fastMA_prev <= slowMA_prev)
    {
        return 1; // BUY signal
    }
    // Bearish Crossover
    else if (fastMA_current < slowMA_current && fastMA_prev >= slowMA_prev)
    {
        return -1; // SELL signal
    }

    return 0; // No crossover
}

//+------------------------------------------------------------------+
//| Helper function to get previous swing high or low.               |
//| direction: 1 for high, -1 for low.                               |
//| Returns the price of the swing point, or 0.0 if not found.       |
//+------------------------------------------------------------------+
double GetPreviousSwingLowHigh(string symbol, ENUM_TIMEFRAMES timeframe, int lookbackBars, int direction)
{
    MqlRates rates[];
    if (CopyRates(symbol, timeframe, 0, lookbackBars, rates) != lookbackBars)
    {
        return 0.0;
    }

    double swingPrice = 0.0;
    if (direction == 1) // Looking for swing high
    {
        double highestHigh = 0.0;
        for (int i = 0; i < lookbackBars; i++)
        {
            if (rates[i].high > highestHigh)
            {
                highestHigh = rates[i].high;
            }
        }
        swingPrice = highestHigh;
    }
    else // Looking for swing low
    {
        double lowestLow = DBL_MAX;
        for (int i = 0; i < lookbackBars; i++)
        {
            if (rates[i].low < lowestLow)
            {
                lowestLow = rates[i].low;
            }
        }
        swingPrice = lowestLow;
    }
    return swingPrice;
}


//+------------------------------------------------------------------+
//| Helper function to calculate lot size based on risk percentage   |
//| and a smart Stop Loss price.                                     |
//+------------------------------------------------------------------+
// The function signature was changed to accept stop loss in points
// and the function call in OnTick was updated to match.
double CalculateLotSize(double riskPercent, int slPoints, double maxLot)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    if (accountBalance <= 0)
    {
        Print("ERROR: Account balance is zero or negative.");
        return 0.0;
    }

    double riskAmount = accountBalance * (riskPercent / 100.0); // Monetary amount to risk
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE); // Value of a tick in deposit currency
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);   // Minimum price change
    
    // Use the passed-in slPoints
    if (slPoints <= 0) 
    {
        Print("ERROR: Calculated SL points is zero or negative. Cannot calculate lot size.");
        return 0.0;
    }

    double lossPerLot = slPoints * (point / tickSize) * tickValue;

    if (lossPerLot <= 0)
    {
        Print("ERROR: Calculated loss per lot is zero or negative. Check symbol properties or SL pips.");
        return 0.0;
    }

    double lotSize = riskAmount / lossPerLot;

    // Apply maximum lot size constraint
    if (lotSize > maxLot)
    {
        Print("Calculated lot size (", NormalizeDouble(lotSize, 2), ") exceeds MaxLotSize (", maxLot, "). Capping to ", maxLot, " lots.");
        lotSize = maxLot;
    }

    // Normalize lot size to symbol's volume step and check min/max
    double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double brokerMaxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX); // Broker's actual max volume
    double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    // Ensure lot size is a multiple of volume step
    lotSize = MathRound(lotSize / volumeStep) * volumeStep;
    lotSize = NormalizeDouble(lotSize, 2); // Normalize to 2 decimal places for common lot sizes

    if (lotSize < minVolume)
    {
        Print("Calculated lot size (", lotSize, ") is less than minimum volume (", minVolume, "). Setting to min volume.");
        lotSize = minVolume;
    }
    // Also ensure it doesn't exceed the broker's max allowed volume
    if (lotSize > brokerMaxVolume)
    {
        Print("Calculated lot size (", lotSize, ") is greater than BROKER'S maximum volume (", brokerMaxVolume, "). Setting to broker's max volume.");
        lotSize = brokerMaxVolume;
    }
    
    return lotSize;
}
