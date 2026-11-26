
-- =================================================================================
-- 09_bb_analysis.sql (Refactored & High-Tier Tactical Execution)
-- =================================================================================
-- PURPOSE: Real-time tactical trigger engine for Bollinger Band squeeze contraction
-- and high-velocity expansion/burst breakout identification.
-- =================================================================================

USE db_Trading;
GO

-- ---------------------------------------------------------------------------------
-- 1. CONFIGURATION PARAMETERS (Variables)
-- ---------------------------------------------------------------------------------
DECLARE @start_hours_ago INT = 0; -- 0 = Most recent candle
DECLARE @end_hours_ago INT = 6; -- Active scanning window depth
DECLARE @symbol_filter NVARCHAR(50) = NULL; -- Specific asset or NULL

-- Strategy Threshold Parameters
DECLARE @max_bandwidth_squeeze DECIMAL(5,2) = 8.50; -- Threshold defining strict asset compression
DECLARE @min_bandwidth_expansion DECIMAL(5,2) = 0.75; -- Minimum bandwidth delta to confirm an active burst
DECLARE @require_rising_middle INT = 0; -- 1 = Enforces underlying trend alignment
DECLARE @min_middle_rise_pct DECIMAL(5,2) = 0.15; -- Basis slope requirement
DECLARE @min_momentum DECIMAL(5,2) = 0.50; -- Minimum 1h price performance baseline
DECLARE @min_volume_ratio DECIMAL(5,2) = 1.20; -- Volume verification threshold vs SMA20

-- Strategy Toggles
DECLARE @signal_mode NVARCHAR(20) = 'ALL'; -- 'ALL', 'BUY_ONLY', 'WATCH_ONLY'
DECLARE @exclude_overbought INT = 1; -- 1 = Protects from chasing near extreme RSI exhaustion ceilings

-- ---------------------------------------------------------------------------------
-- 2. TIME ENGINE CALCULATION & TIMELINE BUFFER SEPARATION
-- ---------------------------------------------------------------------------------
DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 3600);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 3600);

-- Expand lookback to protect historical integrity of LAG window partitions
DECLARE @buffer_timestamp BIGINT = @end_timestamp - 172800;

