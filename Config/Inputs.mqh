//+------------------------------------------------------------------+
//|                                                     Inputs.mqh   |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Centralized, fully-documented, user-configurable input        |
//|   parameters. NO hardcoded trading values exist anywhere else   |
//|   in the project — every module reads its configuration from    |
//|   here. This is the ONLY file the end user needs to touch to    |
//|   tune the EA's behavior.                                       |
//|                                                                  |
//| NOTE:                                                            |
//|   Enums used across multiple modules (entry mode, recovery      |
//|   mode, trade state) are also declared here so every module     |
//|   that includes Inputs.mqh shares the exact same definitions.   |
//+------------------------------------------------------------------+
#ifndef __GHR_INPUTS_MQH__
#define __GHR_INPUTS_MQH__

//====================================================================
// SHARED ENUMERATIONS
//====================================================================

// Entry signal generation mode
enum ENUM_ENTRY_MODE
{
   ENTRY_WAIT_CROSS,        // Wait for EMA Fast/Slow Cross
   ENTRY_CURRENT_TREND,     // Enter immediately based on current trend bias
   ENTRY_SCALP_CANDLE       // Enter every new closed candle, direction = that candle's own color
};

// Recovery lot sizing mode
enum ENUM_RECOVERY_MODE
{
   RECOVERY_FIXED_LOT,      // Fixed Lot for every recovery layer
   RECOVERY_MULTIPLIER,     // Lot = previous layer lot * multiplier
   RECOVERY_CUSTOM_SEQUENCE // User-defined explicit lot sequence
};

// Direction of a position/signal
enum ENUM_TRADE_DIRECTION
{
   DIRECTION_NONE = 0,
   DIRECTION_BUY  = 1,
   DIRECTION_SELL = -1
};

// High level state machine for the whole EA (used by Dashboard/Logger)
enum ENUM_TRADE_STATE
{
   STATE_IDLE,               // No positions open, searching for signal
   STATE_INITIAL_OPEN,       // Only the initial (layer 0) position is open
   STATE_RECOVERY_ACTIVE,    // One or more recovery layers are open
   STATE_EMERGENCY_CLOSED,   // Risk engine forced a full close this bar
   STATE_COOLDOWN,           // Waiting out cooldown after a completed cycle
   STATE_PAUSED_RISK,        // Paused due to daily loss / consecutive loss limit
   STATE_TARGET_REACHED      // Profit target reached - EA permanently halted (until restart)
};

//====================================================================
// GENERAL
//====================================================================
input group "==== GENERAL ===="
input ulong   InpMagicNumber          = 552023;                   // Magic Number (unique EA identifier)
input string  InpTradeComment         = "GoldHedgeRecovery";      // Order Comment Prefix
input bool    InpAllowNewCycles       = true;                     // Allow EA To Start New Cycles Automatically

//====================================================================
// ENTRY SETTINGS
//====================================================================
input group "==== ENTRY SETTINGS ===="
input ENUM_ENTRY_MODE InpEntryMode    = ENTRY_WAIT_CROSS;         // Entry Mode
input int     InpEmaFastPeriod        = 20;                       // EMA Fast Period (Wait Cross mode)
input int     InpEmaSlowPeriod        = 50;                       // EMA Slow Period (Wait Cross mode)
input int     InpTrendEmaPeriod       = 200;                      // EMA Period for Trend Bias (Current Trend mode)
input double  InpBaseLot              = 0.01;                     // Base Lot Size (Layer 0 / initial entry)

//====================================================================
// OPTIONAL FILTERS
//====================================================================
input group "==== FILTER: EMA200 ===="
input bool    InpUseEma200Filter      = true;                     // Enable EMA200 Filter
input int     InpEma200Period         = 200;                      // EMA200 Period

input group "==== FILTER: SMA200 ===="
input bool    InpUseSma200Filter      = false;                    // Enable SMA200 Filter
input int     InpSma200Period         = 200;                      // SMA200 Period

