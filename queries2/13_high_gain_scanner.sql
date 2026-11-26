-- =================================================================================
-- 13_high_gain_scanner.sql (Refactored & High-Velocity Tailored)
-- =================================================================================
-- PURPOSE: Scans for high-volatility assets entering or freshly breaking out of
-- prolonged compression zones for rapid 10-20% intra-day gains.
-- =================================================================================

USE db_Trading;
GO

-- ---------------------------------------------------------------------------------
-- 1. CONFIGURATION PARAMETERS (Variables)
-- ---------------------------------------------------------------------------------
DECLARE @lookback_hours INT = 4; -- Active screening window depth
DECLARE @symbol_filter NVARCHAR(50) = NULL; -- Specific asset or NULL

-- Strategy Execution Thresholds
DECLARE @min_1h_momentum DECIMAL(5,2) = 0.60; -- Captures early structural acceleration
DECLARE @min_volume_ratio DECIMAL(5,2) = 1.30; -- Enforces heavy institutional backing vs SMA20
DECLARE @max_rsi_entry DECIMAL(5,2) = 68.00; -- Exhaustion ceiling to prevent chasing tops

-- ---------------------------------------------------------------------------------
-- 2. TIME ENGINE CALCULATION & PIPELINE BUFFER INSULATION
-- ---------------------------------------------------------------------------------
DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time;
DECLARE @end_timestamp BIGINT = @current_time - (@lookback_hours * 3600);

-- Allocate a 48-hour historical buffer to calculate continuous rolling averages and lags
DECLARE @buffer_timestamp BIGINT = @end_timestamp - 172800;

-- ---------------------------------------------------------------------------------
-- 3. CORE VOLATILITY & VELOCITY DATA PIPELINE
-- ---------------------------------------------------------------------------------
WITH Buffered_Data_Capture AS (
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

        -- Corrected Mathematical Bollinger Bandwidth Parsing
        CASE 
            WHEN [BBM_20_2.0_2.0] > 0 
            THEN ROUND(([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100, 2)
            ELSE 100.00
        END as bandwidth_pct,

        -- Relative location inside bands (0 = Lower Band Floor, 100 = Upper Band Ceiling)
        CASE 
            WHEN ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) > 0 
            THEN ROUND(([close] - [BBL_20_2.0_2.0]) / ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) * 100, 1)
            ELSE 50.0
        END as bb_position,

        -- True volume moving average baseline over a 20-period lookback (Bypassing VWMA price issues)
        AVG(volume) OVER (PARTITION BY symbol ORDER BY timestamp ASC ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) as true_volume_sma_20,

        -- Historical compression markers (Did a squeeze exist 1 and 2 hours ago?)
        LAG(CASE WHEN [BBM_20_2.0_2.0] > 0 THEN ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100 ELSE 100.00 END, 1) 
            OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_bandwidth_1,
        LAG(CASE WHEN [BBM_20_2.0_2.0] > 0 THEN ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100 ELSE 100.00 END, 2) 
            OVER (PARTITION BY symbol ORDER BY timestamp ASC) as prev_bandwidth_2
    FROM tab_calculated_60
    WHERE timestamp >= @buffer_timestamp
),

High_Gain_Metrics_Engine AS (
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
        bandwidth_pct,
        bb_position,
        
        -- Corrected volume ratio calculation
        CASE WHEN true_volume_sma_20 > 0 THEN ROUND(volume / true_volume_sma_20, 2) ELSE 0 END as real_volume_ratio,

        -- Identify if the asset has recently broken out of a verified squeeze state
        CASE 
            WHEN bandwidth_pct <= 8.50 THEN 'ACTIVE_COMPRESSION'
            WHEN (prev_bandwidth_1 <= 8.50 OR prev_bandwidth_2 <= 8.50) AND bandwidth_pct > prev_bandwidth_1 THEN 'FRESH_COMPRESSION_BREAKOUT'
            ELSE 'STANDARD_VOLATILITY_EXPANSION'
        END as volatility_posture
    FROM Buffered_Data_Capture
    -- Remove chronological buffer fields cleanly
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
      AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
),

Scored_Explosive_Matrix AS (
    SELECT 
        *,
        -- Comprehensive Explosive Score Engine (0-100 Base scale)
        CAST(
            -- Volume Velocity Weights
            (CASE WHEN real_volume_ratio >= 2.0 THEN 35
                  WHEN real_volume_ratio >= 1.4 THEN 20 ELSE 5 END) +
            
            -- Volatility Posture Premium (Favors active squeezes or fresh expansions)
            (CASE WHEN volatility_posture = 'FRESH_COMPRESSION_BREAKOUT' THEN 30
                  WHEN volatility_posture = 'ACTIVE_COMPRESSION' THEN 20 ELSE 5 END) +
            
            -- Momentum Acceleration Vectors
            (CASE WHEN momentum_1h_pct >= 2.0 AND acceleration_vector > 0 THEN 25
                  WHEN momentum_1h_pct >= 0.8 AND acceleration_vector > 0 THEN 15 ELSE 5 END) +
            
            -- Trend Structure Concurrence
            (CASE WHEN macd_hist > 0 AND bb_position >= 75 THEN 10 ELSE 0 END)
        AS INT) as explosive_potential_score
    FROM High_Gain_Metrics_Engine
)

-- ---------------------------------------------------------------------------------
-- 4. INSIGHTS-FIRST HIGH-PRIORITY ACTIONABLE DISPLAY LAYOUT
-- ---------------------------------------------------------------------------------
SELECT 
    -- PRIMARY SIGNAL IDENTIFICATION FIELDS FIRST
    explosive_potential_score,
    symbol,
    volatility_posture,
    
    tactical_execution_route = CASE 
        WHEN explosive_potential_score >= 75 AND rsi_value <= 60.0 THEN 'URGENT_MARKET_BUY (HIGH_GAIN_BREAKOUT)'
        WHEN explosive_potential_score >= 60 THEN 'STRATEGIC_LIMIT_ENTRY (ACCELERATING_MOMENTUM)'
        WHEN volatility_posture = 'ACTIVE_COMPRESSION' THEN 'PLACEMENT_ALERT_WATCH (COILING_ENERGY)'
        ELSE 'MONITOR_POSTURE'
    END,

    -- SUGGESTED RISK ARCHITECTURE
    suggested_take_profit = CASE 
        WHEN explosive_potential_score >= 75 THEN 'TP1: +10% | TP2: +15% | TP3: +22%'
        ELSE 'TP1: +6% | TP2: +10% | TP3: +14%'
    END,
    suggested_stop_loss = CASE 
        WHEN acceleration_vector > 0.5 THEN '-4.5%'
        ELSE '-3.0%'
    END,

    -- VELOCITY VERIFICATION METRICS
    momentum_1h_pct,
    real_volume_ratio,
    acceleration_vector,
    
    -- VOLATILITY TENSION METRICS
    ROUND(bandwidth_pct, 2) as current_bandwidth_pct,
    ROUND(bb_position, 1) as band_location_pct,
    rsi_value,
    macd_hist,
    
    -- TIME & VALUE RECORD RECORD
    hours_ago,
    datetime_tehran,
    current_price
FROM Scored_Explosive_Matrix
WHERE 1=1
    -- Global Operational Strategy Controls
    AND momentum_1h_pct >= @min_1h_momentum
    AND real_volume_ratio >= @min_volume_ratio
    AND rsi_value <= @max_rsi_entry

ORDER BY 
    -- Master Dashboard Priority Sort Sequence
    explosive_potential_score DESC,
    real_volume_ratio DESC,
    momentum_1h_pct DESC,
    timestamp DESC;
