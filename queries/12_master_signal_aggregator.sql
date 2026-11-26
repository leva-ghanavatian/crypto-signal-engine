-- =====================================================
-- 12_master_signal_aggregator.sql
-- =====================================================
-- PURPOSE: Combine ALL signal types into one unified view
--          Shows which coins are confirmed by multiple indicators
--
-- OUTPUT: Each coin appears once with scores from all indicators
--         Use this as your daily trading dashboard
--
-- PARAMETERS:
-- @lookback_hours: Look at signals from last X hours (default: 6)
-- @min_momentum: Minimum 1h momentum (default: 0, disabled)
-- @max_rsi: Maximum RSI value (default: 100, disabled)
-- @min_volume_ratio: Minimum volume ratio (default: 0, disabled)
-- @symbol_filter: Specific symbol filter (default: NULL)
-- =====================================================

USE db_Trading;

-- =====================================================
-- CONFIGURATION PARAMETERS (EDIT THESE VALUES)
-- =====================================================

DECLARE @lookback_hours INT = 6;               -- Look at signals from last X hours
DECLARE @min_momentum DECIMAL(5,2) = 0;        -- Minimum 1h momentum (0 = disabled)
DECLARE @max_rsi DECIMAL(5,2) = 65;           -- Maximum RSI value (100 = disabled)
DECLARE @min_volume_ratio DECIMAL(5,2) = 0;    -- Minimum volume ratio (0 = disabled)
DECLARE @symbol_filter NVARCHAR(50) = NULL;    -- NULL = all symbols, or 'BTCIRT'

-- =====================================================
-- TIME CALCULATIONS
-- =====================================================

DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);

-- =====================================================
-- GET CURRENT CANDLE FOR EACH SYMBOL
-- =====================================================

WITH current_candle AS (
    SELECT 
        symbol,
        MAX(timestamp) as latest_timestamp
    FROM tab_calculated_60
    WHERE timestamp >= @current_time - (72 * 60 * 60)
        AND (@symbol_filter IS NULL OR symbol = @symbol_filter)
    GROUP BY symbol
),

current_data AS (
    SELECT 
        c.symbol,
        c.timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, c.timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - c.timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        
        -- Price & Momentum
        ROUND(c.[close], 2) as price,
        ROUND(c.price_change_1, 2) as momentum_1h,
        ROUND(c.price_change_2, 2) as momentum_2h,
        ROUND(c.momentum_acceleration, 2) as acceleration,
        
        -- RSI
        ROUND(c.RSI, 1) as rsi,
        
        -- MACD
        ROUND(c.MACDh_12_26_9, 4) as macd_histogram,
        ROUND(c.MACD_12_26_9, 4) as macd_line,
        ROUND(c.MACDs_12_26_9, 4) as macd_signal_line,
        
        -- Bollinger Bands
        ROUND(c.[BBU_20_2.0_2.0], 2) as bb_upper,
        ROUND(c.[BBM_20_2.0_2.0], 2) as bb_middle,
        ROUND(c.[BBL_20_2.0_2.0], 2) as bb_lower,
        CASE 
            WHEN c.[BBM_20_2.0_2.0] > 0 
            THEN ROUND((c.[BBU_20_2.0_2.0] - c.[BBL_20_2.0_2.0]) / c.[BBM_20_2.0_2.0] * 100, 2)
            ELSE 0
        END as bb_bandwidth,
        CASE 
            WHEN (c.[BBU_20_2.0_2.0] - c.[BBL_20_2.0_2.0]) > 0
            THEN ROUND((c.[close] - c.[BBL_20_2.0_2.0]) / (c.[BBU_20_2.0_2.0] - c.[BBL_20_2.0_2.0]) * 100, 1)
            ELSE 50
        END as bb_position,
        
        -- Volume
        c.volume,
        ROUND(c.VWMA_20, 0) as avg_volume,
        CASE WHEN c.VWMA_20 > 0 THEN ROUND(c.volume / c.VWMA_20, 2) ELSE 0 END as volume_ratio,
        
        -- Trend
        ROUND(c.ADX_14, 1) as adx
        
    FROM tab_calculated_60 c
    INNER JOIN current_candle cc ON c.symbol = cc.symbol AND c.timestamp = cc.latest_timestamp
),

-- =====================================================
-- SIGNAL 1: BOLLINGER BULLISH (09 - Squeeze or Breakout)
-- =====================================================
bb_signals AS (
    SELECT 
        symbol,
        CASE 
            -- Ready to break (bullish)
            WHEN bb_position > 55 
                 AND momentum_1h > 0.3 
                 AND bb_bandwidth < 10
                 AND macd_histogram > 0
            THEN 100
            -- Squeeze only (potential)
            WHEN bb_bandwidth < 8 AND bb_position > 50
            THEN 70
            -- Normal range but bullish
            WHEN bb_position > 55 AND momentum_1h > 0.5
            THEN 60
            ELSE 0
        END as bb_score,
        CASE 
            WHEN bb_position > 55 AND momentum_1h > 0.3 AND bb_bandwidth < 10 AND macd_histogram > 0
            THEN 'BULLISH_BURST_READY'
            WHEN bb_bandwidth < 8 AND bb_position > 50
            THEN 'SQUEEZE_POTENTIAL'
            WHEN bb_position > 55 AND momentum_1h > 0.5
            THEN 'BREAKOUT_STARTING'
            ELSE NULL
        END as bb_signal_type
    FROM current_data
),

