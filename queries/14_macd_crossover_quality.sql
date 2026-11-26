-- =====================================================
-- 14_macd_crossover_quality.sql
-- =====================================================
-- PURPOSE: Distinguish between HIGH QUALITY and LOW QUALITY MACD crossovers
--          based on slope, separation angle, and momentum
--
-- KEY INSIGHT: A crossover with HIGH SLOPE (line cuts sharply through)
--              is much more reliable than lines that just touch
--
-- CROSSOVER TYPES:
-- STRONG_BULLISH: Sharp slope, high momentum, good volume
-- WEAK_BULLISH: Low slope, lines barely cross, low momentum
-- STRONG_BEARISH: Sharp downward slope
-- WEAK_BEARISH: Weak downward crossover
-- =====================================================

USE db_Trading;

-- =====================================================
-- CONFIGURATION PARAMETERS
-- =====================================================

DECLARE @start_hours_ago INT = 0;
DECLARE @end_hours_ago INT = 24;                  -- Last 72 hours
DECLARE @min_slope_for_strong DECIMAL(10,4) = 0.10;  -- Min slope for "strong" (0.10 = 10% per hour)
DECLARE @min_histogram_increase DECIMAL(10,4) = 0.02; -- Min histogram jump
DECLARE @symbol_filter NVARCHAR(50) = NULL;

-- =====================================================
-- TIME CALCULATIONS
-- =====================================================

DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 60 * 60);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 60 * 60);

-- =====================================================
-- MAIN QUERY
-- =====================================================

WITH 
-- Step 1: Get MACD data with historical values
macd_with_history AS (
    SELECT 
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        
        -- MACD components
        ROUND(MACD_12_26_9, 4) as macd_line,
        ROUND(MACDs_12_26_9, 4) as signal_line,
        ROUND(MACDh_12_26_9, 4) as histogram,
        
        -- Previous values (1 hour and 2 hours ago)
        LAG(ROUND(MACD_12_26_9, 4)) OVER (PARTITION BY symbol ORDER BY timestamp) as prev_macd,
        LAG(ROUND(MACD_12_26_9, 4), 2) OVER (PARTITION BY symbol ORDER BY timestamp) as prev2_macd,
        LAG(ROUND(MACDs_12_26_9, 4)) OVER (PARTITION BY symbol ORDER BY timestamp) as prev_signal,
        LAG(ROUND(MACDs_12_26_9, 4), 2) OVER (PARTITION BY symbol ORDER BY timestamp) as prev2_signal,
        LAG(ROUND(MACDh_12_26_9, 4)) OVER (PARTITION BY symbol ORDER BY timestamp) as prev_histogram,
        
        -- Price and confirmation data
        ROUND([close], 2) as price,
        ROUND(price_change_1, 2) as momentum_1h,
        ROUND(price_change_2, 2) as momentum_2h,
        ROUND(volume, 0) as volume,
        ROUND(VWMA_20, 0) as avg_volume,
        ROUND(RSI, 1) as rsi,
        ROUND(OBV, 0) as obv
        
    FROM tab_calculated_60
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
        AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
),

