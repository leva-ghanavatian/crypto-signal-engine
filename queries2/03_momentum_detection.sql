-- =================================================================================
-- 03_momentum_detection.sql (Fixed & Case-Aligned for ATRr_14)
-- =================================================================================
-- PURPOSE: Early detection of building momentum and volume velocity surges.
-- Uses true ATRr_14 column to handle asset-agnostic volatility scaling.
-- =================================================================================

USE db_Trading;
GO

-- ---------------------------------------------------------------------------------
-- 1. CONFIGURATION PARAMETERS (Variables)
-- ---------------------------------------------------------------------------------
DECLARE @start_hours_ago INT = 0; -- 0 = Most recent data
DECLARE @end_hours_ago INT = 6; -- Active screening window depth
DECLARE @symbol_filter NVARCHAR(50) = NULL; -- Specific asset or NULL

-- Strategy Technical Thresholds
DECLARE @min_momentum_pct DECIMAL(5,2) = 0.50; -- Minimum baseline 1h price gain %
DECLARE @max_rsi_entry DECIMAL(5,2) = 63.00; -- Prevents buying into overbought fatigue zones
DECLARE @min_volume_ratio DECIMAL(5,2) = 1.20; -- Volume surge confirmation threshold vs SMA20

-- ---------------------------------------------------------------------------------
-- 2. TIME ENGINE CALCULATION & PIPELINE BUFFER INSULATION
-- ---------------------------------------------------------------------------------
DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 3600);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 3600);

-- Expand history window to safely compute window metrics without truncation bugs
DECLARE @buffer_timestamp BIGINT = @end_timestamp - 172800;

-- ---------------------------------------------------------------------------------
-- 3. VELOCITY ENGINE PIPELINE PROCESSING
-- ---------------------------------------------------------------------------------
WITH Buffered_Momentum_Snapshots AS (
    SELECT 
        symbol,
        timestamp,
        [close],
        high,
        low,
        volume,
        RSI as rsi,
        MACDh_12_26_9 as macd_histogram,
        price_change_1,
        price_change_2,
        price_change_3,
        momentum_acceleration,
        
        -- Exact Schema Mapping Fix: Pulls your exact column to prevent Msg 207
        [ATRr_14] as true_atr_normalized,

        -- Standardized rolling volume moving average (Fixed VWMA valuation bug)
        AVG(volume) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) as true_volume_sma_20
    FROM tab_calculated_60
    WHERE timestamp >= @buffer_timestamp
),

Momentum_Metrics_Parser AS (
    SELECT 
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        [close] as current_price,
        ROUND(price_change_1, 2) as momentum_1h_pct,
        ROUND(price_change_2, 2) as momentum_2h_pct,
        ROUND(price_change_3, 2) as momentum_3h_pct,
        ROUND(momentum_acceleration, 2) as acceleration_vector,
        ROUND(rsi, 1) as rsi_value,
        ROUND(macd_histogram, 4) as macd_hist,
        ROUND(true_atr_normalized, 4) as atr_relative_value,
        
        -- Calculated native volume ratio metrics
        CASE WHEN true_volume_sma_20 > 0 THEN ROUND(volume / true_volume_sma_20, 2) ELSE 0 END as real_volume_ratio,

        -- Standardized Multi-Timeframe Velocity Rating
        CASE 
            WHEN price_change_1 >= 2.0 AND momentum_acceleration > 0 THEN 'EXPLOSIVE_SURGE'
            WHEN price_change_1 >= 1.0 AND price_change_2 > price_change_1 THEN 'AGGRESSIVE_ACCELERATION'
            WHEN price_change_1 >= 0.5 THEN 'SUSTAINED_STEADY_MOMENTUM'
            ELSE 'LATENT_DRIFT'
        END as momentum_velocity_tier
    FROM Buffered_Momentum_Snapshots
    -- Slice away history safety buffer cleanly
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
      AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
),

Scored_Momentum_Matrix AS (
    SELECT 
        *,
        -- Comprehensive Momentum Confidence Engine (0-100 Base scale)
        CAST(
            -- Short-term velocity rating weights
            (CASE WHEN momentum_velocity_tier = 'EXPLOSIVE_SURGE' THEN 40
                  WHEN momentum_velocity_tier = 'AGGRESSIVE_ACCELERATION' THEN 30
                  WHEN momentum_velocity_tier = 'SUSTAINED_STEADY_MOMENTUM' THEN 15 ELSE 0 END) +
            
            -- Volume confirmation pressure variables
            (CASE WHEN real_volume_ratio >= 1.80 THEN 35
                  WHEN real_volume_ratio >= 1.30 THEN 20 ELSE 5 END) +
                  
            -- Mathematical trend alignment support
            (CASE WHEN macd_hist > 0 THEN 15 ELSE 0 END) +
            
            -- Volatility expansion validation via your relative ATR values
            (CASE WHEN atr_relative_value > 0.02 THEN 10 ELSE 0 END)
        AS INT) as momentum_confidence_score
    FROM Momentum_Metrics_Parser
)

-- ---------------------------------------------------------------------------------
-- 4. INSIGHTS-FIRST HIGH-PRIORITY ACTIONABLE DISPLAY LAYOUT
-- ---------------------------------------------------------------------------------
SELECT 
    -- PRIMARY SYSTEM RANKING COLUMNS SELECTION FIRST
    momentum_confidence_score,
    symbol,
    momentum_velocity_tier,
    
    tactical_execution_route = CASE 
        WHEN momentum_confidence_score >= 75 AND rsi_value <= 58.0 THEN 'TRIGGER_MARKET_BUY (HIGH_VELOCITY_BREAKOUT)'
        WHEN momentum_confidence_score >= 55 THEN 'ADD_TO_MOMENTUM_WATCH_LIST'
        ELSE 'MONITOR_POSTURE'
    END,

    -- VELOCITY VERIFICATION METRICS
    momentum_1h_pct,
    real_volume_ratio,
    acceleration_vector,
    
    -- VOLATILITY & HISTORICAL RANGE LEVELS
    atr_relative_value as relative_atr_14,
    rsi_value,
    macd_hist,
    
    -- TIMESTAMPS & RECORD DATA
    hours_ago,
    datetime_tehran,
    current_price
FROM Scored_Momentum_Matrix
WHERE 1=1
    -- Operational Scanner Filters
    AND momentum_1h_pct >= @min_momentum_pct
    AND real_volume_ratio >= @min_volume_ratio
    AND rsi_value <= @max_rsi_entry

ORDER BY 
    -- Master Priority Execution Profile Sequence
    momentum_confidence_score DESC,
    real_volume_ratio DESC,
    momentum_1h_pct DESC,
    timestamp DESC;

