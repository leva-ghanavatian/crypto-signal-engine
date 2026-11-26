-- =====================================================
-- 10_divergence_detection.sql
-- =====================================================
-- PURPOSE: Detect bullish and bearish divergences between price and indicators
--
-- DIVERGENCE TYPES:
-- BULLISH DIVERGENCE: Price makes LOWER LOW, but RSI/MACD makes HIGHER LOW
--   -> Downward momentum weakening, reversal up likely
--
-- BEARISH DIVERGENCE: Price makes HIGHER HIGH, but RSI/MACD makes LOWER HIGH
--   -> Upward momentum weakening, reversal down likely
--
-- HIDDEN BULLISH DIVERGENCE: Price makes HIGHER LOW, RSI makes LOWER LOW
--   -> Trend continuation up
--
-- HIDDEN BEARISH DIVERGENCE: Price makes LOWER HIGH, RSI makes HIGHER HIGH
--   -> Trend continuation down
--
-- PARAMETERS:
-- @start_hours_ago: Beginning of time window (default: 0)
-- @end_hours_ago: End of time window (default: 72 = 3 days)
-- @min_lookback_bars: Minimum bars to look back for divergence (default: 5)
-- @max_lookback_bars: Maximum bars to look back (default: 20)
-- @indicator_type: 'RSI', 'MACD', or 'BOTH' (default: 'BOTH')
-- @divergence_type: 'REGULAR', 'HIDDEN', or 'ALL' (default: 'REGULAR')
-- @divergence_signal_filter: Filter by signal direction (default: 'ALL')
--    Options: 'ALL', 'BULLISH', 'BEARISH', 'BULLISH_REGULAR', 'BEARISH_REGULAR', 
--             'BULLISH_HIDDEN', 'BEARISH_HIDDEN'
-- @min_divergence_strength: Minimum divergence strength (default: 50, range 0-200)
-- @symbol_filter: Specific symbol filter (default: NULL)
--
-- DIVERGENCE STRENGTH GUIDE:
-- 100+: Excellent - Very strong signal, high probability reversal
-- 80-99: Strong - Good signal, take trade with confidence  
-- 60-79: Moderate - Decent signal, use smaller position size
-- 40-59: Weak - Low confidence, wait for confirmation
-- 0-39: Poor - Ignore, too weak to act on
--
-- USE CASE: Early reversal detection before price changes direction
-- SORTED BY: Strongest divergence first
-- =====================================================

USE db_Trading;

-- =====================================================
-- CONFIGURATION PARAMETERS
-- =====================================================

DECLARE @start_hours_ago INT = 0;
DECLARE @end_hours_ago INT = 72;
DECLARE @min_lookback_bars INT = 5;
DECLARE @max_lookback_bars INT = 20;
DECLARE @indicator_type VARCHAR(10) = 'BOTH';  -- 'RSI', 'MACD', 'BOTH'
DECLARE @divergence_type VARCHAR(10) = 'REGULAR';  -- 'REGULAR', 'HIDDEN', 'ALL'
DECLARE @divergence_signal_filter VARCHAR(30) = 'ALL';  -- 'ALL', 'BULLISH', 'BEARISH', 'BULLISH_REGULAR', 'BEARISH_REGULAR', 'BULLISH_HIDDEN', 'BEARISH_HIDDEN'
DECLARE @min_divergence_strength INT = 50;    -- Minimum strength (0-200, 50 = moderate)
DECLARE @symbol_filter NVARCHAR(50) = NULL;

-- =====================================================
-- CALCULATE TIME BOUNDARIES
-- =====================================================

DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 60 * 60);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 60 * 60);

-- =====================================================
-- FIND LOCAL EXTREMES AND DIVERGENCES
-- =====================================================