-- Step 2: Calculate slope and crossover characteristics
crossover_analysis AS (
    SELECT 
        *,
        
        -- =====================================================
        -- SLOPE CALCULATIONS (How steep is the crossover?)
        -- =====================================================
        -- Slope of MACD line (how fast it's rising/falling)
        CASE 
            WHEN prev_macd != 0 
            THEN (macd_line - prev_macd) / ABS(prev_macd) * 100
            ELSE 0
        END as macd_slope_pct,
        
        -- Slope of Signal line
        CASE 
            WHEN prev_signal != 0 
            THEN (signal_line - prev_signal) / ABS(prev_signal) * 100
            ELSE 0
        END as signal_slope_pct,
        
        -- The GAP between lines after crossover (how far apart they are)
        ABS(macd_line - signal_line) as line_separation,
        
        -- How much the histogram increased/decreased
        (histogram - prev_histogram) as histogram_change,
        
        -- =====================================================
        -- CROSSOVER DETECTION
        -- =====================================================
        CASE 
            WHEN prev_macd <= prev_signal AND macd_line > signal_line 
                THEN 'BULLISH_CROSSOVER'
            WHEN prev_macd >= prev_signal AND macd_line < signal_line 
                THEN 'BEARISH_CROSSOVER'
            ELSE 'NO_CROSSOVER'
        END as crossover_type
        
    FROM macd_with_history
),

-- Step 3: Classify crossover quality
quality_classified AS (
    SELECT 
        *,
        
        -- =====================================================
        -- QUALITY CLASSIFICATION (Strong vs Weak)
        -- =====================================================
        CASE 
            -- BULLISH CROSSOVER QUALITY
            WHEN crossover_type = 'BULLISH_CROSSOVER' THEN
                CASE 
                    -- STRONG BULLISH: High slope + good separation + volume confirmation
                    WHEN macd_slope_pct >= @min_slope_for_strong 
                         AND line_separation > 0.05
                         AND histogram_change > @min_histogram_increase
                         AND momentum_1h > 0.5
                        THEN 'STRONG_BULLISH'
                    
                    -- MEDIUM BULLISH: Decent slope but missing some confirmations
                    WHEN macd_slope_pct >= (@min_slope_for_strong * 0.6)
                         AND momentum_1h > 0
                        THEN 'MEDIUM_BULLISH'
                    
                    -- WEAK BULLISH: Barely crossing, low slope
                    WHEN macd_slope_pct < (@min_slope_for_strong * 0.5)
                         AND line_separation < 0.02
                        THEN 'WEAK_BULLISH'
                    
                    ELSE 'BULLISH_CROSSOVER'
                END
            
            -- BEARISH CROSSOVER QUALITY  
            WHEN crossover_type = 'BEARISH_CROSSOVER' THEN
                CASE 
                    -- STRONG BEARISH: Steep downward slope
                    WHEN macd_slope_pct <= -@min_slope_for_strong 
                         AND line_separation > 0.05
                         AND histogram_change < -@min_histogram_increase
                         AND momentum_1h < -0.5
                        THEN 'STRONG_BEARISH'
                    
                    WHEN macd_slope_pct <= -(@min_slope_for_strong * 0.6)
                         AND momentum_1h < 0
                        THEN 'MEDIUM_BEARISH'
                    
                    WHEN macd_slope_pct > -(@min_slope_for_strong * 0.5)
                         AND line_separation < 0.02
                        THEN 'WEAK_BEARISH'
                    
                    ELSE 'BEARISH_CROSSOVER'
                END
            
            ELSE 'NO_CROSSOVER'
        END as crossover_quality,
        
        -- =====================================================
        -- VISUAL REPRESENTATION (Like your picture)
        -- =====================================================
        CASE 
            WHEN crossover_type = 'BULLISH_CROSSOVER' THEN
                CASE 
                    WHEN macd_slope_pct >= 0.15 
                        THEN 'SHARP BULLISH CROSSOVER (Blue line CUTS through Orange)'
                    WHEN macd_slope_pct >= 0.08 
                        THEN 'MODERATE BULLISH CROSSOVER'
                    ELSE 'WEAK BULLISH CROSSOVER (Lines barely touch)'
                END
            WHEN crossover_type = 'BEARISH_CROSSOVER' THEN
                CASE 
                    WHEN macd_slope_pct <= -0.15 
                        THEN 'SHARP BEARISH CROSSOVER'
                    WHEN macd_slope_pct <= -0.08 
                        THEN 'MODERATE BEARISH CROSSOVER'
                    ELSE 'WEAK BEARISH CROSSOVER'
                END
            ELSE 'NO CROSSOVER'
        END as visual_signal,
        
        -- =====================================================
        -- RECOMMENDATION
        -- =====================================================
        CASE 
            WHEN crossover_type = 'BULLISH_CROSSOVER' THEN
                CASE 
                    WHEN macd_slope_pct >= @min_slope_for_strong 
                         AND line_separation > 0.05
                         AND histogram_change > @min_histogram_increase
                         AND momentum_1h > 0.5
                        THEN 'BUY - Strong, sharp crossover with momentum'
                    WHEN macd_slope_pct >= (@min_slope_for_strong * 0.6)
                         AND momentum_1h > 0
                        THEN 'CONSIDER BUY - Moderate crossover, wait for confirmation'
                    WHEN macd_slope_pct < (@min_slope_for_strong * 0.5)
                         AND line_separation < 0.02
                        THEN 'AVOID - Weak crossover, may be false signal'
                    ELSE 'HOLD - Monitor for confirmation'
                END
            WHEN crossover_type = 'BEARISH_CROSSOVER' THEN
                CASE 
                    WHEN macd_slope_pct <= -@min_slope_for_strong 
                         AND line_separation > 0.05
                         AND histogram_change < -@min_histogram_increase
                         AND momentum_1h < -0.5
                        THEN 'SELL - Strong bearish crossover detected'
                    WHEN macd_slope_pct <= -(@min_slope_for_strong * 0.6)
                         AND momentum_1h < 0
                        THEN 'CONSIDER EXIT - Bearish signal developing'
                    WHEN macd_slope_pct > -(@min_slope_for_strong * 0.5)
                         AND line_separation < 0.02
                        THEN 'MONITOR - Weak bearish signal'
                    ELSE 'WATCH - Bearish crossover detected'
                END
            ELSE 'NO ACTION'
        END as recommendation,
        
        -- =====================================================
        -- SLOPE CATEGORY
        -- =====================================================
        CASE 
            WHEN macd_slope_pct >= 0.15 OR macd_slope_pct <= -0.15 
                THEN 'HIGH_SLOPE - Like your picture!'
            WHEN macd_slope_pct >= 0.08 OR macd_slope_pct <= -0.08 
                THEN 'MEDIUM_SLOPE'
            ELSE 'LOW_SLOPE - Lines barely crossed'
        END as slope_category,
        
        -- =====================================================
        -- ENTRY SIGNAL
        -- =====================================================
        CASE 
            WHEN crossover_type = 'BULLISH_CROSSOVER'
                 AND (macd_slope_pct >= @min_slope_for_strong OR macd_slope_pct >= 0.10)
                THEN 'ENTRY SIGNAL - Sharp crossover confirms momentum'
            WHEN crossover_type = 'BULLISH_CROSSOVER'
                 AND macd_slope_pct < (@min_slope_for_strong * 0.6)
                THEN 'NO ENTRY - Wait for sharper crossover'
            ELSE 'NOT_APPLICABLE'
        END as entry_signal
        
    FROM crossover_analysis
)

-- Step 4: Final output - Only show crossovers
SELECT 
    symbol,
    datetime_tehran,
    hours_ago,
    
    -- Crossover information
    crossover_type,
    crossover_quality,
    visual_signal,
    recommendation,
    
    -- MACD Values
    ROUND(macd_line, 4) as macd_line,
    ROUND(signal_line, 4) as signal_line,
    ROUND(histogram, 4) as histogram,
    
    -- Slope metrics (How sharp was the crossover?)
    ROUND(macd_slope_pct, 2) as macd_slope_pct,
    ROUND(line_separation, 4) as line_separation,
    ROUND(histogram_change, 4) as histogram_change,
    
    -- Price and momentum
    price,
    ROUND(momentum_1h, 2) as momentum_1h_pct,
    ROUND(momentum_2h, 2) as momentum_2h_pct,
    rsi,
    
    -- Volume confirmation
    volume,
    ROUND(avg_volume, 0) as avg_volume,
    CASE WHEN avg_volume > 0 THEN ROUND(volume * 1.0 / avg_volume, 2) ELSE 0 END as volume_ratio,
    
    -- The key metrics you asked for
    slope_category,
    entry_signal

FROM quality_classified
WHERE crossover_type != 'NO_CROSSOVER'  -- Only show crossovers
    
ORDER BY 
    -- Order by quality (Strongest first)
    CASE crossover_quality
        WHEN 'STRONG_BULLISH' THEN 1
        WHEN 'MEDIUM_BULLISH' THEN 2
        WHEN 'STRONG_BEARISH' THEN 3
        WHEN 'MEDIUM_BEARISH' THEN 4
        WHEN 'WEAK_BULLISH' THEN 5
        WHEN 'WEAK_BEARISH' THEN 6
        ELSE 7
    END ASC,
    ABS(macd_slope_pct) DESC;  -- Highest slope first