USE db_Trading;
GO

-- ---------------------------------------------------------------------------------
-- 1. CONFIGURATION PARAMETERS (Variables)
-- ---------------------------------------------------------------------------------
DECLARE @start_hours_ago INT = 0;              -- 0 = Most recent data
DECLARE @end_hours_ago INT = 48;               -- Active screening window depth
DECLARE @symbol_filter NVARCHAR(50) = NULL;    -- Specific asset or NULL

-- Divergence Parameter Settings
DECLARE @pivot_strength INT = 3;               -- Left/Right bars check to confirm a true swing pivot
DECLARE @max_lookback_bars INT = 24;           -- Maximum distance allowed between two pivots
DECLARE @min_divergence_strength INT = 55;     -- Lower filter cutoff boundary for scores

-- Strategy Filters
DECLARE @divergence_direction NVARCHAR(20) = 'BULLISH'; -- 'BULLISH', 'BEARISH', 'ALL'
DECLARE @divergence_class NVARCHAR(20) = 'ALL';         -- 'REGULAR', 'HIDDEN', 'ALL'

-- ---------------------------------------------------------------------------------
-- 2. TIME ENGINE CALCULATION & TIMELINE BUFFER SEPARATION
-- ---------------------------------------------------------------------------------
DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 3600);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 3600);

-- Allocate deep history buffer to process lookback windows and structural pivots safely
DECLARE @buffer_timestamp BIGINT = @end_timestamp - (24 * 3600 * 4);

-- ---------------------------------------------------------------------------------
-- 3. DYNAMIC SQL TO OVERCOME ROWS LIMITATION WITH VARIABLES
-- ---------------------------------------------------------------------------------
DECLARE @sql NVARCHAR(MAX);

SET @sql = N'
WITH Base_Market_Data AS (
    SELECT 
        symbol,
        timestamp,
        [close],
        high,
        low,
        volume,
        ROUND(RSI, 2) as rsi,
        ROUND(MACDh_12_26_9, 4) as macd_hist,
        price_change_1,
        
        -- Rolling true volume average baseline
        AVG(volume) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) as true_volume_sma_20,

        -- Windowed elements to locate true local structural peaks and valleys
        MIN(low) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN ' + CAST(@pivot_strength AS NVARCHAR(10)) + N' PRECEDING AND ' + CAST(@pivot_strength AS NVARCHAR(10)) + N' FOLLOWING) as window_low,
        MAX(high) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN ' + CAST(@pivot_strength AS NVARCHAR(10)) + N' PRECEDING AND ' + CAST(@pivot_strength AS NVARCHAR(10)) + N' FOLLOWING) as window_high,
        
        MIN(RSI) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN ' + CAST(@pivot_strength AS NVARCHAR(10)) + N' PRECEDING AND ' + CAST(@pivot_strength AS NVARCHAR(10)) + N' FOLLOWING) as window_rsi_low,
        MAX(RSI) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN ' + CAST(@pivot_strength AS NVARCHAR(10)) + N' PRECEDING AND ' + CAST(@pivot_strength AS NVARCHAR(10)) + N' FOLLOWING) as window_rsi_high
    FROM tab_calculated_60
    WHERE timestamp >= @buffer_timestamp
),

Pivot_Registry AS (
    SELECT 
        *,
        CASE WHEN low = window_low THEN 1 ELSE 0 END as is_swing_low,
        CASE WHEN high = window_high THEN 1 ELSE 0 END as is_swing_high
    FROM Base_Market_Data
),

Historical_Pivot_Bridge AS (
    SELECT 
        p.*,
        LAG(low, 1) OVER (PARTITION BY symbol, is_swing_low ORDER BY timestamp ASC) as prev_pivot_low,
        LAG(rsi, 1) OVER (PARTITION BY symbol, is_swing_low ORDER BY timestamp ASC) as prev_pivot_low_rsi,
        LAG(macd_hist, 1) OVER (PARTITION BY symbol, is_swing_low ORDER BY timestamp ASC) as prev_pivot_low_macd,
        LAG(timestamp, 1) OVER (PARTITION BY symbol, is_swing_low ORDER BY timestamp ASC) as prev_low_pivot_timestamp,

        LAG(high, 1) OVER (PARTITION BY symbol, is_swing_high ORDER BY timestamp ASC) as prev_pivot_high,
        LAG(rsi, 1) OVER (PARTITION BY symbol, is_swing_high ORDER BY timestamp ASC) as prev_pivot_high_rsi,
        LAG(macd_hist, 1) OVER (PARTITION BY symbol, is_swing_high ORDER BY timestamp ASC) as prev_pivot_high_macd,
        LAG(timestamp, 1) OVER (PARTITION BY symbol, is_swing_high ORDER BY timestamp ASC) as prev_high_pivot_timestamp
    FROM Pivot_Registry p
),

