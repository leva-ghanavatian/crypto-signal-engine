-- =====================================================
-- 09_bb_squeeze_duration.sql
-- =====================================================
-- PURPOSE: Find coins that have been in a squeeze for extended periods
-- =====================================================

USE db_Trading;

-- =====================================================
-- CONFIGURATION PARAMETERS
-- =====================================================

DECLARE @min_squeeze_hours INT = 10;
DECLARE @max_bandwidth_pct DECIMAL(5,2) = 10;
DECLARE @require_rising_middle INT = 0;
DECLARE @min_middle_rise_pct DECIMAL(5,2) = 0.2;
DECLARE @min_volume_ratio DECIMAL(5,2) = 0;
DECLARE @lookback_hours INT = 168;
DECLARE @symbol_filter NVARCHAR(50) = NULL;

-- =====================================================
-- TIME CALCULATIONS
-- =====================================================

DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @lookback_timestamp BIGINT = @current_time - (@lookback_hours * 60 * 60);

-- =====================================================
-- SIMPLE WORKING VERSION
-- =====================================================

WITH 
-- Step 1: Mark each candle and create group ID using gaps and islands
base_data AS (
    SELECT 
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        
        -- Bandwidth
        CASE 
            WHEN [BBM_20_2.0_2.0] > 0 
            THEN ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100
            ELSE 100
        END as bandwidth_pct,
        
        -- Is squeeze?
        CASE 
            WHEN [BBM_20_2.0_2.0] > 0 
                 AND ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100 <= @max_bandwidth_pct
            THEN 1 
            ELSE 0 
        END as is_squeeze,
        
        -- Values we need
        ROUND([close], 2) as price,
        ROUND([BBM_20_2.0_2.0], 2) as bb_middle,
        ROUND(([close] - [BBL_20_2.0_2.0]) / ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) * 100, 1) as bb_position,
        price_change_1 as momentum_1h,
        volume,
        [VWMA_20] as avg_volume,
        RSI as rsi,
        MACDh_12_26_9 as macd_histogram,
        
        -- For gaps and islands
        ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY timestamp) as rn,
        ROW_NUMBER() OVER (PARTITION BY symbol, 
            CASE 
                WHEN [BBM_20_2.0_2.0] > 0 
                     AND ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100 <= @max_bandwidth_pct
                THEN 1 ELSE 0 
            END
            ORDER BY timestamp) as rn2
            
    FROM tab_calculated_60
    WHERE timestamp >= @lookback_timestamp
        AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
),

-- Step 2: Filter to squeeze candles and create group ID
squeeze_candles AS (
    SELECT 
        *,
        (rn - rn2) as group_id
    FROM base_data
    WHERE is_squeeze = 1
),

-- Step 3: Get group statistics (min/max timestamps and averages)
group_stats AS (
    SELECT 
        symbol,
        group_id,
        MIN(timestamp) as squeeze_start,
        MAX(timestamp) as squeeze_end,
        MIN(datetime_tehran) as squeeze_start_tehran,
        MAX(datetime_tehran) as squeeze_end_tehran,
        COUNT(*) as squeeze_hours,
        AVG(bandwidth_pct) as avg_bandwidth,
        MIN(bandwidth_pct) as min_bandwidth,
        AVG(bb_position) as avg_bb_position,
        AVG(momentum_1h) as avg_momentum,
        AVG(volume * 1.0 / NULLIF(avg_volume, 0)) as avg_volume_ratio
    FROM squeeze_candles
    GROUP BY symbol, group_id
    HAVING COUNT(*) >= @min_squeeze_hours
),

-- Step 4: Get first and last candle data by joining back
first_candle AS (
    SELECT 
        gs.symbol,
        gs.group_id,
        sc.bb_middle as start_bb_middle
    FROM group_stats gs
    JOIN squeeze_candles sc 
        ON gs.symbol = sc.symbol 
        AND gs.group_id = sc.group_id
        AND gs.squeeze_start = sc.timestamp
),

last_candle AS (
    SELECT 
        gs.symbol,
        gs.group_id,
        sc.price as end_price,
        sc.bb_position as end_bb_position,
        sc.momentum_1h as end_momentum,
        sc.rsi as end_rsi,
        sc.macd_histogram as end_macd,
        sc.volume as end_volume,
        sc.avg_volume as end_avg_volume,
        sc.bb_middle as end_bb_middle
    FROM group_stats gs
    JOIN squeeze_candles sc 
        ON gs.symbol = sc.symbol 
        AND gs.group_id = sc.group_id
        AND gs.squeeze_end = sc.timestamp
),

