-- =================================================================================
-- 09_bb_squeeze_duration.sql (Refactored & Algorithmically Enhanced)
-- =================================================================================
-- PURPOSE: Identifies assets locked in prolonged compression states (islands)
-- AND detects high-velocity breakouts immediately following a squeeze.
-- =================================================================================

USE db_Trading;
GO

-- ---------------------------------------------------------------------------------
-- 1. CONFIGURATION PARAMETERS (Variables)
-- ---------------------------------------------------------------------------------
DECLARE @min_squeeze_hours INT = 10; -- Minimum consecutive hours to define an island
DECLARE @max_bandwidth_pct DECIMAL(5,2) = 8.50; -- Lowered to 8.5% for tighter, premium setups
DECLARE @require_rising_middle INT = 0; -- 1 = Requires upward structural drift
DECLARE @min_middle_rise_pct DECIMAL(5,2) = 0.20;
DECLARE @min_volume_ratio DECIMAL(5,2) = 1.20; -- Minimum volume vs baseline to validate breakouts
DECLARE @lookback_hours INT = 168; -- Lookback window (1 week)
DECLARE @symbol_filter NVARCHAR(50) = NULL; -- Specific asset filter or NULL

-- Strategy Selection Toggles
DECLARE @scan_mode NVARCHAR(20) = 'ALL'; -- 'ALL', 'ACTIVE_SQUEEZE', 'FRESH_BREAKOUT'
DECLARE @max_hours_since_exit INT = 4; -- Max window to capture a breakout after compression ends

-- ---------------------------------------------------------------------------------
-- 2. TIME ENGINE CALCULATION
-- ---------------------------------------------------------------------------------
DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @lookback_timestamp BIGINT = @current_time - (@lookback_hours * 3600);

-- ---------------------------------------------------------------------------------
-- 3. CORE PROCESSING PIPELINE
-- ---------------------------------------------------------------------------------
WITH Base_Calculated_Data AS (
    SELECT 
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        ROUND([close], 2) as price,
        ROUND([BBM_20_2.0_2.0], 2) as bb_middle,
        volume,
        RSI as rsi,
        MACDh_12_26_9 as macd_histogram,
        price_change_1,

        -- Corrected Mathematical Bandwidth Calculation
        CASE 
            WHEN [BBM_20_2.0_2.0] > 0 
            THEN ROUND(([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100, 2)
            ELSE 100.00
        END as bandwidth_pct,
        
        -- Clean, isolated Volume Moving Average over a 20-period lookback (Bypassing VWMA price issues)
        AVG(volume) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) as true_volume_sma_20,

        -- Relative location inside the bands (0 = lower band, 100 = upper band)
        CASE 
            WHEN ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) > 0 
            THEN ROUND(([close] - [BBL_20_2.0_2.0]) / ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) * 100, 1)
            ELSE 50.0
        END as bb_position,
        
        -- Gaps and Islands Engine Indicators
        ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY timestamp) as rn
    FROM tab_calculated_60
    WHERE timestamp >= @lookback_timestamp
),

Squeeze_Island_Flags AS (
    SELECT 
        *,
        -- Mark a record as a squeeze if its true bandwidth drops below your parameter boundary
        CASE WHEN bandwidth_pct <= @max_bandwidth_pct THEN 1 ELSE 0 END as is_squeeze,
        
        -- Second sequence tracker partitioned by the squeeze state vector
        ROW_NUMBER() OVER (
            PARTITION BY symbol, CASE WHEN bandwidth_pct <= @max_bandwidth_pct THEN 1 ELSE 0 END 
            ORDER BY timestamp
        ) as rn2
    FROM Base_Calculated_Data
),

Squeeze_Islands_Grouped AS (
    SELECT 
        *,
        -- The mathematical anchor point: consecutive squeeze rows maintain an identical delta
        (rn - rn2) as island_id
    FROM Squeeze_Island_Flags
    WHERE is_squeeze = 1
),

