-- =====================================================
-- 05_macd_analysis.sql
-- =====================================================
-- PURPOSE: Detect MACD crossovers and analyze trend changes
--
-- PARAMETERS:
-- @start_hours_ago: Beginning of time window (default: 0 = most recent)
-- @end_hours_ago: End of time window (default: 24 = 24 hours back)
-- @crossover_only: Show only crossovers vs all signals (default: 0 = all signals)
-- @min_momentum: Minimum 1h price change percentage (default: 0, disabled)
-- @max_rsi: Maximum RSI value (default: 100, disabled)
-- @signal_type: Filter by signal type (default: 'ALL')
--               Options: 'BULLISH_CROSSOVER', 'BEARISH_CROSSOVER', 'BULLISH', 'BEARISH', 'ALL'
-- @symbol_filter: Specific symbol filter (default: NULL = all symbols)
--
-- CROSSOVER MEANINGS:
-- BULLISH CROSSOVER: MACD crosses ABOVE Signal line -> Price likely INCREASE -> BUY signal
-- BEARISH CROSSOVER: MACD crosses BELOW Signal line -> Price likely DECREASE -> SELL signal
-- BULLISH TERRITORY: MACD above Signal line -> Uptrend continuing -> HOLD
-- BEARISH TERRITORY: MACD below Signal line -> Downtrend continuing -> WAIT
--
-- USE CASE: Identifying trend changes via MACD crossovers
-- SORTED BY: Most recent signals first
-- =====================================================

USE db_Trading;

-- =====================================================
-- CONFIGURATION PARAMETERS (EDIT THESE VALUES)
-- =====================================================

DECLARE @start_hours_ago INT = 0;           -- 0 = most recent candle
DECLARE @end_hours_ago INT = 6;            -- 24 = last 24 hours
DECLARE @crossover_only INT = 0;            -- 1 = crossovers only, 0 = all signals
DECLARE @min_momentum DECIMAL(5,2) = 2;     -- Minimum 1h price change % (0 = disabled)
DECLARE @max_rsi DECIMAL(5,2) = 65;        -- Maximum RSI value (100 = disabled)
DECLARE @signal_type NVARCHAR(30) = 'ALL';  -- 'ALL', 'BULLISH_CROSSOVER', 'BEARISH_CROSSOVER', 'BULLISH', 'BEARISH'
DECLARE @symbol_filter NVARCHAR(50) = NULL; -- NULL = all symbols, or 'BTCIRT'

-- =====================================================
-- CALCULATE TIME BOUNDARIES
-- =====================================================

DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 60 * 60);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 60 * 60);

-- =====================================================
-- MAIN QUERY
-- =====================================================

WITH macd_analysis AS (
    SELECT 
        -- Basic info
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        
        -- Price data
        ROUND([close], 2) as price,
        ROUND(price_change_1, 2) as momentum_1h_pct,
        
        -- MACD values
        ROUND(MACD_12_26_9, 4) as macd_line,
        ROUND(MACDs_12_26_9, 4) as signal_line,
        ROUND(MACDh_12_26_9, 4) as histogram,
        
        -- Previous values for crossover detection
        LAG(MACD_12_26_9) OVER (PARTITION BY symbol ORDER BY timestamp) as prev_macd,
        LAG(MACDs_12_26_9) OVER (PARTITION BY symbol ORDER BY timestamp) as prev_signal,
        
        -- Additional indicators
        ROUND(RSI, 1) as rsi,
        ROUND(volume, 0) as volume,
        ROUND(VWMA_20, 0) as avg_volume,
        
        -- Histogram previous for trend detection
        LAG(MACDh_12_26_9) OVER (PARTITION BY symbol ORDER BY timestamp) as prev_histogram

    FROM tab_calculated_60
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
        AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
),

