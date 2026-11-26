-- =====================================================
-- 02_oversold_opportunities.sql
-- =====================================================
-- PURPOSE: Find oversold conditions with bullish confirmation for reversals
--
-- PARAMETERS:
-- @start_hours_ago: Beginning of time window (default: 0 = most recent)
-- @end_hours_ago: End of time window (default: 4 = 4 hours back)
-- @min_rsi: Minimum RSI value for oversold zone (default: 25)
-- @max_rsi: Maximum RSI value for oversold zone (default: 40)
-- @require_buy_signal: Require combined BUY/STRONG_BUY signal (default: 1)
-- @min_macd_histogram: Minimum MACD histogram value (default: 0 = positive only)
-- @min_momentum: Minimum 1h price change % (default: 0, disabled)
-- @min_volume_ratio: Minimum volume vs VWMA_20 (default: 0, disabled)
-- @max_hours_ago: Maximum age of signal in hours (default: 4)
-- @symbol_filter: Specific symbol filter (default: NULL = all symbols)
--
-- OVERSOLD ZONE MEANINGS:
-- RSI 20-25: Extremely oversold (high reversal probability)
-- RSI 25-30: Very oversold (good reversal zone)
-- RSI 30-35: Moderately oversold (standard reversal zone)
-- RSI 35-40: Near oversold (early reversal warning)
--
-- BULLISH CONFIRMATION SIGNALS:
-- - MACD histogram positive (momentum turning bullish)
-- - Price momentum positive (price starting to rise)
-- - Volume increasing (institutional interest)
-- - Combined signal from main analyzer
--
-- USE CASE: Finding potential reversal entries when RSI is low
-- SORTED BY: Lowest RSI first, then best momentum
-- =====================================================

USE db_Trading;

DECLARE @start_hours_ago INT = 0;              -- 0 = most recent candle
DECLARE @end_hours_ago INT = 4;                -- 4 = last 4 hours (default)
DECLARE @min_rsi DECIMAL(5,2) = 25;            -- Minimum RSI (oversold lower bound)
DECLARE @max_rsi DECIMAL(5,2) = 55;            -- Maximum RSI (oversold upper bound)
DECLARE @require_buy_signal INT = 1;           -- 1 = require BUY/STRONG_BUY, 0 = show all
DECLARE @min_macd_histogram DECIMAL(10,4) = 0.05; -- Min MACD histogram (0 = positive only, negative allowed)
DECLARE @min_momentum DECIMAL(5,2) = 0.5;        -- Min 1h price change % (0 = disabled)
DECLARE @min_volume_ratio DECIMAL(5,2) = 0;    -- Min volume / VWMA_20 (0 = disabled)
DECLARE @max_hours_ago INT = 180;                -- Max age of signal in hours
DECLARE @symbol_filter NVARCHAR(50) = NULL;    -- NULL = all symbols, or 'BTCIRT'

-- =====================================================
-- CALCULATE TIME BOUNDARIES
-- =====================================================

DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 60 * 60);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 60 * 60);
DECLARE @max_age_timestamp BIGINT = @current_time - (@max_hours_ago * 60 * 60);