input group "==== FILTER: ATR ===="
input bool    InpUseAtrFilter         = true;                     // Enable ATR Volatility Filter
input int     InpAtrPeriod            = 14;                       // ATR Period
input double  InpAtrMinPoints         = 20;                       // Minimum ATR (points) required to allow entry
input double  InpAtrMaxPoints         = 800;                      // Maximum ATR (points) allowed (news-spike guard)

input group "==== FILTER: MULTI TIMEFRAME ===="
input bool             InpUseMtfFilter   = false;                 // Enable Multi-Timeframe Trend Confirmation
input ENUM_TIMEFRAMES  InpMtfTimeframe   = PERIOD_H1;              // Higher Timeframe used to confirm trend
input int              InpMtfEmaPeriod   = 200;                    // EMA Period on the higher timeframe

input group "==== FILTER: SPREAD ===="
input bool    InpUseSpreadFilter      = true;                     // Enable Spread Filter
input double  InpMaxSpreadPoints      = 350;                      // Maximum Allowed Spread (points)

input group "==== FILTER: SESSION ===="
input bool    InpUseSessionFilter     = false;                    // Enable Session Filter
input int     InpSessionStartHour     = 8;                        // Session Start Hour (broker time, 0-23)
input int     InpSessionEndHour       = 21;                       // Session End Hour (broker time, 0-23)

input group "==== FILTER: CANDLE ===="
input bool    InpUseCandleFilter      = false;                    // Enable Minimum Candle Body Filter
input double  InpMinCandleBodyPoints  = 30;                       // Minimum Candle Body Size (points)

//====================================================================
// RECOVERY SETTINGS
//====================================================================
input group "==== RECOVERY SETTINGS ===="
input ENUM_RECOVERY_MODE InpRecoveryMode     = RECOVERY_MULTIPLIER;             // Recovery Lot Sizing Mode
input double              InpRecoveryMultiplier = 2.0;                          // Lot Multiplier (Multiplier mode)
input string              InpCustomLotSequence  = "0.01,0.02,0.04,0.08,0.16";   // Custom Lot Sequence (Custom mode, CSV)
input double              InpRecoveryTriggerUSD = 0.30;                        // Floating Loss (USD) That Triggers Next Layer
input int                 InpMaxLayers          = 5;                           // Maximum Layers (including Layer 0)
input int                 InpRecoveryCooldownSec= 30;                          // Cooldown (seconds) Between Recovery Layers

//====================================================================
// EXIT SETTINGS
//====================================================================
input group "==== EXIT: INDIVIDUAL TP ===="
input bool    InpUseIndividualTP      = true;                     // Enable Individual TP Per Position
input double  InpIndividualTPUSD      = 0.20;                     // Individual TP Target (USD profit per position)

input group "==== EXIT: BASKET TP ===="
input bool    InpUseBasketTP          = true;                     // Enable Basket TP (close all layers together)
input double  InpBasketTPUSD          = 0.50;                     // Basket TP Target (USD total profit for the cycle)

input group "==== EXIT: BREAK EVEN ===="
input bool    InpUseBreakEven         = true;                     // Enable Break Even Management
input double  InpBreakEvenTriggerUSD  = 0.15;                     // Profit (USD) That Triggers Break Even
input double  InpBreakEvenLockPoints  = 20;                       // Points Locked Above Entry When BE Triggers

input group "==== EXIT: TRAILING STOP ===="
input bool    InpUseTrailingStop      = false;                    // Enable Trailing Stop (Layer 0, basket in profit)
input double  InpTrailingStartPoints  = 150;                      // Points In Profit Before Trailing Starts
input double  InpTrailingStepPoints   = 50;                       // Trailing Step (points)

input group "==== EXIT: EMERGENCY CLOSE ===="
input bool    InpUseEmergencyClose    = true;                     // Enable Emergency Close (Risk Engine triggered)