WITH price_data AS (
    SELECT 
        symbol,
        timestamp,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        ROUND([close], 2) as price,
        ROUND(RSI, 1) as rsi,
        ROUND(MACDh_12_26_9, 4) as macd_histogram,
        ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY timestamp) as bar_num,
        -- Price extremes (local highs and lows)
        CASE 
            WHEN [close] > LAG([close], 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                 AND [close] > LEAD([close], 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                THEN [close]
            ELSE NULL
        END as local_high,
        CASE 
            WHEN [close] < LAG([close], 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                 AND [close] < LEAD([close], 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                THEN [close]
            ELSE NULL
        END as local_low,
        -- RSI extremes
        CASE 
            WHEN RSI > LAG(RSI, 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                 AND RSI > LEAD(RSI, 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                THEN RSI
            ELSE NULL
        END as rsi_high,
        CASE 
            WHEN RSI < LAG(RSI, 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                 AND RSI < LEAD(RSI, 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                THEN RSI
            ELSE NULL
        END as rsi_low,
        -- MACD extremes
        CASE 
            WHEN MACDh_12_26_9 > LAG(MACDh_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                 AND MACDh_12_26_9 > LEAD(MACDh_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                THEN MACDh_12_26_9
            ELSE NULL
        END as macd_high,
        CASE 
            WHEN MACDh_12_26_9 < LAG(MACDh_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                 AND MACDh_12_26_9 < LEAD(MACDh_12_26_9, 1) OVER (PARTITION BY symbol ORDER BY timestamp)
                THEN MACDh_12_26_9
            ELSE NULL
        END as macd_low
    FROM tab_calculated_60
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
        AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
),
divergence_scan AS (
    SELECT 
        p1.symbol,
        p1.timestamp as signal_timestamp,
        p1.hours_ago,
        DATEADD(MINUTE, 210, DATEADD(SECOND, p1.timestamp, '1970-01-01')) as signal_time_tehran,
        p1.price as current_price,
        
        -- Previous extreme values
        p2.price as prev_price,
        p2.timestamp as prev_timestamp,
        CAST((p1.timestamp - p2.timestamp) / 3600.0 AS INT) as bars_apart,
        
        -- Price comparison
        CASE 
            WHEN p1.price < p2.price THEN 'LOWER_LOW'
            WHEN p1.price > p2.price THEN 'HIGHER_HIGH'
            ELSE 'OTHER'
        END as price_pattern,
        
        -- RSI comparison
        p1.rsi as current_rsi,
        p2.rsi as prev_rsi,
        p1.macd_histogram as current_macd,
        p2.macd_histogram as prev_macd,
        
        -- Calculate divergence conditions
        CASE 
            -- REGULAR BULLISH DIVERGENCE: Price lower low, RSI higher low
            WHEN p1.price < p2.price AND p1.rsi > p2.rsi
                THEN 'BULLISH_REGULAR'
            -- REGULAR BEARISH DIVERGENCE: Price higher high, RSI lower high
            WHEN p1.price > p2.price AND p1.rsi < p2.rsi
                THEN 'BEARISH_REGULAR'
            -- HIDDEN BULLISH DIVERGENCE: Price higher low, RSI lower low
            WHEN p1.price > p2.price AND p1.rsi < p2.rsi
                 AND p1.local_low IS NOT NULL
                THEN 'BULLISH_HIDDEN'
            -- HIDDEN BEARISH DIVERGENCE: Price lower high, RSI higher high
            WHEN p1.price < p2.price AND p1.rsi > p2.rsi
                 AND p1.local_high IS NOT NULL
                THEN 'BEARISH_HIDDEN'
            ELSE NULL
        END as rsi_divergence,
        
        -- MACD divergence (same logic)
        CASE 
            WHEN p1.price < p2.price AND p1.macd_histogram > p2.macd_histogram
                THEN 'BULLISH_REGULAR'
            WHEN p1.price > p2.price AND p1.macd_histogram < p2.macd_histogram
                THEN 'BEARISH_REGULAR'
            WHEN p1.price > p2.price AND p1.macd_histogram < p2.macd_histogram
                 AND p1.local_low IS NOT NULL
                THEN 'BULLISH_HIDDEN'
            WHEN p1.price < p2.price AND p1.macd_histogram > p2.macd_histogram
                 AND p1.local_high IS NOT NULL
                THEN 'BEARISH_HIDDEN'
            ELSE NULL
        END as macd_divergence
        
    FROM price_data p1
    JOIN price_data p2 
        ON p1.symbol = p2.symbol
        AND p1.bar_num > p2.bar_num
        AND (p1.bar_num - p2.bar_num) BETWEEN @min_lookback_bars AND @max_lookback_bars
    WHERE 
        -- Only consider price extremes
        (p1.local_high IS NOT NULL OR p1.local_low IS NOT NULL)
        AND (p2.local_high IS NOT NULL OR p2.local_low IS NOT NULL)
),
strength_calculated AS (
    SELECT 
        *,
        -- Calculate divergence strength
        CASE 
            WHEN rsi_divergence IN ('BULLISH_REGULAR', 'BEARISH_REGULAR') THEN 
                CAST(ABS((current_price - prev_price) / prev_price * 100) + 
                     ABS(current_rsi - prev_rsi) AS INT)
            WHEN macd_divergence IN ('BULLISH_REGULAR', 'BEARISH_REGULAR') THEN
                CAST(ABS((current_price - prev_price) / prev_price * 100) * 2 AS INT)
            ELSE 50
        END as divergence_strength,
        
        -- Determine which divergence to use as primary
        CASE 
            WHEN @indicator_type IN ('RSI', 'BOTH') AND rsi_divergence IS NOT NULL
                AND @divergence_type IN ('ALL', 
                    CASE WHEN rsi_divergence LIKE '%REGULAR' THEN 'REGULAR' ELSE 'HIDDEN' END)
                THEN rsi_divergence
            WHEN @indicator_type IN ('MACD', 'BOTH') AND macd_divergence IS NOT NULL
                AND @divergence_type IN ('ALL',
                    CASE WHEN macd_divergence LIKE '%REGULAR' THEN 'REGULAR' ELSE 'HIDDEN' END)
                THEN macd_divergence
            ELSE 'NO_DIVERGENCE'
        END as divergence_signal
        
    FROM divergence_scan
)
SELECT 
    symbol,
    hours_ago,
    signal_time_tehran,
    bars_apart,
    current_price,
    prev_price,
    ROUND(ABS((current_price - prev_price) / prev_price * 100), 2) as price_change_pct,
    
    -- RSI Divergence
    rsi_divergence,
    current_rsi,
    prev_rsi,
    ROUND(ABS(current_rsi - prev_rsi), 1) as rsi_change,
    
    -- MACD Divergence
    macd_divergence,
    ROUND(current_macd, 4) as current_macd,
    ROUND(prev_macd, 4) as prev_macd,
    ROUND(ABS(current_macd - prev_macd), 4) as macd_change,
    
    -- Strength and Signal
    divergence_strength,
    CASE 
        WHEN divergence_strength >= 100 THEN 'EXCELLENT'
        WHEN divergence_strength >= 80 THEN 'STRONG'
        WHEN divergence_strength >= 60 THEN 'MODERATE'
        WHEN divergence_strength >= 40 THEN 'WEAK'
        ELSE 'POOR'
    END as strength_category,
    divergence_signal,
    
    -- Actionable Recommendation
    CASE 
        WHEN divergence_signal IN ('BULLISH_REGULAR', 'BULLISH_HIDDEN') 
             AND divergence_strength >= 80 THEN 'STRONG_BUY'
        WHEN divergence_signal IN ('BULLISH_REGULAR', 'BULLISH_HIDDEN') 
             AND divergence_strength >= 60 THEN 'BUY'
        WHEN divergence_signal IN ('BEARISH_REGULAR', 'BEARISH_HIDDEN') 
             AND divergence_strength >= 80 THEN 'STRONG_SELL'
        WHEN divergence_signal IN ('BEARISH_REGULAR', 'BEARISH_HIDDEN') 
             AND divergence_strength >= 60 THEN 'SELL'
        WHEN divergence_signal IN ('BULLISH_REGULAR', 'BULLISH_HIDDEN') THEN 'WATCH_BUY'
        WHEN divergence_signal IN ('BEARISH_REGULAR', 'BEARISH_HIDDEN') THEN 'WATCH_SELL'
        ELSE 'NO_ACTION'
    END as recommendation

FROM strength_calculated
WHERE 1=1
    AND (rsi_divergence IS NOT NULL OR macd_divergence IS NOT NULL)
    AND divergence_strength >= @min_divergence_strength
    -- Divergence signal filter
    AND (
        @divergence_signal_filter = 'ALL' 
        OR (@divergence_signal_filter = 'BULLISH' AND divergence_signal IN ('BULLISH_REGULAR', 'BULLISH_HIDDEN'))
        OR (@divergence_signal_filter = 'BEARISH' AND divergence_signal IN ('BEARISH_REGULAR', 'BEARISH_HIDDEN'))
        OR divergence_signal = @divergence_signal_filter
    )
ORDER BY 
    divergence_strength DESC,
    bars_apart ASC,
    signal_time_tehran DESC;