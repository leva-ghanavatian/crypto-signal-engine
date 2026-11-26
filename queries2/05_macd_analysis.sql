-- =================================================================================
-- 05_macd_analysis.sql (Refactored, Highly Preserved & Enhanced)
-- =================================================================================
-- PURPOSE: Tracks precise MACD crossover states and absolute histogram momentum
-- vectors while structurally preventing window-lag truncation errors.
-- =================================================================================

USE db_Trading;
GO

-- ---------------------------------------------------------------------------------
-- 1. CONFIGURATION PARAMETERS (Variables)
-- ---------------------------------------------------------------------------------
DECLARE @start_hours_ago INT = 0; -- 0 = Most recent candle
DECLARE @end_hours_ago INT = 6; -- Standard evaluation timeframe
DECLARE @crossover_only INT = 0; -- 1 = Crossovers only, 0 = All trend states
DECLARE @min_momentum DECIMAL(5,2) = 0.50; -- Lowered to capture institutional high-caps; scores adjust
DECLARE @max_rsi DECIMAL(5,2) = 65.00; -- Blocks entries near localized exhaustion ceilings
DECLARE @signal_type NVARCHAR(30) = 'ALL'; -- 'ALL', 'BULLISH_CROSSOVER', 'BEARISH_CROSSOVER', 'BULLISH', 'BEARISH'
DECLARE @symbol_filter NVARCHAR(50) = NULL; -- Filter for a single asset or NULL

-- Strategy Filters
DECLARE @require_volume_verify INT = 1; -- 1 = Validates setups are backed by active trading interest
DECLARE @centerline_premium INT = 1; -- 1 = Prioritizes deep oversold sub-zero line crossovers

-- ---------------------------------------------------------------------------------
-- 2. TIME ENGINE CALCULATION & DATA BUFFER EXTENSION
-- ---------------------------------------------------------------------------------
DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 3600);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 3600);

-- Crucial: Buffer lookback expanded by 48 hours to preserve historical continuity for LAG partitions
DECLARE @buffer_timestamp BIGINT = @end_timestamp - 172800; 