-- =====================================================
-- SIGNAL 2: MACD BULLISH (05 - Crossover)
-- =====================================================
macd_signals AS (
    SELECT 
        symbol,
        CASE 
            -- Bullish crossover (strong)
            WHEN macd_histogram > 0.05 AND macd_line > macd_signal_line
                 AND macd_histogram > LAG(macd_histogram) OVER (PARTITION BY symbol ORDER BY timestamp)
            THEN 100
            -- In bullish territory
            WHEN macd_histogram > 0 AND macd_line > macd_signal_line
            THEN 70
            -- Just crossed into positive
            WHEN macd_histogram > 0
            THEN 50
            ELSE 0
        END as macd_score,
        CASE 
            WHEN macd_histogram > 0.05 AND macd_line > macd_signal_line
            THEN 'STRONG_BULLISH_MACD'
            WHEN macd_histogram > 0 AND macd_line > macd_signal_line
            THEN 'BULLISH_MACD'
            WHEN macd_histogram > 0
            THEN 'MACD_TURNING_BULLISH'
            ELSE NULL
        END as macd_signal_type
    FROM current_data
),

-- =====================================================
-- SIGNAL 3: MOMENTUM (03 - Early detection)
-- =====================================================
momentum_signals AS (
    SELECT 
        symbol,
        CASE 
            -- Strong accelerating momentum
            WHEN momentum_1h > 1.0 AND acceleration > 0.2 AND volume_ratio > 1.0
            THEN 100
            -- Good momentum
            WHEN momentum_1h > 0.7 AND volume_ratio > 0.8
            THEN 80
            -- Building momentum
            WHEN momentum_1h > 0.3 AND acceleration > 0
            THEN 60
            -- Weak momentum
            WHEN momentum_1h > 0
            THEN 40
            ELSE 0
        END as momentum_score,
        CASE 
            WHEN momentum_1h > 1.0 AND acceleration > 0.2
            THEN 'STRONG_ACCELERATING'
            WHEN momentum_1h > 0.7
            THEN 'STRONG_MOMENTUM'
            WHEN momentum_1h > 0.3
            THEN 'BUILDING_MOMENTUM'
            ELSE NULL
        END as momentum_signal_type
    FROM current_data
),

-- =====================================================
-- SIGNAL 4: OVERSOLD REVERSAL (02)
-- =====================================================
oversold_signals AS (
    SELECT 
        symbol,
        CASE 
            -- Perfect reversal setup
            WHEN rsi BETWEEN 30 AND 40 
                 AND momentum_1h > 0.3 
                 AND macd_histogram > -0.1
            THEN 90
            -- Oversold but turning
            WHEN rsi < 35 AND momentum_1h > 0
            THEN 70
            -- Just oversold
            WHEN rsi < 40
            THEN 50
            ELSE 0
        END as oversold_score,
        CASE 
            WHEN rsi BETWEEN 30 AND 40 AND momentum_1h > 0.3 AND macd_histogram > -0.1
            THEN 'STRONG_REVERSAL_SETUP'
            WHEN rsi < 35 AND momentum_1h > 0
            THEN 'OVERSOLD_BOUNCE'
            ELSE NULL
        END as oversold_signal_type
    FROM current_data
),

-- =====================================================
-- SIGNAL 5: VOLUME CONFIRMATION
-- =====================================================
volume_signals AS (
    SELECT 
        symbol,
        CASE 
            WHEN volume_ratio >= 1.5 THEN 100
            WHEN volume_ratio >= 1.2 THEN 80
            WHEN volume_ratio >= 1.0 THEN 60
            ELSE 0
        END as volume_score,
        CASE 
            WHEN volume_ratio >= 1.5 THEN 'VERY_HIGH_VOLUME'
            WHEN volume_ratio >= 1.2 THEN 'HIGH_VOLUME'
            WHEN volume_ratio >= 1.0 THEN 'ABOVE_AVERAGE_VOLUME'
            ELSE NULL
        END as volume_signal_type
    FROM current_data
),

