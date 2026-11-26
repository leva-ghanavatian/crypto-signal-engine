-- =====================================================
-- 11_master_morning_scan.sql
-- =====================================================
-- PURPOSE: Single comprehensive scan combining all indicators for 24-48 hour trades
-- 
-- This query combines:
--   - Momentum detection (03)
--   - Bollinger Squeeze/Breakout (09)
--   - MACD crossovers (05)
--   - Oversold reversals (02)
--   - Divergence detection (10)
--   - Combined buy signals (01)
--
-- OUTPUT: Prioritized list of trading opportunities with clear action recommendations
--
-- USE CASE: Morning scan (9-10 AM) to identify best trades for the day
-- SORTED BY: Trade priority (highest first)
-- =====================================================

USE db_Trading;

-- =====================================================
-- CONFIGURATION PARAMETERS (Adjust these based on your risk tolerance)
-- =====================================================

DECLARE @lookback_hours INT = 6;              -- Look back 6 hours for signals
DECLARE @min_momentum_pct DECIMAL(5,2) = 0.5; -- Minimum 1h price change %
DECLARE @min_volume_ratio DECIMAL(5,2) = 1.0; -- Minimum volume vs average
DECLARE @max_rsi_for_entry INT = 65;          -- Don't buy overbought
DECLARE @min_buy_probability INT = 60;        -- Minimum buy probability score

-- =====================================================
-- TIME CALCULATIONS
-- =====================================================

DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @lookback_timestamp BIGINT = @current_time - (@lookback_hours * 60 * 60);

-- =====================================================
-- MAIN SCAN QUERY
-- =====================================================

