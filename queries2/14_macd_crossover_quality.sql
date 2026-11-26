
-- =================================================================================
-- 14_macd_crossover_quality.sql (Refactored & Scale-Normalized)
-- =================================================================================
-- PURPOSE: Evaluates the velocity and angular separation of MACD crossovers.
-- Insulated mathematically against asset pricing scale variations.
-- =================================================================================

USE db_Trading;
GO

-- ---------------------------------------------------------------------------------
-- 1. CONFIGURATION PARAMETERS (Variables)
-- ---------------------------------------------------------------------------------
DECLARE @start_hours_ago INT = 0; -- 0 = Most recent candle snapshot
DECLARE @end_hours_ago INT = 24; -- Active scanning window depth
DECLARE @symbol_filter NVARCHAR(50) = NULL; -- Specific asset filter or NULL

-- Strategy Threshold Parameter Matrices
DECLARE @min_volume_ratio DECIMAL(5,2) = 1.20; -- Minimum institutional backing volume vs SMA20
DECLARE @max_rsi_entry DECIMAL(5,2) = 62.00; -- Defensive ceiling to block late momentum chases
DECLARE @require_sub_zero_cross INT = 0; -- 1 = Strictly limits triggers to deep reversal bottoms

-- ---------------------------------------------------------------------------------
-- 2. TIME ENGINE CALCULATION & TIMELINE BUFFER SEPARATION
-- ---------------------------------------------------------------------------------
DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 3600);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 3600);

-- Allocate 72-hour historical buffer to protect lagging window calculations near the timeline boundary
DECLARE @buffer_timestamp BIGINT = @end_timestamp - 259200;

-- ---------------------------------------------------------------------------------
-- 3. SCALE-NORMALIZED DATA PROCESSING PIPELINE
-- ---------------------------------------------------------------------------------
WITH Buffered_MACD_Snapshots AS (
    SELECT 
        symbol,
        timestamp,
        [close],
        RSI as rsi,
        volume,
        price_change_1,
        price_change_2,
        
        -- Direct structural mapping variables to your Python calculations
        MACD_12_26_9 as macd_line,
        MACDs_12_26_9 as signal_line,
        MACDh_12_26_9 as histogram,

        -- Standardizing volume metrics (Bypassing currency-denominated VWMA issues)
        AVG(volume) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) as true_volume_sma_20,

        -- Calculate the standard deviation of the histogram over a 20-period lookback to normalize scale
        STDEV(MACDh_12_26_9) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) as hist_std_dev_20,
        
        -- Chronologically stable sequence indicators to catch crossovers
        LAG(MACD_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_macd,
        LAG(MACDs_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_signal,
        LAG(MACDh_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_histogram
    FROM tab_calculated_60
    WHERE timestamp >= @buffer_timestamp
),

Crossover_Trigger_Engine AS (
    SELECT 
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        [close] as current_price,
        ROUND(price_change_1, 2) as momentum_1h_pct,
        ROUND(price_change_2, 2) as momentum_2h_pct,
        ROUND(rsi, 1) as rsi_value,
        macd_line,
        signal_line,
        histogram,
        
        -- Normalized Angular Separation Velocity (Expressed as multiples of standard deviation)
        CASE 
            WHEN hist_std_dev_20 > 0 
            THEN ROUND((histogram - prev_histogram) / hist_std_dev_20, 2)
            ELSE 0.00 
        END as normalized_separation_velocity,

        -- Asset-agnostic nominal separation depth
        ROUND(ABS(macd_line - signal_line), 4) as raw_line_separation,
        CASE WHEN true_volume_sma_20 > 0 THEN ROUND(volume / true_volume_sma_20, 2) ELSE 0 END as real_volume_ratio,

        -- State machine tracking exact crossover events
        CASE 
            WHEN prev_macd <= prev_signal AND macd_line > signal_line THEN 'BULLISH_CROSSOVER'
            WHEN prev_macd >= prev_signal AND macd_line < signal_line THEN 'BEARISH_CROSSOVER'
            ELSE 'NO_CROSSOVER'
        END as crossover_type
    FROM Buffered_MACD_Snapshots
    -- Slice away tracking buffer elements safely
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
      AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
),

Scored_Crossover_Matrix AS (
    SELECT 
        *,
        -- Comprehensive Crossover Quality Confidence Scorer (0-100 Base)
        CAST(
            -- Angular separation velocity scale weights (Z-Score performance metrics)
            (CASE WHEN normalized_separation_velocity >= 1.50 THEN 40
                  WHEN normalized_separation_velocity >= 0.75 THEN 25
                  WHEN normalized_separation_velocity > 0.00 THEN 10 ELSE 0 END) +
            
            -- Location-based Territory premium scaling
            (CASE WHEN macd_line < 0.00 AND crossover_type = 'BULLISH_CROSSOVER' THEN 30 -- Reversal premium
                  WHEN macd_line >= 0.00 AND crossover_type = 'BULLISH_CROSSOVER' THEN 15 -- Continuation weights
                  ELSE 0 END) +
                  
            -- Institutional Volumetric Confirmation
            (CASE WHEN real_volume_ratio >= 1.50 THEN 20
                  WHEN real_volume_ratio >= 1.15 THEN 10 ELSE 0 END) +
                  
            -- Price Velocity support tracking
            (CASE WHEN momentum_1h_pct > 0.40 THEN 10 ELSE 0 END)
        AS INT) as crossover_quality_score
    FROM Crossover_Trigger_Engine
    WHERE crossover_type <> 'NO_CROSSOVER'
)

-- ---------------------------------------------------------------------------------
-- 4. INSIGHTS-FIRST DISPLAY ARCHITECTURE ORDERING
-- ---------------------------------------------------------------------------------
SELECT 
    -- PRIMARY ACTIONABLE SELECTION TARGETS FIRST
    crossover_quality_score,
    symbol,
    crossover_type,
    
    crossover_classification = CASE 
        WHEN crossover_quality_score >= 75 AND crossover_type = 'BULLISH_CROSSOVER' THEN 'STRONG_VALIDATED_REVERSAL_BUY'
        WHEN crossover_quality_score >= 50 AND crossover_type = 'BULLISH_CROSSOVER' THEN 'STANDARD_TREND_CONTINUATION_BUY'
        WHEN crossover_type = 'BEARISH_CROSSOVER' AND crossover_quality_score >= 65 THEN 'HIGH_VELOCITY_TREND_REJECTION_EXIT'
        ELSE 'LOW_CONFIDENCE_DRIFT_CROSS'
    END,

    -- VELOCITY AND ANGULAR MEASUREMENTS
    normalized_separation_velocity as angular_cross_velocity,
    real_volume_ratio,
    momentum_1h_pct,
    
    -- TECHNICAL DETAILS
    ROUND(macd_line, 4) as macd_line,
    ROUND(signal_line, 4) as signal_line,
    ROUND(histogram, 4) as histogram,
    raw_line_separation,
    rsi_value,
    
    -- TIMESTAMPS
    hours_ago,
    datetime_tehran,
    current_price
FROM Scored_Crossover_Matrix
WHERE 1=1
    -- Operational Boundary Assertions
    AND (@require_sub_zero_cross = 0 OR macd_line < 0)
    AND (crossover_type = 'BEARISH_CROSSOVER' OR (real_volume_ratio >= @min_volume_ratio AND rsi_value <= @max_rsi_entry))

ORDER BY 
    -- Master Layout Priorities System
    crossover_quality_score DESC,
    normalized_separation_velocity DESC,
    timestamp DESC;