-- ---------------------------------------------------------------------------------
-- 3. REAL-TIME DATA PROCESSING PIPELINE
-- ---------------------------------------------------------------------------------
WITH Buffered_BB_Snapshots AS (
    SELECT 
        symbol,
        timestamp,
        [close],
        price_change_1,
        RSI as rsi,
        volume,
        
        -- Map columns directly to your Python pipeline indicators
        ROUND([BBM_20_2.0_2.0], 2) as bb_middle,
        ROUND([BBU_20_2.0_2.0], 2) as bb_upper,
        ROUND([BBL_20_2.0_2.0], 2) as bb_lower,
        
        -- Corrected Bandwidth Metric
        CASE 
            WHEN [BBM_20_2.0_2.0] > 0 
            THEN ROUND(([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100, 2)
            ELSE 100.00
        END as bandwidth_pct,

        -- Corrected Volume Metric (True volume lookback lookbehind)
        AVG(volume) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) as true_volume_sma_20,
        
        -- Chronologically stable window lookbacks
        LAG([BBM_20_2.0_2.0], 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_middle,
        LAG([BBM_20_2.0_2.0], 2) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_middle_2,
        
        -- Bandwidth continuity tracking
        LAG(
            CASE WHEN [BBM_20_2.0_2.0] > 0 THEN ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100 ELSE 100.00 END, 1
        ) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_bandwidth
    FROM tab_calculated_60
    WHERE timestamp >= @buffer_timestamp
),

Tactical_Metrics_Engine AS (
    SELECT 
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        [close] as current_price,
        ROUND(price_change_1, 2) as momentum_1h_pct,
        ROUND(rsi, 1) as rsi_value,
        
        bandwidth_pct,
        prev_bandwidth,
        ROUND(bandwidth_pct - prev_bandwidth, 2) as bandwidth_expansion_velocity,
        
        -- Compute true volume multiplier
        CASE WHEN true_volume_sma_20 > 0 THEN ROUND(volume / true_volume_sma_20, 2) ELSE 0 END as real_volume_ratio,
        
        -- Relative location inside bands (0 = Lower Band Floor, 100 = Upper Band Ceiling)
        CASE 
            WHEN (bb_upper - bb_lower) > 0 
            THEN ROUND(([close] - bb_lower) / (bb_upper - bb_lower) * 100, 1)
            ELSE 50.0
        END as bb_position_pct,

        -- Basis Trend Alignment Vectors
        CASE 
            WHEN prev_middle > 0 
            THEN ROUND((bb_middle - prev_middle) / prev_middle * 100, 2)
            ELSE 0.00
        END as middle_band_slope_pct,

        -- Squeeze Tightness Tier Assignments
        CASE 
            WHEN bandwidth_pct < 5.00 THEN 'EXTREME_SQUEEZE'
            WHEN bandwidth_pct BETWEEN 5.00 AND 8.50 THEN 'TIGHT_SQUEEZE'
            WHEN bandwidth_pct BETWEEN 8.50 AND 12.00 THEN 'NORMAL_RANGE'
            ELSE 'WIDE_EXPANDED'
        END as squeeze_classification,

        -- Dynamic Actionable Structural Direction Matrices
        CASE 
            WHEN [close] >= bb_upper AND (bandwidth_pct > prev_bandwidth + @min_bandwidth_expansion) THEN 'BULLISH_BURST_ACTIVE'
            WHEN [close] >= bb_upper AND bandwidth_pct <= @max_bandwidth_squeeze THEN 'BULLISH_BURST_STARTING'
            WHEN [close] > bb_middle AND prev_bandwidth <= @max_bandwidth_squeeze AND bandwidth_pct > prev_bandwidth THEN 'UPTREND_STARTING'
            WHEN [close] <= bb_lower AND (bandwidth_pct > prev_bandwidth + @min_bandwidth_expansion) THEN 'BEARISH_BURST_ACTIVE'
            ELSE 'STABLE_OR_RANGING'
        END as burst_direction
    FROM Buffered_BB_Snapshots
    -- Slice buffer away cleanly within projection engine
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
      AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
),

Scored_Execution_Matrix AS (
    SELECT 
        *,
        -- Comprehensive Tactical Confidence Engine (0-100 Scale)
        CAST(
            -- Band Expansion Velocity Weights
            (CASE WHEN bandwidth_expansion_velocity >= 1.5 THEN 30
                  WHEN bandwidth_expansion_velocity >= 0.5 THEN 20
                  WHEN bandwidth_pct <= 6.0 THEN 15 ELSE 5 END) +
            
            -- Volume Velocity Confirmations
            (CASE WHEN real_volume_ratio >= 1.8 THEN 30
                  WHEN real_volume_ratio >= 1.2 THEN 15 ELSE 0 END) +
            
            -- Price Positioning Alignment Contexts
            (CASE WHEN bb_position_pct >= 95 THEN 20
                  WHEN bb_position_pct >= 80 THEN 10 ELSE 0 END) +
            
            -- Structural Base Slopes
            (CASE WHEN middle_band_slope_pct >= 0.25 THEN 20
                  WHEN middle_band_slope_pct > 0.00 THEN 10 ELSE 0 END)
        AS INT) as burst_confidence_score
    FROM Tactical_Metrics_Engine
)

-- ---------------------------------------------------------------------------------
-- 4. HIGHEST ENLIGHTENING COLUMNS ORDERING (DISPLAY SELECTION)
-- ---------------------------------------------------------------------------------
SELECT 
    -- ACTIONABLE PRIMARY DATA FIELDS FIRST
    burst_confidence_score,
    symbol,
    burst_direction,
    squeeze_classification,
    
    tactical_execution_signal = CASE 
        WHEN (@require_rising_middle = 1 AND middle_band_slope_pct < @min_middle_rise_pct) THEN 'FILTERED_OUT (TREND_MISALIGNMENT)'
        WHEN burst_direction IN ('BULLISH_BURST_ACTIVE', 'BULLISH_BURST_STARTING', 'UPTREND_STARTING') AND burst_confidence_score >= 65 THEN 'TRIGGER_BUY_EXECUTION'
        WHEN burst_direction IN ('BULLISH_BURST_ACTIVE', 'BULLISH_BURST_STARTING') THEN 'TACTICAL_WATCH_LIST'
        ELSE 'NO_SIGNAL'
    END,

    -- MOMENTUM & VELOCITY VERIFICATION METRICS
    momentum_1h_pct,
    real_volume_ratio,
    bandwidth_expansion_velocity,
    
    -- VOLATILITY TENSION STATS
    ROUND(bandwidth_pct, 2) as current_bandwidth_pct,
    ROUND(bb_position_pct, 1) as band_location_pct,
    middle_band_slope_pct as basis_trend_slope,
    rsi_value,
    
    -- TIMESTAMPS
    hours_ago,
    datetime_tehran,
    current_price
FROM Scored_Execution_Matrix
WHERE 1=1
    -- Operational Strategy Boundaries
    AND momentum_1h_pct >= @min_momentum
    AND real_volume_ratio >= @min_volume_ratio
    AND (@exclude_overbought = 0 OR rsi_value <= 68.0)
    
    -- Interactive Filter Routing Configurations
    AND (
         @signal_mode = 'ALL'
         OR (@signal_mode = 'BUY_ONLY' AND burst_direction IN ('BULLISH_BURST_ACTIVE', 'BULLISH_BURST_STARTING', 'UPTREND_STARTING') AND burst_confidence_score >= 50)
         OR (@signal_mode = 'WATCH_ONLY' AND bandwidth_pct <= @max_bandwidth_squeeze)
        )

ORDER BY 
    -- Master Priority Tactical Sort Profile
    burst_confidence_score DESC,
    bandwidth_expansion_velocity DESC,
    momentum_1h_pct DESC,
    timestamp DESC;