signals_classified AS (
    SELECT 
        *,
        
        -- =====================================================
        -- MACD SIGNAL CLASSIFICATION
        -- =====================================================
        CASE 
            WHEN prev_macd <= prev_signal AND macd_line > signal_line 
                THEN 'BULLISH_CROSSOVER'
            WHEN prev_macd >= prev_signal AND macd_line < signal_line 
                THEN 'BEARISH_CROSSOVER'
            WHEN macd_line > signal_line AND histogram > 0 
                THEN 'BULLISH_TERRITORY'
            WHEN macd_line < signal_line AND histogram < 0 
                THEN 'BEARISH_TERRITORY'
            ELSE 'NEUTRAL'
        END as macd_signal,
        
        -- =====================================================
        -- PREDICTED DIRECTION
        -- =====================================================
        CASE 
            WHEN prev_macd <= prev_signal AND macd_line > signal_line 
                THEN 'UP'
            WHEN prev_macd >= prev_signal AND macd_line < signal_line 
                THEN 'DOWN'
            WHEN macd_line > signal_line 
                THEN 'UP'
            WHEN macd_line < signal_line 
                THEN 'DOWN'
            ELSE 'SIDEWAYS'
        END as predicted_direction,
        
        -- =====================================================
        -- SIGNAL STRENGTH (0-100 scale)
        -- =====================================================
        CASE 
            -- Strongest: Bullish crossover with positive momentum
            WHEN prev_macd <= prev_signal AND macd_line > signal_line 
                 AND momentum_1h_pct > 1 AND histogram > 0 
                THEN 95
            -- Strong: Bullish crossover
            WHEN prev_macd <= prev_signal AND macd_line > signal_line 
                THEN 80
            -- Bearish crossover
            WHEN prev_macd >= prev_signal AND macd_line < signal_line 
                THEN 80
            -- Bullish territory with momentum
            WHEN macd_line > signal_line AND momentum_1h_pct > 0.5 
                THEN 70
            -- Bullish territory only
            WHEN macd_line > signal_line 
                THEN 60
            -- Bearish territory
            WHEN macd_line < signal_line 
                THEN 40
            ELSE 50
        END as signal_strength,
        
        -- =====================================================
        -- CONFIRMATION LEVEL
        -- =====================================================
        CASE 
            WHEN momentum_1h_pct > 1.5 AND histogram > 0 
                THEN 'STRONG_CONFIRMATION'
            WHEN momentum_1h_pct > 0.5 AND histogram > 0 
                THEN 'WEAK_CONFIRMATION'
            WHEN momentum_1h_pct < 0 AND histogram > 0 
                THEN 'DIVERGENCE_WARNING'
            WHEN momentum_1h_pct > 0.5 AND histogram < 0 
                THEN 'DIVERGENCE_WARNING'
            WHEN (prev_macd <= prev_signal AND macd_line > signal_line)
              OR (prev_macd >= prev_signal AND macd_line < signal_line)
                THEN 'CROSSOVER_DETECTED'
            ELSE 'NEEDS_CONFIRMATION'
        END as confirmation_level,
        
        -- =====================================================
        -- HISTOGRAM TREND (getting stronger or weaker)
        -- =====================================================
        CASE 
            WHEN prev_histogram IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN histogram > prev_histogram THEN 'STRENGTHENING'
            WHEN histogram < prev_histogram THEN 'WEAKENING'
            ELSE 'STABLE'
        END as histogram_trend

    FROM macd_analysis
)

-- =====================================================
-- FINAL SELECT
-- =====================================================
SELECT 
    -- Identification
    symbol,
    hours_ago,
    datetime_tehran,
    --price,
    
    -- MACD values
    --macd_line,
    --signal_line,
    --histogram,
    --histogram_trend,
    
    -- Signal interpretation
    macd_signal,
    predicted_direction,
    signal_strength,
    confirmation_level,
    
    -- Confirmation indicators
    rsi,
    momentum_1h_pct,
    
    -- Volume data
    volume,
    avg_volume,
    CASE 
        WHEN avg_volume > 0 THEN ROUND(volume / avg_volume, 2)
        ELSE 0
    END as volume_ratio

FROM signals_classified
WHERE 1=1
    -- Filter by crossover only if requested
    AND (@crossover_only = 0 OR macd_signal IN ('BULLISH_CROSSOVER', 'BEARISH_CROSSOVER'))
    -- Filter by momentum
    AND momentum_1h_pct >= @min_momentum
    -- Filter by RSI
    AND rsi <= @max_rsi
    -- Filter by signal type
    AND (@signal_type = 'ALL' OR macd_signal = @signal_type)

ORDER BY 
    -- Strongest signals first, then most recent
    --hours_ago asc,
    signal_strength DESC,
    timestamp DESC;