-- ---------------------------------------------------------------------------------
-- 3. CORE PROCESSING ENGINE
-- ---------------------------------------------------------------------------------
WITH Raw_Buffered_Context AS (
    SELECT 
        symbol,
        timestamp,
        [close],
        price_change_1,
        RSI,
        volume,
        
        -- Native MACD targets fetched directly from the Python-ingested pipeline
        -- Columns parsed to match pyodbc system mappings: MACD_12_26_9, MACDs_12_26_9, MACDh_12_26_9
        ROUND(MACD_12_26_9, 4) as macd_line,
        ROUND(MACDs_12_26_9, 4) as signal_line,
        ROUND(MACDh_12_26_9, 4) as histogram,

        -- Volumetric Fix: Calculate an actual mathematical volume average over a 20-period lookback
        AVG(volume) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) as true_volume_sma_20,
        
        -- Timestamps look back deep into the buffer buffer safely before window cropping occurs
        LAG(MACD_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_macd,
        LAG(MACDs_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_signal,
        LAG(MACDh_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_histogram
    FROM tab_calculated_60
    WHERE timestamp >= @buffer_timestamp
),

Signals_Classification_Engine AS (
    SELECT 
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        [close] as current_price,
        ROUND(price_change_1, 2) as momentum_1h_pct,
        ROUND(RSI, 1) as rsi_value,
        ROUND(volume, 0) as raw_volume,
        
        macd_line,
        signal_line,
        histogram,
        prev_histogram,
        
        -- True volume ratio calculations completely decoupled from VWMA error matrices
        CASE WHEN true_volume_sma_20 > 0 THEN ROUND(volume / true_volume_sma_20, 2) ELSE 0 END as real_volume_ratio,

        -- Precise Structural State Parsing Matrices
        CASE 
            WHEN prev_macd <= prev_signal AND macd_line > signal_line THEN 'BULLISH_CROSSOVER'
            WHEN prev_macd >= prev_signal AND macd_line < signal_line THEN 'BEARISH_CROSSOVER'
            WHEN macd_line > signal_line AND histogram > 0 THEN 'BULLISH_TERRITORY'
            WHEN macd_line < signal_line AND histogram < 0 THEN 'BEARISH_TERRITORY'
            ELSE 'NEUTRAL'
        END as macd_signal,
        
        CASE 
            WHEN prev_macd <= prev_signal AND macd_line > signal_line THEN 'UP'
            WHEN prev_macd >= prev_signal AND macd_line < signal_line THEN 'DOWN'
            WHEN macd_line > signal_line THEN 'UP'
            WHEN macd_line < signal_line THEN 'DOWN'
            ELSE 'SIDEWAYS'
        END as predicted_direction,

        CASE 
            WHEN histogram > prev_histogram THEN 'STRENGTHENING'
            WHEN histogram < prev_histogram THEN 'WEAKENING'
            ELSE 'STABLE'
        END as histogram_trend,

        -- Multi-Variable Component Scoring Matrix (0-100 Base)
        CAST(
            -- Structural Core Weights
            (CASE WHEN prev_macd <= prev_signal AND macd_line > signal_line THEN 50
                  WHEN macd_line > signal_line AND histogram > 0 THEN 25 ELSE 10 END) +
            
            -- Reversal Location Premium (Extra weight if crossing underneath the zero boundary lines)
            (CASE WHEN prev_macd <= prev_signal AND macd_line > signal_line AND macd_line < 0 THEN 20 ELSE 0 END) +
            
            -- Momentum Velocities
            (CASE WHEN price_change_1 > 1.5 THEN 20
                  WHEN price_change_1 > 0.5 THEN 10 ELSE 0 END) +
            
            -- Volume Confirmations
            (CASE WHEN true_volume_sma_20 > 0 AND volume / true_volume_sma_20 >= 1.5 THEN 10 ELSE 0 END)
        AS INT) as calculated_signal_strength,

        -- System Divergence/Convergence Diagnostic Assertions
        CASE 
            WHEN price_change_1 > 1.5 AND histogram > 0 THEN 'STRONG_CONFIRMATION'
            WHEN price_change_1 > 0.5 AND histogram > 0 THEN 'WEAK_CONFIRMATION'
            WHEN price_change_1 < -0.5 AND histogram > 0 THEN 'BULLISH_DIVERGENCE_WARNING'
            WHEN price_change_1 > 0.5 AND histogram < 0 THEN 'BEARISH_DIVERGENCE_WARNING'
            ELSE 'NEEDS_CONFIRMATION'
        END as confirmation_level
    FROM Raw_Buffered_Context
    -- Apply window cropping safely within the final engine projection tier
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
      AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
)

-- ---------------------------------------------------------------------------------
-- 4. INSIGHT-FIRST PRIORITY LAYOUT
-- ---------------------------------------------------------------------------------
SELECT 
    -- MOST ENLIGHTENING ACTIONABLE COLUMNS CONSOLIDATED FIRST
    calculated_signal_strength,
    symbol,
    macd_signal,
    predicted_direction,
    confirmation_level,
    histogram_trend,
    
    -- QUANTIFIABLE VERIFICATION VALUES
    momentum_1h_pct,
    rsi_value,
    real_volume_ratio,
    
    -- TECHNICAL INDICATOR TRACE PLOT STRINGS
    macd_line,
    signal_line,
    histogram as histogram_value,
    
    -- TIMESTAMPS & PRICING
    hours_ago,
    datetime_tehran,
    current_price
    FROM Signals_Classification_Engine
    WHERE 1=1
    -- Explicit Filter Boundaries
    AND momentum_1h_pct >= @min_momentum
    AND rsi_value <= @max_rsi
    
    -- Interactive Execution Switch Toggles
    AND (@crossover_only = 0 OR macd_signal IN ('BULLISH_CROSSOVER', 'BEARISH_CROSSOVER'))
    AND (@signal_type = 'ALL' OR macd_signal = @signal_type)
    AND (@require_volume_verify = 0 OR real_volume_ratio >= 0.85)

ORDER BY 
    -- Master Layout Sorting Protocol
    calculated_signal_strength DESC,
    momentum_1h_pct DESC,
    real_volume_ratio DESC,
    timestamp DESC;
