-- =================================================================================
-- 12_master_signal_aggregator.sql (Refactored & Fully Integrated)
-- =================================================================================
-- PURPOSE: Unified Multi-Indicator Convergence Engine. Cross-analyzes and scores
-- all underlying technical setups on a single chronological plane.
-- =================================================================================

USE db_Trading;
GO

-- ---------------------------------------------------------------------------------
-- 1. GLOBAL CONFIGURATION PARAMETERS (Dashboard Controls)
-- ---------------------------------------------------------------------------------
DECLARE @lookback_hours INT = 6; -- Signal parsing window depth
DECLARE @symbol_filter NVARCHAR(50) = NULL; -- Specific asset or NULL

-- Global Defensive Boundary Overrides
DECLARE @max_rsi DECIMAL(5,2) = 65.00; -- Hard ceiling to protect capital from overbought traps
DECLARE @min_volume_ratio DECIMAL(5,2) = 1.15; -- Minimum institutional trading volume vs SMA20
DECLARE @min_master_score INT = 40; -- Lower filter boundary for dashboard output visibility

-- Strategy Scoring Weights
DECLARE @weight_momentum DECIMAL(3,2) = 1.00; -- Multiplier for velocity signals
DECLARE @weight_bb DECIMAL(3,2) = 1.20; -- Multiplier for volatility compression/burst setups
DECLARE @weight_macd DECIMAL(3,2) = 1.10; -- Multiplier for trend reversal crossovers
DECLARE @weight_oversold DECIMAL(3,2) = 1.25; -- Multiplier for deep historical floor sweeps
DECLARE @weight_divergence DECIMAL(3,2) = 1.40; -- Highest premium: Structural divergence pivot matching

-- ---------------------------------------------------------------------------------
-- 2. TIME ENGINE CALCULATION & BUFFER INSULATION
-- ---------------------------------------------------------------------------------
DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time;
DECLARE @end_timestamp BIGINT = @current_time - (@lookback_hours * 3600);

-- Allocate deep history buffer to process window functions and pivot indicators continuously
DECLARE @buffer_timestamp BIGINT = @end_timestamp - 259200; -- 72-hour protection layer