Squeeze_Island_Statistics AS (
    SELECT 
        symbol,
        island_id,
        MIN(timestamp) as squeeze_start,
        MAX(timestamp) as squeeze_end,
        MIN(datetime_tehran) as squeeze_start_tehran,
        MAX(datetime_tehran) as squeeze_end_tehran,
        COUNT(*) as squeeze_hours,
        ROUND(AVG(bandwidth_pct), 2) as avg_bandwidth,
        ROUND(MIN(bandwidth_pct), 2) as min_bandwidth,
        ROUND(AVG(bb_position), 2) as avg_bb_position,
        ROUND(AVG(price_change_1), 2) as avg_momentum,
        ROUND(AVG(CASE WHEN true_volume_sma_20 > 0 THEN volume / true_volume_sma_20 ELSE 1.0 END), 2) as avg_volume_ratio
    FROM Squeeze_Islands_Grouped
    GROUP BY symbol, island_id
    HAVING COUNT(*) >= @min_squeeze_hours
),

Structural_Breakout_Bridge AS (
    SELECT 
        stat.*,
        base.price as current_market_price,
        base.bandwidth_pct as current_bandwidth,
        base.bb_position as current_bb_position,
        base.price_change_1 as active_1h_momentum,
        base.rsi as current_rsi,
        base.macd_histogram as current_macd_hist,
        CAST((@current_time - base.timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_since_candle,
        
        -- Track structural shifts across the squeeze horizon
        CASE WHEN start_node.bb_middle > 0 THEN ROUND((end_node.bb_middle - start_node.bb_middle) / start_node.bb_middle * 100, 2) ELSE 0 END as middle_band_trend_pct,
        CASE WHEN base.true_volume_sma_20 > 0 THEN ROUND(base.volume / base.true_volume_sma_20, 2) ELSE 0 END as current_volume_ratio,
        ROUND(base.bandwidth_pct - stat.min_bandwidth, 2) as bandwidth_expansion_rate,

        -- Is the asset currently in an active squeeze or evaluating a post-squeeze breakout?
        CASE 
            WHEN base.timestamp = stat.squeeze_end THEN 'ACTIVE_SQUEEZE'
            WHEN base.timestamp > stat.squeeze_end AND base.timestamp <= stat.squeeze_end + (@max_hours_since_exit * 3600) THEN 'POST_SQUEEZE_WINDOW'
            ELSE 'EXPIRED_HORIZON'
        END as lifecycle_state
    FROM Squeeze_Island_Statistics stat
    -- Join to catch the entry boundaries of the compression phase
    JOIN Base_Calculated_Data start_node ON stat.symbol = start_node.symbol AND stat.squeeze_start = start_node.timestamp
    JOIN Base_Calculated_Data end_node ON stat.symbol = end_node.symbol AND stat.squeeze_end = end_node.timestamp
    -- Crucial: Join back to find current data, whether still compressed or in a breakout window
    JOIN Base_Calculated_Data base ON stat.symbol = base.symbol 
        AND base.timestamp >= stat.squeeze_end 
        AND base.timestamp <= stat.squeeze_end + (@max_hours_since_exit * 3600)
),

Scored_Breakout_Matrix AS (
    SELECT 
        *,
        -- Comprehensive Scoring Algorithm (0-100 base)
        CAST(
            (CASE WHEN squeeze_hours >= 48 THEN 35
                  WHEN squeeze_hours >= 24 THEN 25
                  WHEN squeeze_hours >= 12 THEN 15 ELSE 5 END) + -- Coiled tension score
            (CASE WHEN min_bandwidth < 4.0 THEN 25
                  WHEN min_bandwidth < 6.5 THEN 15 ELSE 5 END) + -- Compression tightness score
            (CASE WHEN active_1h_momentum >= 1.5 AND current_volume_ratio >= 1.5 THEN 30
                  WHEN active_1h_momentum >= 0.6 AND current_volume_ratio >= 1.1 THEN 15 ELSE 0 END) + -- Breakout force score
            (CASE WHEN middle_band_trend_pct > 0.5 THEN 10 ELSE 0 END) -- Directional structural drift
        AS INT) as structural_explosive_score
    FROM Structural_Breakout_Bridge
    WHERE lifecycle_state IN ('ACTIVE_SQUEEZE', 'POST_SQUEEZE_WINDOW')
)


