-- =====================================================
-- 09_bb_analysis.sql
-- =====================================================
-- PURPOSE: Complete Bollinger Band analysis with squeeze detection,
--          middle band slope tracking, and expansion detection
--
-- PARAMETERS:
-- @start_hours_ago: Beginning of time window (default: 0 = most recent)
-- @end_hours_ago: End of time window (default: 24 = 24 hours back)
-- @max_bandwidth_pct: Maximum bandwidth to detect squeeze (default: 10)
-- @min_bandwidth_expansion: Minimum bandwidth expansion to detect burst (default: 0.5)
-- @require_rising_middle: Require middle band to be rising (0 = no, 1 = yes, default: 0)
-- @min_middle_rise_pct: Minimum middle band rise percentage if rising required (default: 0.3)
-- @min_momentum: Minimum 1h price change (default: 0, disabled)
-- @min_volume_ratio: Minimum volume vs VWMA_20 (default: 0, disabled)
-- @symbol_filter: Specific symbol filter (default: NULL = all symbols)
--
-- SQUEEZE TYPES:
-- EXTREME_SQUEEZE: Bandwidth < 5% (very tight, ready to explode)
-- TIGHT_SQUEEZE: Bandwidth between 5-8% (building pressure)
-- NORMAL_RANGE: Bandwidth between 8-12%
-- WIDE_EXPANDED: Bandwidth > 12% (already moving)
--
-- BURST SIGNALS:
-- BULLISH_BURST: Breaking upward with volume and momentum
-- BEARISH_BURST: Breaking downward
-- UPTREND_STARTING: Rising middle band, building momentum
--
-- USE CASE: Find squeeze patterns ready to break out
-- SORTED BY: Burst confidence highest first
-- =====================================================

USE db_Trading;

-- =====================================================
-- CONFIGURATION PARAMETERS (EDIT THESE VALUES)
-- =====================================================

DECLARE @start_hours_ago INT = 0;              -- 0 = most recent candle
DECLARE @end_hours_ago INT = 4;               -- 24 = last 24 hours
DECLARE @max_bandwidth_pct DECIMAL(5,2) = 10;  -- Max bandwidth to consider (squeeze threshold)
DECLARE @min_bandwidth_expansion DECIMAL(5,2) = 0.5;  -- Min % expansion to detect burst
DECLARE @require_rising_middle INT = 0;        -- 0 = no, 1 = yes
DECLARE @min_middle_rise_pct DECIMAL(5,2) = 0.3;  -- Min middle band rise % (if rising required)
DECLARE @min_momentum DECIMAL(5,2) = 0;        -- Min 1h price change % (0 = disabled)
DECLARE @min_volume_ratio DECIMAL(5,2) = 0;    -- Min volume / VWMA_20 (0 = disabled)
DECLARE @symbol_filter NVARCHAR(50) = NULL;    -- NULL = all symbols, or 'BTCIRT'

-- =====================================================
-- CALCULATE TIME BOUNDARIES
-- =====================================================

DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 60 * 60);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 60 * 60);

-- =====================================================
-- MAIN QUERY WITH BOLLINGER BAND ANALYSIS
-- =====================================================