WITH 
-- Get current candle data
current_data AS (
    SELECT 
        c1.symbol,
        c1.timestamp,
        CAST((@current_time - c1.timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        DATEADD(MINUTE, 210, DATEADD(SECOND, c1.timestamp, '1970-01-01')) as datetime_tehran,
        
        -- Price data
        ROUND(c1.[close], 2) as price,
        ROUND(c1.price_change_1, 2) as momentum_1h,
        ROUND(c1.price_change_2, 2) as momentum_2h,
        ROUND(c1.price_change_3, 2) as momentum_3h,
        ROUND(c1.momentum_acceleration, 2) as acceleration,
        
        -- RSI
        ROUND(c1.RSI, 1) as rsi,
        
        -- MACD
        ROUND(c1.MACD_12_26_9, 4) as macd_line,
        ROUND(c1.MACDs_12_26_9, 4) as macd_signal,
        ROUND(c1.MACDh_12_26_9, 4) as macd_histogram,
        
        -- Volume
        c1.volume,
        ROUND(c1.VWMA_20, 0) as avg_volume,
        CASE WHEN c1.VWMA_20 > 0 THEN ROUND(c1.volume / c1.VWMA_20, 2) ELSE 0 END as volume_ratio,
        
        -- Bollinger Bands
        ROUND(c1.[BBU_20_2.0_2.0], 2) as bb_upper,
        ROUND(c1.[BBM_20_2.0_2.0], 2) as bb_middle,
        ROUND(c1.[BBL_20_2.0_2.0], 2) as bb_lower,
        
        -- Bandwidth
        CASE 
            WHEN c1.[BBM_20_2.0_2.0] > 0 
            THEN ROUND((c1.[BBU_20_2.0_2.0] - c1.[BBL_20_2.0_2.0]) / c1.[BBM_20_2.0_2.0] * 100, 2)
            ELSE 0
        END as bb_bandwidth,
        
        -- Position in bands
        CASE 
            WHEN (c1.[BBU_20_2.0_2.0] - c1.[BBL_20_2.0_2.0]) > 0
            THEN ROUND((c1.[close] - c1.[BBL_20_2.0_2.0]) / (c1.[BBU_20_2.0_2.0] - c1.[BBL_20_2.0_2.0]) * 100, 1)
            ELSE 50
        END as bb_position,
        
        -- Previous values for trends
        LAG(ROUND((c1.[BBU_20_2.0_2.0] - c1.[BBL_20_2.0_2.0]) / c1.[BBM_20_2.0_2.0] * 100, 2)) 
            OVER (PARTITION BY c1.symbol ORDER BY c1.timestamp) as prev_bandwidth,
        LAG(ROUND(c1.[BBM_20_2.0_2.0], 2)) 
            OVER (PARTITION BY c1.symbol ORDER BY c1.timestamp) as prev_middle,
        LAG(c1.MACDh_12_26_9) OVER (PARTITION BY c1.symbol ORDER BY c1.timestamp) as prev_macd_hist,
        
        -- ADX
        ROUND(c1.ADX_14, 1) as adx,
        
        -- OBV
        ROUND(c1.OBV, 0) as obv
        
    FROM tab_calculated_60 c1
    WHERE c1.timestamp >= @lookback_timestamp
),

-- Previous data for crossover detection
prev_data AS (
    SELECT 
        symbol,
        LAG(RSI) OVER (PARTITION BY symbol ORDER BY timestamp) as prev_rsi,
        LAG(MACDh_12_26_9) OVER (PARTITION BY symbol ORDER BY timestamp) as prev_macd_hist,
        LAG(price_change_1) OVER (PARTITION BY symbol ORDER BY timestamp) as prev_momentum
    FROM tab_calculated_60
    WHERE timestamp >= @lookback_timestamp
),

-- Analysis results
analysis_results AS (
    SELECT 
        a.symbol,
        a.combined_signal,
        a.buy_probability,
        a.combined_score,
        a.rsi_signal,
        a.macd_signal as macd_analysis_signal,
        a.bb_signal
    FROM tab_analysis_results a
    WHERE a.timestamp >= @lookback_timestamp
)

-- =====================================================
-- FINAL MASTER SCAN
-- =====================================================
SELECT TOP 30
    -- Basic info
    c.symbol,
    c.datetime_tehran as signal_time,
    c.hours_ago,
    c.price,
    
    -- =====================================================
    -- MOMENTUM SCORE (0-25)
    -- =====================================================
    CAST(
        (CASE WHEN c.momentum_1h > 1.5 THEN 25
              WHEN c.momentum_1h > 1.0 THEN 20
              WHEN c.momentum_1h > 0.5 THEN 15
              WHEN c.momentum_1h > 0 THEN 10
              ELSE 0 END) +
        (CASE WHEN c.acceleration > 0.2 THEN 5 ELSE 0 END)
    AS INT) as momentum_score,
    
    -- Momentum details
    ROUND(c.momentum_1h, 2) as momentum_1h_pct,
    ROUND(c.acceleration, 2) as acceleration,
    CASE 
        WHEN c.momentum_1h > 1.5 AND c.acceleration > 0 THEN 'STRONG_ACCELERATING'
        WHEN c.momentum_1h > 1.0 THEN 'STRONG'
        WHEN c.momentum_1h > 0.5 THEN 'MODERATE'
        WHEN c.momentum_1h > 0 THEN 'WEAK'
        ELSE 'NEGATIVE'
    END as momentum_status,
    
    -- =====================================================
    -- BOLLINGER SCORE (0-25)
    -- =====================================================
    CAST(
        (CASE WHEN c.bb_bandwidth < 8 THEN 15
              WHEN c.bb_bandwidth < 12 THEN 10
              ELSE 5 END) +
        (CASE WHEN c.bb_position > 55 THEN 10
              WHEN c.bb_position > 50 THEN 5
              ELSE 0 END) +
        (CASE WHEN c.bb_bandwidth > c.prev_bandwidth THEN 5 ELSE 0 END)
    AS INT) as bollinger_score,
    
    -- Bollinger details
    c.bb_bandwidth as bandwidth_pct,
    c.bb_position as position_pct,
    CASE 
        WHEN c.bb_bandwidth < 5 THEN 'EXTREME_SQUEEZE'
        WHEN c.bb_bandwidth < 8 THEN 'TIGHT_SQUEEZE'
        WHEN c.bb_bandwidth < 12 THEN 'NORMAL'
        ELSE 'EXPANDED'
    END as squeeze_status,
    CASE WHEN c.bb_middle > c.prev_middle THEN 'RISING' ELSE 'FLAT_OR_FALLING' END as middle_band_trend,
    
    -- =====================================================
    -- MACD SCORE (0-25)
    -- =====================================================
    CAST(
        (CASE WHEN c.macd_histogram > 0 AND c.prev_macd_hist <= 0 THEN 20
              WHEN c.macd_histogram > 0 THEN 15
              ELSE 0 END) +
        (CASE WHEN c.macd_histogram > c.prev_macd_hist THEN 5 ELSE 0 END)
    AS INT) as macd_score,
    
    -- MACD details
    ROUND(c.macd_histogram, 4) as macd_histogram,
    CASE 
        WHEN c.macd_histogram > 0 AND c.prev_macd_hist <= 0 THEN 'BULLISH_CROSSOVER'
        WHEN c.macd_histogram > 0 THEN 'BULLISH'
        ELSE 'BEARISH'
    END as macd_status,
    
    -- =====================================================
    -- VOLUME & TREND SCORE (0-25)
    -- =====================================================
    CAST(
        (CASE WHEN c.volume_ratio >= 1.5 THEN 15
              WHEN c.volume_ratio >= 1.2 THEN 10
              WHEN c.volume_ratio >= 1.0 THEN 5
              ELSE 0 END) +
        (CASE WHEN c.adx >= 25 THEN 10
              WHEN c.adx >= 20 THEN 5
              ELSE 0 END)
    AS INT) as volume_trend_score,
    
    -- Volume details
    c.volume_ratio,
    c.adx as adx_value,
    CASE 
        WHEN c.volume_ratio >= 1.5 THEN 'HIGH_VOLUME'
        WHEN c.volume_ratio >= 1.2 THEN 'ABOVE_AVERAGE'
        ELSE 'NORMAL_VOLUME'
    END as volume_status,
    
    -- =====================================================
    -- RSI STATUS (Filter)
    -- =====================================================
    c.rsi,
    CASE 
        WHEN c.rsi < 30 THEN 'OVERSOLD'
        WHEN c.rsi BETWEEN 30 AND 40 THEN 'NEAR_OVERSOLD'
        WHEN c.rsi BETWEEN 40 AND 60 THEN 'NEUTRAL'
        WHEN c.rsi BETWEEN 60 AND 70 THEN 'NEAR_OVERBOUGHT'
        ELSE 'OVERBOUGHT'
    END as rsi_zone,
    
    -- =====================================================
    -- COMBINED SCORE (0-100)
    -- =====================================================
    CAST(
        (CASE WHEN c.momentum_1h > 1.5 THEN 25
              WHEN c.momentum_1h > 1.0 THEN 20
              WHEN c.momentum_1h > 0.5 THEN 15
              WHEN c.momentum_1h > 0 THEN 10
              ELSE 0 END) +
        (CASE WHEN c.bb_bandwidth < 8 THEN 15
              WHEN c.bb_bandwidth < 12 THEN 10
              ELSE 5 END) +
        (CASE WHEN c.bb_position > 55 THEN 10 ELSE 0 END) +
        (CASE WHEN c.macd_histogram > 0 THEN 20 ELSE 0 END) +
        (CASE WHEN c.volume_ratio >= 1.2 THEN 15 ELSE 0 END) +
        (CASE WHEN c.adx >= 25 THEN 15 ELSE 0 END)
    AS INT) as master_score,
    
    -- =====================================================
    -- TRADE RECOMMENDATION
    -- =====================================================
    CASE 
        -- EXCELLENT: All conditions met
        WHEN c.momentum_1h > 1.0 
             AND c.bb_bandwidth < 8 
             AND c.macd_histogram > 0 
             AND c.volume_ratio >= 1.2
             AND c.rsi <= @max_rsi_for_entry
            THEN 'STRONG_BUY'
        
        -- GOOD: Most conditions met
        WHEN c.momentum_1h > 0.5 
             AND c.bb_bandwidth < 10 
             AND c.macd_histogram > 0
             AND c.rsi <= @max_rsi_for_entry
            THEN 'BUY'
        
        -- WATCH: Promising but needs confirmation
        WHEN (c.momentum_1h > 0.5 OR c.bb_bandwidth < 8)
             AND c.macd_histogram > 0
            THEN 'WATCH'
        
        -- OVERSOLD BOUNCE: Dip buy opportunity
        WHEN c.rsi < 35 
             AND c.momentum_1h > 0.3
             AND c.macd_histogram > -0.1
            THEN 'DIP_BUY'
        
        -- AVOID: Poor setup
        ELSE 'AVOID'
    END as trade_recommendation,
    
    -- =====================================================
    -- CONFIDENCE LEVEL
    -- =====================================================
    CASE 
        WHEN c.momentum_1h > 1.5 AND c.bb_bandwidth < 5 AND c.volume_ratio >= 1.5 
            THEN 'VERY_HIGH'
        WHEN c.momentum_1h > 1.0 AND c.bb_bandwidth < 8 AND c.volume_ratio >= 1.2 
            THEN 'HIGH'
        WHEN c.momentum_1h > 0.5 AND c.bb_bandwidth < 10 
            THEN 'MEDIUM'
        ELSE 'LOW'
    END as confidence_level,
    
    -- =====================================================
    -- SUGGESTED POSITION SIZE
    -- =====================================================
    CASE 
        WHEN c.momentum_1h > 1.5 AND c.bb_bandwidth < 5 AND c.volume_ratio >= 1.5 
            THEN '5%'
        WHEN c.momentum_1h > 1.0 AND c.bb_bandwidth < 8 AND c.volume_ratio >= 1.2 
            THEN '3%'
        WHEN c.momentum_1h > 0.5 OR c.rsi < 35 
            THEN '2%'
        ELSE '0%'
    END as suggested_position,
    
    -- =====================================================
    -- TARGET & STOP LOSS
    -- =====================================================
    CASE 
        WHEN c.momentum_1h > 1.5 THEN '15-20%'
        WHEN c.momentum_1h > 1.0 THEN '10-15%'
        ELSE '5-10%'
    END as target_gain,
    
    CASE 
        WHEN c.momentum_1h > 1.0 THEN '-5%'
        ELSE '-3%'
    END as stop_loss,
    
    -- =====================================================
    -- ANALYZER CONFIRMATION (if available)
    -- =====================================================
    ISNULL(ar.combined_signal, 'NO_SIGNAL') as analyzer_signal,
    ISNULL(ar.buy_probability, 0) as analyzer_probability

FROM current_data c
LEFT JOIN analysis_results ar ON c.symbol = ar.symbol
WHERE 1=1
    -- Filters
    AND c.rsi <= @max_rsi_for_entry  -- Avoid overbought
    AND (c.momentum_1h >= @min_momentum_pct OR c.rsi < 35)  -- Either momentum OR oversold
    AND c.volume_ratio >= @min_volume_ratio  -- Volume confirmation
    
ORDER BY 
    -- Prioritize by best setup
    CASE 
        WHEN c.momentum_1h > 1.5 AND c.bb_bandwidth < 5 THEN 1
        WHEN c.momentum_1h > 1.0 AND c.bb_bandwidth < 8 THEN 2
        WHEN c.rsi < 35 AND c.momentum_1h > 0.3 THEN 3
        WHEN c.momentum_1h > 0.5 THEN 4
        ELSE 5
    END ASC,
    master_score DESC,
    c.momentum_1h DESC;