-- =====================================================
-- COMBINE ALL SIGNALS
-- =====================================================
combined AS (
    SELECT 
        c.*,
        ISNULL(bb.bb_score, 0) as bb_score,
        ISNULL(bb.bb_signal_type, '') as bb_signal_type,
        ISNULL(m.macd_score, 0) as macd_score,
        ISNULL(m.macd_signal_type, '') as macd_signal_type,
        ISNULL(mom.momentum_score, 0) as momentum_score,
        ISNULL(mom.momentum_signal_type, '') as momentum_signal_type,
        ISNULL(os.oversold_score, 0) as oversold_score,
        ISNULL(os.oversold_signal_type, '') as oversold_signal_type,
        ISNULL(v.volume_score, 0) as volume_score,
        ISNULL(v.volume_signal_type, '') as volume_signal_type
    FROM current_data c
    LEFT JOIN bb_signals bb ON c.symbol = bb.symbol
    LEFT JOIN macd_signals m ON c.symbol = m.symbol
    LEFT JOIN momentum_signals mom ON c.symbol = mom.symbol
    LEFT JOIN oversold_signals os ON c.symbol = os.symbol
    LEFT JOIN volume_signals v ON c.symbol = v.symbol
),

-- Calculate combined scores
scored AS (
    SELECT 
        *,
        -- Total score (sum of all)
        (bb_score + macd_score + momentum_score + volume_score) as total_score,
        
        -- Count how many signals are active (score >= 50)
        (CASE WHEN bb_score >= 50 THEN 1 ELSE 0 END +
         CASE WHEN macd_score >= 50 THEN 1 ELSE 0 END +
         CASE WHEN momentum_score >= 50 THEN 1 ELSE 0 END +
         CASE WHEN oversold_score >= 50 THEN 1 ELSE 0 END +
         CASE WHEN volume_score >= 50 THEN 1 ELSE 0 END) as active_signals_count,
        
        -- Which signals are active (using clean names)
        CONCAT(
            CASE WHEN bb_score >= 50 THEN 'BB ' ELSE '' END,
            CASE WHEN macd_score >= 50 THEN 'MACD ' ELSE '' END,
            CASE WHEN momentum_score >= 50 THEN 'MOM ' ELSE '' END,
            CASE WHEN oversold_score >= 50 THEN 'OS ' ELSE '' END,
            CASE WHEN volume_score >= 50 THEN 'VOL ' ELSE '' END
        ) as active_signals
    FROM combined
),

-- Apply filters
filtered AS (
    SELECT 
        *
    FROM scored
    WHERE hours_ago <= @lookback_hours
        AND momentum_1h >= @min_momentum
        AND rsi <= @max_rsi
        AND (@min_volume_ratio <= 0 OR volume_ratio >= @min_volume_ratio)
)

-- =====================================================
-- FINAL OUTPUT - SORTED BY BEST OPPORTUNITIES
-- =====================================================
SELECT 
    symbol,
    datetime_tehran as last_update,
    hours_ago,
    price,
    ROUND(momentum_1h, 2) as momentum_1h_pct,
    rsi,
    
    -- Individual Scores (0-100)
    bb_score,
    macd_score,
    momentum_score,
    oversold_score,
    volume_score,
    
    -- Individual Signal Types
    bb_signal_type,
    macd_signal_type,
    momentum_signal_type,
    oversold_signal_type,
    volume_signal_type,
    
    -- Combined Metrics
    total_score,
    active_signals_count,
    active_signals,
    
    -- Recommendation based on multiple confirmations
    CASE 
        -- STRONGEST: 4+ signals active + high scores
        WHEN active_signals_count >= 4 AND total_score >= 250
        THEN 'STRONG_BUY - Multiple confirmations'
        
        -- STRONG: 3+ signals active
        WHEN active_signals_count >= 3 AND total_score >= 200
        THEN 'BUY - Good confirmation'
        
        -- MODERATE: 2 signals active
        WHEN active_signals_count >= 2 AND total_score >= 150
        THEN 'WATCH - Needs confirmation'
        
        -- WEAK: Only 1 signal
        WHEN active_signals_count >= 1
        THEN 'MONITOR - Weak signal'
        
        ELSE 'AVOID - No signals'
    END as recommendation,
    
    -- Entry suggestion based on which signals are active
    CASE 
        WHEN active_signals LIKE '%BB%' AND active_signals LIKE '%MACD%' AND active_signals LIKE '%MOM%'
        THEN 'IMMEDIATE_ENTRY - All indicators aligned'
        WHEN active_signals LIKE '%BB%' AND active_signals LIKE '%MACD%'
        THEN 'CONSIDER_ENTRY - BB and MACD agree'
        WHEN active_signals LIKE '%OS%' AND active_signals LIKE '%MOM%'
        THEN 'DIP_BUY_ENTRY - Oversold bounce'
        ELSE 'WAIT_FOR_CONFIRMATION'
    END as entry_strategy,
    
    -- Additional info
    ROUND(bb_bandwidth, 1) as bb_bandwidth_pct,
    ROUND(bb_position, 0) as bb_position_pct,
    ROUND(macd_histogram, 4) as macd_hist,
    volume_ratio

FROM filtered
ORDER BY 
    active_signals_count DESC,
    total_score DESC,
    momentum_1h DESC;