WITH bb_analysis AS (
    SELECT 
        -- Basic info
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        
        -- Price data
        ROUND([close], 2) as price,
        
        -- Bollinger Bands (wrap column names in brackets)
        ROUND([BBU_20_2.0_2.0], 2) as bb_upper,
        ROUND([BBM_20_2.0_2.0], 2) as bb_middle,
        ROUND([BBL_20_2.0_2.0], 2) as bb_lower,
        
        -- Bandwidth calculations
        CASE 
            WHEN [BBM_20_2.0_2.0] > 0 
            THEN ROUND(([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100, 2)
            ELSE 0
        END as bandwidth_pct,
        
        -- Position within bands (0-100 scale, 50 = middle)
        CASE 
            WHEN ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) > 0
            THEN ROUND(([close] - [BBL_20_2.0_2.0]) / ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) * 100, 1)
            ELSE 50
        END as bb_position_pct,
        
        -- Previous values for trend detection
        LAG(ROUND(([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100, 2)) 
            OVER (PARTITION BY symbol ORDER BY timestamp) as prev_bandwidth,
        LAG(ROUND([BBM_20_2.0_2.0], 2)) 
            OVER (PARTITION BY symbol ORDER BY timestamp) as prev_middle,
        
        -- Middle band slope
        CASE 
            WHEN LAG([BBM_20_2.0_2.0]) OVER (PARTITION BY symbol ORDER BY timestamp) > 0
            THEN ROUND(([BBM_20_2.0_2.0] - LAG([BBM_20_2.0_2.0]) OVER (PARTITION BY symbol ORDER BY timestamp)) 
                / LAG([BBM_20_2.0_2.0]) OVER (PARTITION BY symbol ORDER BY timestamp) * 100, 2)
            ELSE 0
        END as middle_band_slope_pct,
        
        -- Momentum and volume
        ROUND(price_change_1, 2) as momentum_1h_pct,
        ROUND(price_change_2, 2) as momentum_2h_pct,
        ROUND(volume, 0) as volume,
        ROUND(VWMA_20, 0) as avg_volume,
        ROUND(RSI, 1) as rsi,
        ROUND(MACD_12_26_9, 4) as macd_line,
        ROUND(MACDh_12_26_9, 4) as macd_histogram

    FROM tab_calculated_60
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
        AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
),
bb_classified AS (
    SELECT 
        *,
        
        -- =====================================================
        -- SQUEEZE STATUS CLASSIFICATION
        -- =====================================================
        CASE 
            WHEN bandwidth_pct < 5 THEN 'EXTREME_SQUEEZE'
            WHEN bandwidth_pct < 8 THEN 'TIGHT_SQUEEZE'
            WHEN bandwidth_pct < 12 THEN 'NORMAL_RANGE'
            ELSE 'WIDE_EXPANDED'
        END as squeeze_status,
        
        -- =====================================================
        -- MIDDLE BAND TREND
        -- =====================================================
        CASE 
            WHEN middle_band_slope_pct >= 0.5 THEN 'STRONG_UPTREND'
            WHEN middle_band_slope_pct >= 0.2 THEN 'WEAK_UPTREND'
            WHEN middle_band_slope_pct <= -0.5 THEN 'STRONG_DOWNTREND'
            WHEN middle_band_slope_pct <= -0.2 THEN 'WEAK_DOWNTREND'
            ELSE 'FLAT'
        END as middle_band_trend,
        
        -- =====================================================
        -- BANDWIDTH CHANGE (Expanding or Contracting)
        -- =====================================================
        CASE 
            WHEN prev_bandwidth IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN bandwidth_pct > prev_bandwidth + @min_bandwidth_expansion THEN 'EXPANDING'
            WHEN bandwidth_pct < prev_bandwidth - @min_bandwidth_expansion THEN 'CONTRACTING'
            ELSE 'STABLE'
        END as bandwidth_change,
        
        -- =====================================================
        -- BURST DIRECTION DETECTION
        -- =====================================================
        CASE 
            -- Bullish burst conditions
            WHEN bb_position_pct > 60 
                 AND momentum_1h_pct > 0.5 
                 AND bandwidth_pct > prev_bandwidth + @min_bandwidth_expansion
                THEN 'BULLISH_BURST_ACTIVE'
            WHEN bb_position_pct > 60 
                 AND momentum_1h_pct > 0
                THEN 'BULLISH_BURST_STARTING'
            WHEN bb_position_pct > 50 
                 AND middle_band_slope_pct > 0
                THEN 'UPTREND_STARTING'
            -- Bearish burst conditions
            WHEN bb_position_pct < 40 
                 AND momentum_1h_pct < -0.5 
                 AND bandwidth_pct > prev_bandwidth + @min_bandwidth_expansion
                THEN 'BEARISH_BURST_ACTIVE'
            WHEN bb_position_pct < 40 
                 AND momentum_1h_pct < 0
                THEN 'BEARISH_BURST_STARTING'
            WHEN bb_position_pct < 50 
                 AND middle_band_slope_pct < 0
                THEN 'DOWNTREND_STARTING'
            ELSE 'NEUTRAL'
        END as burst_direction,
        
        -- =====================================================
        -- BURST CONFIDENCE SCORE (0-100)
        -- =====================================================
        CAST(
            (CASE WHEN bandwidth_pct < 8 THEN 35 ELSE 0 END) +      -- Squeeze condition
            (CASE WHEN bb_position_pct > 55 THEN 15 ELSE 0 END) +   -- Upper half of bands
            (CASE WHEN momentum_1h_pct > 0.5 THEN 20 ELSE 0 END) +  -- Positive momentum
            (CASE WHEN middle_band_slope_pct > 0.2 THEN 15 ELSE 0 END) + -- Rising middle
            (CASE WHEN volume > avg_volume THEN 15 ELSE 0 END)      -- Volume confirmation
        AS INT) as burst_confidence

    FROM bb_analysis
)
SELECT 
    -- Identification
    symbol,
    hours_ago,
    datetime_tehran,
    price,
    
    -- Bollinger Band values
    bb_upper,
    bb_middle,
    bb_lower,
    bandwidth_pct,
    bb_position_pct,
    
    -- Trend analysis
    squeeze_status,
    middle_band_trend,
    ROUND(middle_band_slope_pct, 2) as middle_band_slope_pct,
    bandwidth_change,
    CASE 
        WHEN prev_bandwidth IS NOT NULL THEN ROUND(bandwidth_pct - prev_bandwidth, 2)
        ELSE NULL
    END as bandwidth_change_pct,
    
    -- Burst signal
    burst_direction,
    burst_confidence,
    
    -- Confirmation indicators
    momentum_1h_pct,
    momentum_2h_pct,
    rsi,
    macd_line,
    macd_histogram,
    
    -- Volume
    volume,
    avg_volume,
    CASE 
        WHEN avg_volume > 0 THEN ROUND(volume / avg_volume, 2)
        ELSE 0
    END as volume_ratio,
    CASE 
        WHEN volume > avg_volume * 1.5 THEN 'HIGH_VOLUME'
        WHEN volume > avg_volume * 1.2 THEN 'ABOVE_AVERAGE_VOLUME'
        WHEN avg_volume > 0 THEN 'NORMAL_VOLUME'
        ELSE 'UNKNOWN'
    END as volume_status,

    -- =====================================================
    -- FINAL BUY SIGNAL (All conditions combined)
    -- =====================================================
    CASE 
        WHEN @require_rising_middle = 1 
             AND middle_band_slope_pct < @min_middle_rise_pct 
            THEN 'FILTERED_OUT - Middle band not rising'
        WHEN burst_direction IN ('BULLISH_BURST_ACTIVE', 'BULLISH_BURST_STARTING', 'UPTREND_STARTING')
             AND burst_confidence >= 60
            THEN 'BUY_SIGNAL'
        WHEN burst_direction IN ('BULLISH_BURST_ACTIVE', 'BULLISH_BURST_STARTING')
            THEN 'WATCH_SIGNAL'
        ELSE 'NO_SIGNAL'
    END as buy_signal

FROM bb_classified
WHERE 1=1
    -- Squeeze or expansion filter (using calculated columns directly)
    AND (bandwidth_pct <= @max_bandwidth_pct 
         OR (prev_bandwidth IS NOT NULL AND bandwidth_pct > prev_bandwidth + @min_bandwidth_expansion))
    -- Momentum filter
    AND momentum_1h_pct >= @min_momentum
    -- Volume filter
    AND (@min_volume_ratio <= 0 OR (avg_volume > 0 AND volume / avg_volume >= @min_volume_ratio))
    -- Rising middle band filter (optional)
    AND (@require_rising_middle = 0 OR middle_band_slope_pct >= @min_middle_rise_pct)
    -- Position filter (avoid overbought/oversold extremes unless bursting)
    AND bb_position_pct BETWEEN 20 AND 80

ORDER BY 
    -- Best signals first
    burst_confidence DESC,
    bandwidth_pct ASC,
    momentum_1h_pct DESC;