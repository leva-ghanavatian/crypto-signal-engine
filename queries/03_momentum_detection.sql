-- =====================================================
-- 03_momentum_detection.sql
-- =====================================================
-- PURPOSE: Early detection of building momentum before official signals
--
-- PARAMETERS:
-- @start_hours_ago: Beginning of time window (default: 0 = most recent)
-- @end_hours_ago: End of time window (default: 2 = 2 hours back)
-- @min_momentum_pct: Minimum 1h price change percentage (default: 0.5)
-- @max_rsi: Maximum RSI value to filter (default: 60)
-- @min_volume_ratio: Minimum volume vs VWMA ratio (default: 0, disabled)
-- @symbol_filter: Specific symbol filter (default: NULL = all symbols)
--
-- EXAMPLES:
-- Last 2 hours:              @start_hours_ago=0, @end_hours_ago=2
-- Hours 5 to 1 ago:          @start_hours_ago=1, @end_hours_ago=5
-- Strong momentum only:      @min_momentum_pct=1.5
-- Conservative (low RSI):    @max_rsi=50
-- Specific symbol:           @symbol_filter='BTCIRT'
-- Volume confirmation:       @min_volume_ratio=1.2
--
-- RETURNS:
-- - Price changes over 1h, 2h, and 3h periods
-- - Momentum acceleration
-- - Rate of Change (ROC) for 2h and 5h periods
-- - RSI and MACD values for confirmation
-- - Early momentum signals (Strong/Emerging/Weak)
-- - Volume comparison to average
--
-- USE CASE: Getting early entries before RSI/MACD confirm trends
-- SORTED BY: Strongest momentum first
-- =====================================================

USE db_Trading;

DECLARE @start_hours_ago INT = 0;        -- 0 = most recent candle
DECLARE @end_hours_ago INT = 2;          -- 2 = last 2 hours (so 0 to 2 hours ago)
DECLARE @min_momentum_pct DECIMAL(5,2) = 2;   -- Minimum 1h price change %
DECLARE @max_rsi DECIMAL(5,2) = 65;             -- Maximum RSI value
DECLARE @min_volume_ratio DECIMAL(5,2) = 1.2;     -- Min volume / VWMA_20 (0 = disabled)
DECLARE @symbol_filter NVARCHAR(50) = NULL;     -- NULL = all symbols, or 'BTCIRT'


DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 60 * 60);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 60 * 60);

-- =====================================================
-- MAIN QUERY
-- =====================================================

SELECT 
    -- Time information
    symbol,
    timestamp,
    DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
    CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
    
    -- Price data
    ROUND([close], 2) as price,
    
    -- Momentum indicators
    ROUND(price_change_1, 2) as momentum_1h_pct,
    ROUND(price_change_2, 2) as momentum_2h_pct,
    ROUND(price_change_3, 2) as momentum_3h_pct,
    ROUND(momentum_acceleration, 2) as acceleration,
    
    -- Rate of Change
    ROUND(ROC_5, 2) as roc_5h,
    ROUND(ROC_2, 2) as roc_2h,
    
    -- Confirmation indicators
    ROUND(RSI, 1) as rsi,
    ROUND(MACD_12_26_9, 4) as macd_line,
    ROUND(MACDh_12_26_9, 4) as macd_histogram,
    
    -- Volume analysis
    ROUND(volume, 0) as volume,
    ROUND(VWMA_20, 0) as avg_volume_20h,
    CASE 
        WHEN VWMA_20 > 0 THEN ROUND(volume / VWMA_20, 2)
        ELSE 0
    END as volume_ratio,
    
    -- =====================================================
    -- MOMENTUM SIGNAL CLASSIFICATION 
    -- =====================================================
    CASE 
        WHEN price_change_1 > 1.5 AND price_change_2 > 1 THEN 'STRONG_EARLY_MOMENTUM'
        WHEN price_change_1 > 1 AND momentum_acceleration > 0.5 THEN 'ACCELERATING_MOMENTUM'
        WHEN price_change_1 > 0.5 THEN 'WEAK_MOMENTUM_BUILDING'
        WHEN price_change_1 > 0 THEN 'MINIMAL_MOMENTUM'
        ELSE 'NEGATIVE_MOMENTUM'
    END as momentum_signal,
    
    -- =====================================================
    -- VOLUME STATUS
    -- =====================================================
    CASE 
        WHEN VWMA_20 > 0 AND volume / VWMA_20 >= 1.5 THEN 'HIGH_VOLUME'
        WHEN VWMA_20 > 0 AND volume / VWMA_20 >= 1.2 THEN 'ABOVE_AVERAGE_VOLUME'
        WHEN VWMA_20 > 0 AND volume / VWMA_20 >= 0.8 THEN 'NORMAL_VOLUME'
        ELSE 'LOW_VOLUME'
    END as volume_status,
    
    -- =====================================================
    -- MACD DIRECTION
    -- =====================================================
    CASE 
        WHEN MACDh_12_26_9 > 0 THEN 'BULLISH'
        WHEN MACDh_12_26_9 < 0 THEN 'BEARISH'
        ELSE 'NEUTRAL'
    END as macd_direction,
    
    -- =====================================================
    -- RSI ZONE
    -- =====================================================
    CASE 
        WHEN RSI < 30 THEN 'OVERSOLD'
        WHEN RSI BETWEEN 30 AND 40 THEN 'NEAR_OVERSOLD'
        WHEN RSI BETWEEN 40 AND 60 THEN 'NEUTRAL'
        WHEN RSI BETWEEN 60 AND 70 THEN 'NEAR_OVERBOUGHT'
        ELSE 'OVERBOUGHT'
    END as rsi_zone

FROM tab_calculated_60
WHERE 1=1
    AND timestamp BETWEEN @end_timestamp AND @start_timestamp
    -- Momentum filter
    AND price_change_1 >= @min_momentum_pct
    -- RSI filter (not overbought)
    AND RSI <= @max_rsi
    -- Volume filter (if enabled)
    AND (@min_volume_ratio <= 0 OR (VWMA_20 > 0 AND volume / VWMA_20 >= @min_volume_ratio))
    -- Symbol filter (if specified)
    AND (@symbol_filter IS NULL OR symbol = @symbol_filter)

ORDER BY 
    -- Order by strongest momentum first
    price_change_1 DESC,
    hours_ago ASC;