SELECT 
    -- =====================================================
    -- TIME INFORMATION
    -- =====================================================
    c.timestamp,
    DATEADD(MINUTE, 210, DATEADD(SECOND, c.timestamp, '1970-01-01')) as datetime_tehran,
    CAST((@current_time - c.timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
    c.symbol,
    
    -- =====================================================
    -- PRICE DATA
    -- =====================================================

    --ROUND(c.[close], 2) as current_price,
    --ROUND(c.[open], 2) as open_price,
    --ROUND(c.high, 2) as high_price,
    --ROUND(c.low, 2) as low_price,
    
    -- =====================================================
    -- RSI ANALYSIS (Oversold focus)
    -- =====================================================
    ROUND(c.RSI, 1) as rsi_value,
    CASE 
        WHEN c.RSI < 25 THEN 'EXTREMELY_OVERSOLD'
        WHEN c.RSI < 30 THEN 'VERY_OVERSOLD'
        WHEN c.RSI < 35 THEN 'MODERATELY_OVERSOLD'
        WHEN c.RSI < 40 THEN 'NEAR_OVERSOLD'
        ELSE 'NEUTRAL'
    END as rsi_zone,
    -- Distance from oversold threshold (how deep)
    --CASE 
    --    WHEN c.RSI < 40 THEN ROUND(40 - c.RSI, 1)
    --    ELSE 0
    --END as rsi_oversold_depth,
    
    -- =====================================================
    -- MACD ANALYSIS (Momentum confirmation)
    -- =====================================================
    ROUND(c.MACD_12_26_9, 4) as macd_line,
    ROUND(c.MACDs_12_26_9, 4) as macd_signal_line,
    ROUND(c.MACDh_12_26_9, 4) as macd_histogram,
    CASE 
        WHEN c.MACDh_12_26_9 > 0.1 THEN 'STRONGLY_BULLISH'
        WHEN c.MACDh_12_26_9 > 0 THEN 'BULLISH'
        WHEN c.MACDh_12_26_9 > -0.1 THEN 'NEUTRAL'
        WHEN c.MACDh_12_26_9 > -0.5 THEN 'BEARISH'
        ELSE 'STRONGLY_BEARISH'
    END as macd_status,
    
    -- MACD crossover detection (using previous row from CTE)
    -- Note: This requires a LAG, will add in CTE section below
    
    -- =====================================================
    -- MOMENTUM ANALYSIS
    -- =====================================================
    ROUND(c.price_change_1, 2) as momentum_1h_pct,
    ROUND(c.price_change_2, 2) as momentum_2h_pct,
    ROUND(c.price_change_3, 2) as momentum_3h_pct,
    ROUND(c.momentum_acceleration, 2) as momentum_acceleration,
    
    -- Momentum classification
    CASE 
        WHEN c.price_change_1 > 1.5 THEN 'STRONG_MOMENTUM'
        WHEN c.price_change_1 > 0.5 THEN 'BUILDING_MOMENTUM'
        WHEN c.price_change_1 > 0 THEN 'WEAK_MOMENTUM'
        WHEN c.price_change_1 > -1 THEN 'SLIGHTLY_NEGATIVE'
        ELSE 'STRONGLY_NEGATIVE'
    END as momentum_status,
    
    -- =====================================================
    -- VOLUME ANALYSIS (Confirmation)
    -- =====================================================
    ROUND(c.volume, 0) as volume,
    ROUND(c.VWMA_20, 0) as avg_volume_20h,
    CASE 
        WHEN c.VWMA_20 > 0 THEN ROUND(c.volume / c.VWMA_20, 2)
        ELSE 0
    END as volume_ratio,
    CASE 
        WHEN c.VWMA_20 > 0 AND c.volume / c.VWMA_20 >= 1.5 THEN 'HIGH_VOLUME'
        WHEN c.VWMA_20 > 0 AND c.volume / c.VWMA_20 >= 1.2 THEN 'ABOVE_AVERAGE_VOLUME'
        WHEN c.VWMA_20 > 0 AND c.volume / c.VWMA_20 >= 0.8 THEN 'NORMAL_VOLUME'
        ELSE 'LOW_VOLUME'
    END as volume_status,
    
    -- =====================================================
    -- COMBINED SIGNAL (from analyzer)
    -- =====================================================
    a.combined_signal,
    a.buy_probability,
    a.combined_score,
    
    -- =====================================================
    -- INDIVIDUAL INDICATOR SIGNALS (for transparency)
    -- =====================================================
    a.rsi_signal,
    a.rsi_recommendation,
    a.macd_signal as macd_analysis_signal,
    a.macd_recommendation,
    a.bb_signal,
    a.bb_recommendation,
    
    -- =====================================================
    -- TREND STRENGTH
    -- =====================================================
    ROUND(c.ADX_14, 1) as adx_trend_strength,
    CASE 
        WHEN c.ADX_14 > 50 THEN 'EXTREMELY_STRONG_TREND'
        WHEN c.ADX_14 > 35 THEN 'STRONG_TREND'
        WHEN c.ADX_14 > 25 THEN 'MODERATE_TREND'
        WHEN c.ADX_14 > 20 THEN 'WEAK_TREND'
        ELSE 'NO_TREND_RANGING'
    END as trend_strength,
    
    -- =====================================================
    -- OVERSOLD REVERSAL SCORE (0-100)
    -- =====================================================
    CAST(
        (CASE WHEN c.RSI < 30 THEN 40 
              WHEN c.RSI < 35 THEN 30 
              WHEN c.RSI < 40 THEN 20 
              ELSE 0 END) +                          -- RSI component (oversold weight)
        (CASE WHEN c.MACDh_12_26_9 > 0 THEN 25 ELSE 0 END) +   -- MACD bullish weight
        (CASE WHEN c.price_change_1 > 0.5 THEN 20 
              WHEN c.price_change_1 > 0 THEN 10 
              ELSE 0 END) +                          -- Momentum weight
        (CASE WHEN c.volume > c.VWMA_20 * 1.2 THEN 15 
              WHEN c.volume > c.VWMA_20 THEN 8 
              ELSE 0 END)                            -- Volume confirmation weight
    AS INT) as reversal_score,
    
    -- =====================================================
    -- FINAL RECOMMENDATION
    -- =====================================================
    CASE 
        WHEN c.RSI < 30 
             AND c.MACDh_12_26_9 > 0 
             AND c.price_change_1 > 0 
            THEN 'STRONG_BUY_OPPORTUNITY'
        WHEN c.RSI < 35 
             AND c.MACDh_12_26_9 > 0 
            THEN 'BUY_OPPORTUNITY'
        WHEN c.RSI < 40 
             AND c.price_change_1 > 0.5 
            THEN 'WATCH_OPPORTUNITY'
        ELSE 'NO_OPPORTUNITY'
    END as opportunity_signal

FROM tab_calculated_60 c
INNER JOIN tab_analysis_results a 
    ON c.symbol = a.symbol 
    AND c.timestamp = a.timestamp

WHERE 1=1
    -- Time range filter
    AND c.timestamp BETWEEN @end_timestamp AND @start_timestamp
    -- Signal age filter (maximum hours ago)
    AND c.timestamp >= @max_age_timestamp
    -- RSI oversold zone filter
    AND c.RSI BETWEEN @min_rsi AND @max_rsi
    -- MACD histogram filter (bullish confirmation)
    AND c.MACDh_12_26_9 >= @min_macd_histogram
    -- Combined signal filter (optional)
    AND (@require_buy_signal = 0 OR a.combined_signal IN ('BUY', 'STRONG_BUY'))
    -- Momentum filter
    AND c.price_change_1 >= @min_momentum
    -- Volume filter
    AND (@min_volume_ratio <= 0 OR (c.VWMA_20 > 0 AND c.volume / c.VWMA_20 >= @min_volume_ratio))
    -- Symbol filter
    AND (@symbol_filter IS NULL OR c.symbol = @symbol_filter)

ORDER BY 
    -- Prioritize: Most oversold first, then best momentum
    c.RSI ASC,
    reversal_score DESC,
    c.price_change_1 DESC,
    c.timestamp DESC;