//====================================================================
// RISK MANAGEMENT
//====================================================================
input group "==== RISK MANAGEMENT ===="
input bool    InpUseMaxDailyLoss      = true;                     // Enable Max Daily Loss Limit
input double  InpMaxDailyLossUSD      = 3.0;                      // Max Daily Loss (USD)

input bool    InpUseMaxFloatingLoss   = true;                     // Enable Max Floating Loss Limit
input double  InpMaxFloatingLossUSD   = 4.0;                      // Max Floating Loss (USD) Before Emergency Close

input bool    InpUseMaxDrawdown       = true;                     // Enable Max Drawdown Limit
input double  InpMaxDrawdownPercent   = 40.0;                     // Max Drawdown (% of starting balance)

input bool    InpUseMaxTotalLot       = true;                     // Enable Max Total Lot Limit
input double  InpMaxTotalLot          = 0.50;                     // Max Total Lot (sum of all open layers)

input bool    InpUseMaxConsecLosses   = true;                     // Enable Max Consecutive Losing Cycles Limit
input int     InpMaxConsecutiveLosses = 4;                        // Max Consecutive Losing Cycles Before Pause

input bool    InpUseFreeMarginGuard   = true;                     // Enable Free Margin Protection
input double  InpMinFreeMarginUSD     = 2.0;                      // Minimum Free Margin (USD) Required For New Layer

input bool    InpUseMarginLevelGuard  = true;                     // Enable Margin Level Protection
input double  InpMinMarginLevelPercent= 150.0;                    // Minimum Margin Level (%) Required For New Layer

input group "==== RISK MANAGEMENT: PROFIT TARGET STOP ===="
input bool    InpUseProfitTarget      = false;                    // Enable Profit Target Stop (halts EA when reached)
input double  InpProfitTargetPercent  = 900.0;                    // Target Gain (%) From Starting Balance. Formula: Target Equity = StartBalance * (1 + Percent/100). Example: StartBalance=3000, Percent=900 -> Target=30000 (10x). Percent=1000 -> Target=33000 (11x).

//====================================================================
// NOTIFICATIONS
//====================================================================
input group "==== NOTIFICATIONS ===="
input bool    InpEnablePushNotifications = true;   // Send Push Notifications To MT5 Mobile App
input bool    InpNotifyProfitTarget      = true;   // Notify: Profit Target Reached
input bool    InpNotifyEmergencyClose    = true;   // Notify: Emergency Close Triggered
input bool    InpNotifyRecoveryLayer     = true;   // Notify: New Recovery Layer Opened
input bool    InpNotifyBasketTP          = true;   // Notify: Basket TP Closed (cycle completed)

//====================================================================
// DASHBOARD
//====================================================================
input group "==== DASHBOARD ===="
input bool    InpShowDashboard        = true;                     // Show On-Chart Dashboard
input int     InpDashboardX           = 10;                       // Dashboard X Offset (pixels)
input int     InpDashboardY           = 20;                       // Dashboard Y Offset (pixels)
input color   InpDashboardColor       = clrWhite;                 // Dashboard Text Color
input color   InpDashboardBgColor     = clrBlack;                 // Dashboard Background Color
input int     InpDashboardFontSize    = 9;                        // Dashboard Font Size

//====================================================================
// LOGGING
//====================================================================
input group "==== LOGGING ===="
input bool    InpEnableLogging        = true;                     // Enable Logging (Experts tab)
input bool    InpEnableCsvLogging     = true;                     // Enable CSV File Logging
input string  InpCsvFileName          = "GoldHedgeRecovery_Log.csv"; // CSV Log File Name (stored in MQL5/Files)
input bool    InpVerboseLogging       = false;                    // Verbose Logging (extra debug detail)

//====================================================================
// EXECUTION
//====================================================================
input group "==== EXECUTION ===="
input int     InpSlippagePoints       = 30;                       // Max Slippage (points)
input int     InpOrderRetryCount      = 3;                        // Retry Count On Recoverable Trade Errors
input int     InpOrderRetryDelayMs    = 200;                      // Delay Between Retries (milliseconds)

#endif // __GHR_INPUTS_MQH__