-- Step 5: Combine everything
combined AS (
    SELECT 
        gs.*,
        fc.start_bb_middle,
        lc.end_price,
        lc.end_bb_position,
        lc.end_momentum,
        lc.end_rsi,
        lc.end_macd,
        lc.end_volume,
        lc.end_avg_volume,
        lc.end_bb_middle,
        
        -- Calculate middle band change
        CASE 
            WHEN fc.start_bb_middle > 0 
            THEN (lc.end_bb_middle - fc.start_bb_middle) / fc.start_bb_middle * 100
            ELSE 0
        END as middle_band_change_pct,
        
        -- Calculate volume ratio
        CASE WHEN lc.end_avg_volume > 0 
             THEN lc.end_volume * 1.0 / lc.end_avg_volume 
             ELSE 0 
        END as volume_ratio,
        
        -- Duration category
        CASE 
            WHEN gs.squeeze_hours >= 48 THEN 'EXTREME_LONG_SQUEEZE (48h+)'
            WHEN gs.squeeze_hours >= 24 THEN 'LONG_SQUEEZE (24-48h)'
            WHEN gs.squeeze_hours >= 10 THEN 'MEDIUM_SQUEEZE (10-24h)'
            ELSE 'SHORT_SQUEEZE'
        END as duration_category,
        
        -- Tightness category
        CASE 
            WHEN gs.avg_bandwidth < 5 THEN 'EXTREME_TIGHT'
            WHEN gs.avg_bandwidth < 7 THEN 'VERY_TIGHT'
            ELSE 'TIGHT'
        END as tightness_category,
        
        -- Most recent squeeze per symbol
        ROW_NUMBER() OVER (PARTITION BY gs.symbol ORDER BY gs.squeeze_end DESC) as rn
        
    FROM group_stats gs
    LEFT JOIN first_candle fc ON gs.symbol = fc.symbol AND gs.group_id = fc.group_id
    LEFT JOIN last_candle lc ON gs.symbol = lc.symbol AND gs.group_id = lc.group_id
)

-- Step 6: Final output
SELECT 
    symbol,
    duration_category,
    tightness_category,
    squeeze_hours,
    squeeze_start_tehran,
    squeeze_end_tehran as last_update_tehran,
    CAST((@current_time - squeeze_end) / 3600.0 AS DECIMAL(5,1)) as hours_since_last_candle,
    
    ROUND(avg_bandwidth, 2) as avg_bandwidth_pct,
    ROUND(min_bandwidth, 2) as min_bandwidth_pct,
    ROUND(end_price, 2) as current_price,
    ROUND(end_bb_position, 1) as current_bb_position_pct,
    ROUND(end_momentum, 2) as momentum_1h_pct,
    ROUND(end_rsi, 1) as current_rsi,
    ROUND(end_macd, 4) as current_macd,
    ROUND(volume_ratio, 2) as volume_ratio,
    ROUND(middle_band_change_pct, 2) as middle_band_change_pct,
    
    -- Breakout potential
    CAST(
        (CASE WHEN squeeze_hours >= 48 THEN 40
              WHEN squeeze_hours >= 24 THEN 30
              ELSE 20 END) +
        (CASE WHEN avg_bandwidth < 5 THEN 30
              WHEN avg_bandwidth < 7 THEN 20
              ELSE 10 END) +
        (CASE WHEN end_momentum > 0.5 THEN 20
              WHEN end_momentum > 0.3 THEN 15
              WHEN end_momentum > 0 THEN 10
              ELSE 0 END) +
        (CASE WHEN end_bb_position > 60 THEN 10
              WHEN end_bb_position > 55 THEN 5
              ELSE 0 END)
    AS INT) as breakout_potential

FROM combined
WHERE rn = 1
    AND (@require_rising_middle = 0 OR middle_band_change_pct >= @min_middle_rise_pct)
    AND (@min_volume_ratio <= 0 OR volume_ratio >= @min_volume_ratio)
    
ORDER BY 
    squeeze_hours DESC,
    avg_bandwidth ASC;