Divergence_Classifier_Engine AS (
    SELECT 
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, ''1970-01-01'')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        [close] as current_price,
        price_change_1 as momentum_1h_pct,
        rsi as current_rsi,
        macd_hist as current_macd_hist,
        CASE WHEN true_volume_sma_20 > 0 THEN ROUND(volume / true_volume_sma_20, 2) ELSE 0 END as real_volume_ratio,

        CASE 
            WHEN is_swing_low = 1 AND low < prev_pivot_low AND (rsi > prev_pivot_low_rsi OR macd_hist > prev_pivot_low_macd)
                 AND (timestamp - prev_low_pivot_timestamp) / 3600 <= @max_lookback_bars THEN ''REGULAR_BULLISH''
            WHEN is_swing_low = 1 AND low > prev_pivot_low AND (rsi < prev_pivot_low_rsi OR macd_hist < prev_pivot_low_macd)
                 AND (timestamp - prev_low_pivot_timestamp) / 3600 <= @max_lookback_bars THEN ''HIDDEN_BULLISH''
            WHEN is_swing_high = 1 AND high > prev_pivot_high AND (rsi < prev_pivot_high_rsi OR macd_hist < prev_pivot_high_macd)
                 AND (timestamp - prev_high_pivot_timestamp) / 3600 <= @max_lookback_bars THEN ''REGULAR_BEARISH''
            WHEN is_swing_high = 1 AND high < prev_pivot_high AND (rsi > prev_pivot_high_rsi OR macd_hist > prev_pivot_high_macd)
                 AND (timestamp - prev_high_pivot_timestamp) / 3600 <= @max_lookback_bars THEN ''HIDDEN_BEARISH''
            ELSE ''NO_DIVERGENCE''
        END as detected_divergence,

        CASE 
            WHEN rsi > prev_pivot_low_rsi AND rsi < prev_pivot_high_rsi THEN ''RSI''
            WHEN macd_hist > prev_pivot_low_macd AND macd_hist < prev_pivot_high_macd THEN ''MACD''
            ELSE ''BOTH''
        END as primary_indicator_source,

        CASE 
            WHEN is_swing_low = 1 THEN CAST((timestamp - prev_low_pivot_timestamp) / 3600 AS INT)
            WHEN is_swing_high = 1 THEN CAST((timestamp - prev_high_pivot_timestamp) / 3600 AS INT)
            ELSE 0 
        END as pivot_distance_bars
    FROM Historical_Pivot_Bridge
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
),

Scored_Divergence_Matrix AS (
    SELECT 
        *,
        CAST(
            (CASE WHEN detected_divergence IN (''REGULAR_BULLISH'', ''REGULAR_BEARISH'') THEN 45 ELSE 35 END) +
            (CASE WHEN primary_indicator_source = ''BOTH'' THEN 25 ELSE 10 END) +
            (CASE WHEN pivot_distance_bars BETWEEN 6 AND 18 THEN 20 
                  WHEN pivot_distance_bars > 0 THEN 10 ELSE 0 END) +
            (CASE WHEN real_volume_ratio >= 1.4 AND detected_divergence LIKE ''%BULLISH'' THEN 10 ELSE 0 END)
        AS INT) as divergence_confidence_score
    FROM Divergence_Classifier_Engine
    WHERE detected_divergence <> ''NO_DIVERGENCE''
)

SELECT 
    divergence_confidence_score,
    symbol,
    detected_divergence as divergence_signal,
    
    tactical_action = CASE 
        WHEN detected_divergence = ''REGULAR_BULLISH'' AND divergence_confidence_score >= 75 THEN ''STRONG_BUY_REVERSAL''
        WHEN detected_divergence = ''HIDDEN_BULLISH'' AND divergence_confidence_score >= 65 THEN ''BUY_TREND_CONTINUATION''
        WHEN detected_divergence = ''REGULAR_BEARISH'' AND divergence_confidence_score >= 75 THEN ''STRONG_SHORT_REVERSAL''
        WHEN detected_divergence LIKE ''%BULLISH'' THEN ''TACTICAL_LONGS_WATCH''
        ELSE ''TACTICAL_SHORTS_WATCH''
    END,

    pivot_distance_bars as anchor_distance_hours,
    primary_indicator_source as verification_source,
    
    momentum_1h_pct,
    real_volume_ratio,
    current_rsi,
    current_macd_hist,
    
    hours_ago,
    datetime_tehran,
    current_price
FROM Scored_Divergence_Matrix
WHERE 1=1
    AND divergence_confidence_score >= @min_divergence_strength
    
    AND (@divergence_direction = ''ALL'' 
         OR (@divergence_direction = ''BULLISH'' AND detected_divergence LIKE ''%BULLISH'')
         OR (@divergence_direction = ''BEARISH'' AND detected_divergence LIKE ''%BEARISH''))
         
    AND (@divergence_class = ''ALL''
         OR (@divergence_class = ''REGULAR'' AND detected_divergence LIKE ''REGULAR%'')
         OR (@divergence_class = ''HIDDEN'' AND detected_divergence LIKE ''HIDDEN%''))
         
    AND (@symbol_filter IS NULL OR symbol = @symbol_filter)

ORDER BY 
    divergence_confidence_score DESC,
    pivot_distance_bars ASC,
    timestamp DESC;
';

-- Execute the dynamic SQL, passing all necessary variables as parameters
EXEC sp_executesql @sql,
    N'@buffer_timestamp BIGINT, @current_time BIGINT, @start_timestamp BIGINT, @end_timestamp BIGINT,
      @max_lookback_bars INT, @min_divergence_strength INT,
      @divergence_direction NVARCHAR(20), @divergence_class NVARCHAR(20), @symbol_filter NVARCHAR(50)',
    @buffer_timestamp, @current_time, @start_timestamp, @end_timestamp,
    @max_lookback_bars, @min_divergence_strength,
    @divergence_direction, @divergence_class, @symbol_filter;