-- ---------------------------------------------------------------------------------
-- 3. UNIFIED ANALYTICAL STAGE DIRECTORY (CTEs)
-- ---------------------------------------------------------------------------------
WITH Consolidated_Market_Cache AS (
    SELECT 
        symbol,
        timestamp,
        [close],
        high,
        low,
        volume,
        RSI as rsi,
        MACD_12_26_9 as macd_line,
        MACDs_12_26_9 as signal_line,
        MACDh_12_26_9 as histogram,
        price_change_1,
        momentum_acceleration,
        
        -- Corrected Bandwidth Expression
        CASE WHEN [BBM_20_2.0_2.0] > 0 THEN (([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100) ELSE 100.00 END as bandwidth_pct,
        CASE WHEN ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) > 0 THEN (([close] - [BBL_20_2.0_2.0]) / ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) * 100) ELSE 50.0 END as bb_position,
        ROUND([BBM_20_2.0_2.0], 2) as bb_middle,
        ROUND([BBU_20_2.0_2.0], 2) as bb_upper,
        ROUND([BBL_20_2.0_2.0], 2) as bb_lower,

        -- Unified Volume Standardization Fix (Replaces broken VWMA calculation variables)
        AVG(volume) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) as true_volume_sma_20,
        
        -- Continuity Tracing Elements
        LAG(MACD_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_macd,
        LAG(MACDs_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_signal,
        LAG(MACDh_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_histogram,
        LAG(RSI, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_rsi,
        
        -- Pivot structural elements to pull native live structural divergences
        MIN(low) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING) as pivot_window_low,
        MAX(high) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING) as pivot_window_high
    FROM tab_calculated_60
    WHERE timestamp >= @buffer_timestamp
),

-- [STRATEGY MODULE 1: MOMENTUM TRACKING]
Module_Momentum AS (
    SELECT symbol, timestamp, price_change_1,
        CAST((CASE WHEN price_change_1 >= 1.5 AND momentum_acceleration > 0 THEN 40
                   WHEN price_change_1 >= 0.75 THEN 20 ELSE 0 END) * @weight_momentum AS INT) as score
    FROM Consolidated_Market_Cache
),

-- [STRATEGY MODULE 2: BOLLINGER VOLATILITY BREAKOUTS]
Module_Bollinger AS (
    SELECT symbol, timestamp, bandwidth_pct, bb_position,
        CAST((CASE WHEN [close] >= bb_upper AND bandwidth_pct < 10.0 THEN 50 -- Squeeze bursting upward
                   WHEN bandwidth_pct <= 6.50 THEN 30 -- Compressing latent energy
                   ELSE 0 END) * @weight_bb AS INT) as score,
        CASE WHEN [close] >= bb_upper THEN 'UPWARD_BURST' WHEN bandwidth_pct <= 8.5 THEN 'COMPRESSION' ELSE 'RANGING' END as state
    FROM Consolidated_Market_Cache
),

-- [STRATEGY MODULE 3: MACD TREND OVERHAULS]
Module_MACD AS (
    SELECT symbol, timestamp, histogram,
        CAST((CASE WHEN prev_macd <= prev_signal AND macd_line > signal_line AND macd_line < 0 THEN 45 -- Sub-zero bullish cross
                   WHEN prev_macd <= prev_signal AND macd_line > signal_line THEN 30 -- Standard bullish cross
                   WHEN histogram > prev_histogram AND histogram > 0 THEN 15 -- Bullish expansion
                   WHEN prev_macd >= prev_signal AND macd_line < signal_line THEN -35 -- BEARISH CONFLICT DROP
                   ELSE 0 END) * @weight_macd AS INT) as score
    FROM Consolidated_Market_Cache
),

-- [STRATEGY MODULE 4: OVERSOLD HISTORICAL REVERSALS]
Module_Oversold AS (
    SELECT symbol, timestamp,
        CAST((CASE WHEN rsi < 25 AND histogram > prev_histogram THEN 45
                   WHEN rsi < 32 THEN 25 ELSE 0 END) * @weight_oversold AS INT) as score
    FROM Consolidated_Market_Cache
),

-- [STRATEGY MODULE 5: STRUCTURAL PIVOT DIVERGENCES]
Module_Divergence AS (
    SELECT c.symbol, c.timestamp,
        CAST((CASE 
            -- Regular Bullish Divergence check matching structural coordinate points
            WHEN c.low = c.pivot_window_low AND c.rsi > c.prev_rsi AND c.price_change_1 > 0 THEN 55 
            ELSE 0 END) * @weight_divergence AS INT) as score
    FROM Consolidated_Market_Cache c
),

-- ---------------------------------------------------------------------------------
-- 4. THE MATRIX ENGINE INTEGRATION CORE
-- ---------------------------------------------------------------------------------
Unified_Matrix_Aggregation AS (
    SELECT 
        base.symbol,
        base.timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, base.timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - base.timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        base.[close] as current_price,
        ROUND(base.price_change_1, 2) as momentum_1h_pct,
        ROUND(base.rsi, 1) as rsi_value,
        CASE WHEN base.true_volume_sma_20 > 0 THEN ROUND(base.volume / base.true_volume_sma_20, 2) ELSE 0 END as real_volume_ratio,
        ROUND(base.bandwidth_pct, 2) as bb_bandwidth,
        ROUND(base.bb_position, 1) as bb_position_pct,
        
        -- Trace individual signal sub-component scores for systemic audit visibility
        m1.score as score_mom,
        m2.score as score_bb,
        m3.score as score_macd,
        m4.score as score_os,
        m5.score as score_div,

        -- Advanced Temporal Decay Formula: Restricts historical signals from inflating modern ranking tiers
        -- Signals printed 4-6 hours ago suffer a 35% score dampening penalty vector
        CAST(
            (m1.score + m2.score + m3.score + m4.score + m5.score) * (CASE WHEN base.timestamp >= @current_time - 3600 THEN 1.00
                  WHEN base.timestamp >= @current_time - 10800 THEN 0.85
                  ELSE 0.65 END)
        AS INT) as composite_master_score,

        -- Count how many core subsystems actively triggered positive buy confidence metrics
        (CASE WHEN m1.score > 0 THEN 1 ELSE 0 END +
         CASE WHEN m2.score > 20 THEN 1 ELSE 0 END +
         CASE WHEN m3.score > 0 THEN 1 ELSE 0 END +
         CASE WHEN m4.score > 0 THEN 1 ELSE 0 END +
         CASE WHEN m5.score > 0 THEN 1 ELSE 0 END) as active_indicators_count
         
    FROM Consolidated_Market_Cache base
    JOIN Module_Momentum m1 ON base.symbol = m1.symbol AND base.timestamp = m1.timestamp
    JOIN Module_Bollinger m2 ON base.symbol = m2.symbol AND base.timestamp = m2.timestamp
    JOIN Module_MACD m3 ON base.symbol = m3.symbol AND base.timestamp = m3.timestamp
    JOIN Module_Oversold m4 ON base.symbol = m4.symbol AND base.timestamp = m4.timestamp
    JOIN Module_Divergence m5 ON base.symbol = m5.symbol AND base.timestamp = m5.timestamp
    
    -- Filter down pipeline cleanly to focus exclusively on active user lookback constraints
    WHERE base.timestamp BETWEEN @end_timestamp AND @start_timestamp
)

-- ---------------------------------------------------------------------------------
-- 5. ACTION-FIRST HIGH-PRIORITY INSIGHT DISPLAY
-- ---------------------------------------------------------------------------------
SELECT 
    -- PRIMARY SYSTEM RANKING COLUMNS PLACED FIRST FOR INSTANT EXECUTION SCANNING
    composite_master_score,
    symbol,
    active_indicators_count as confirmed_subsystems,
    
    master_execution_signal = CASE 
        WHEN composite_master_score >= 110 AND active_indicators_count >= 4 THEN 'STRONG_CONVERGENCE_BUY'
        WHEN composite_master_score >= 70 AND active_indicators_count >= 2 THEN 'VALIDATED_MASTER_BUY'
        WHEN composite_master_score >= 40 THEN 'LATENT_WATCH_TARGET'
        ELSE 'MONITOR_HOLD'
    END,

    -- SUB-COMPONENT SCORE AUDITING MATRIX
    CONCAT('MOM:', score_mom, ' | BB:', score_bb, ' | MACD:', score_macd, ' | OS:', score_os, ' | DIV:', score_div) as subsystem_score_breakdown,
    
    -- SYSTEM RISK & VALIDATION DATA
    momentum_1h_pct,
    real_volume_ratio,
    rsi_value,
    bb_bandwidth as bandwidth_pct,
    bb_position_pct,
    
    -- TIME & VALUE PLOTS
    hours_ago,
    datetime_tehran,
    current_price
FROM Unified_Matrix_Aggregation
WHERE 1=1
    -- Master Core Strategy Assertions
    AND rsi_value <= @max_rsi
    AND real_volume_ratio >= @min_volume_ratio
    AND composite_master_score >= @min_master_score
    AND (@symbol_filter IS NULL OR symbol = @symbol_filter)

ORDER BY 
    -- Master Dashboard Priority Sequence
    composite_master_score DESC,
    active_indicators_count DESC,
    real_volume_ratio DESC,
    timestamp DESC;

