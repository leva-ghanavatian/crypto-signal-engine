-- =================================================================================
-- 02_oversold_opportunities.sql (Refactored & Highly Optimized)
-- =================================================================================
-- PURPOSE: Identifies high-probability oversold environments experiencing active 
-- bullish momentum shifts while aggressively filtering out falling knives.
-- =================================================================================

USE db_Trading;
GO

-- ---------------------------------------------------------------------------------
-- 1. CONFIGURATION PARAMETERS (Variables)
-- ---------------------------------------------------------------------------------
DECLARE @start_hours_ago INT = 0; -- 0 = Most recent candle
DECLARE @end_hours_ago INT = 6; -- Lookback window width (Expanded for safety)
DECLARE @max_hours_ago INT = 24; -- Absolute maximum cutoff for valid signals
DECLARE @symbol_filter NVARCHAR(50) = NULL; -- Set to specific asset (e.g., 'BTCIRT') or NULL

-- Indicator Thresholds
DECLARE @min_rsi DECIMAL(5,2) = 20.00; -- Extreme oversold lower bound
DECLARE @max_rsi DECIMAL(5,2) = 42.00; -- Upper bound of interest for reversals
DECLARE @min_macd_hist_growth DECIMAL(10,4) = 0.0000; -- Requires MACD histogram to be increasing
DECLARE @min_momentum_1h DECIMAL(5,2) = 0.20; -- Minimum 1h price bounce confirmation %
DECLARE @min_volume_ratio DECIMAL(5,2) = 1.10; -- Minimum volume multiplier against VWMA_20
DECLARE @max_adx_bear_trend DECIMAL(5,2) = 35.00; -- Filter out hyper-strong structural downtrends

-- Strategy Toggles
DECLARE @require_buy_signal INT = 1; -- 1 = Forces alignment with tab_analysis_results
DECLARE @filter_falling_knives INT = 1; -- 1 = Blocks entries when price is deep under EMA50

-- ---------------------------------------------------------------------------------
-- 2. TIME ENGINE CALCULATION
-- ---------------------------------------------------------------------------------
DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);
DECLARE @start_timestamp BIGINT = @current_time - (@start_hours_ago * 3600);
DECLARE @end_timestamp BIGINT = @current_time - (@end_hours_ago * 3600);
DECLARE @max_age_timestamp BIGINT = @current_time - (@max_hours_ago * 3600);

-- ---------------------------------------------------------------------------------
-- 3. CORE ANALYTICAL ENGINE
-- ---------------------------------------------------------------------------------
;WITH Historical_Context AS (
    SELECT 
        c.timestamp,
        c.symbol,
        c.[close],
        c.RSI,
        c.MACDh_12_26_9,
        c.price_change_1,
        c.volume,
        c.VWMA_20,
        c.ADX_14,
        c.EMA_50,
        a.combined_signal,
        a.combined_score,
        -- Windows Lag Metrics to identify shifting momentum vectors
        LAG(c.RSI, 1) OVER (PARTITION BY c.symbol ORDER BY c.timestamp ASC) as prev_rsi,
        LAG(c.MACDh_12_26_9, 1) OVER (PARTITION BY c.symbol ORDER BY c.timestamp ASC) as prev_macd_hist,
        LAG(c.[close], 1) OVER (PARTITION BY c.symbol ORDER BY c.timestamp ASC) as prev_close
    FROM tab_calculated_60 c
    INNER JOIN tab_analysis_results a ON c.symbol = a.symbol AND c.timestamp = a.timestamp
    WHERE c.timestamp >= @max_age_timestamp
),

Opportunity_Scoring AS (
    SELECT 
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        symbol,
        [close] as current_price,
        ROUND(RSI, 1) as rsi_value,
        ROUND(MACDh_12_26_9, 4) as macd_histogram,
        ROUND(price_change_1, 2) as momentum_1h_pct,
        
        -- Volume Multiplier calculation
        CASE WHEN VWMA_20 > 0 THEN ROUND(volume / VWMA_20, 2) ELSE 0 END as volume_ratio,
        
        -- Trend State Mechanics
        ROUND(ADX_14, 1) as adx_trend_strength,
        CASE 
            WHEN [close] > EMA_50 THEN 'BULLISH_STRUCTURE'
            WHEN [close] <= EMA_50 AND ADX_14 > @max_adx_bear_trend THEN 'STRONG_BEAR_TREND (DANGEROUS)'
            ELSE 'BEARISH_RECOVERY'
        END as trend_environment,

        -- Advanced Reversal Momentum Confirmations
        CASE WHEN MACDh_12_26_9 > prev_macd_hist THEN 1 ELSE 0 END as is_macd_histogram_expanding,
        CASE WHEN RSI > prev_rsi THEN 1 ELSE 0 END as is_rsi_turning_up,

        -- Dynamic Scoring Algorithm (0-100 Base scale)
        CAST(
            (CASE WHEN RSI < 25 THEN 40 
                  WHEN RSI < 30 THEN 35 
                  WHEN RSI < 35 THEN 25 
                  ELSE 10 END) + -- Deep Oversold Weight
            (CASE WHEN MACDh_12_26_9 > 0 AND MACDh_12_26_9 > prev_macd_hist THEN 25 
                  WHEN MACDh_12_26_9 > prev_macd_hist THEN 15 
                  ELSE 0 END) + -- MACD Trajectory Shift Weight
            (CASE WHEN price_change_1 > 1.0 THEN 20 
                  WHEN price_change_1 > 0 THEN 10 
                  ELSE 0 END) + -- Short-term buying velocity
            (CASE WHEN volume > VWMA_20 * 1.5 THEN 15 
                  WHEN volume > VWMA_20 THEN 8 
                  ELSE 0 END) -- Institutional buying volume confirmation
        AS INT) as calculated_reversal_score,
        
        combined_signal,
        combined_score as engine_score
    FROM Historical_Context
    WHERE timestamp BETWEEN @end_timestamp AND @start_timestamp
)

-- ---------------------------------------------------------------------------------
-- 4. ENLIGHTENED FILTERING & SORTING OUTPUT
-- ---------------------------------------------------------------------------------
SELECT 
    -- MOST ENLIGHTENING COLUMNS FIRST (Actionable Insights)
    calculated_reversal_score,
    symbol,
    rsi_value,
    trend_environment,
    opportunity_signal = CASE 
        WHEN calculated_reversal_score >= 75 AND trend_environment <> 'STRONG_BEAR_TREND (DANGEROUS)' THEN 'STRONG_REVERSAL_CONFIRMED'
        WHEN calculated_reversal_score >= 55 THEN 'VALID_BUY_OPPORTUNITY'
        WHEN rsi_value < 30 THEN 'SPECULATIVE_NIFE_CATCH'
        ELSE 'WATCH_LIST'
    END,

    -- MOMENTUM & VOLUME VALIDATION DATA
    momentum_1h_pct,
    macd_histogram,
    is_macd_histogram_expanding,
    is_rsi_turning_up,
    volume_ratio,
    adx_trend_strength,
    
    -- SYSTEM STRATEGY METRICS
    combined_signal as engine_signal,
    engine_score,
    
    -- TIME METRICS
    hours_ago,
    datetime_tehran,
    current_price
FROM Opportunity_Scoring
WHERE 1=1
    -- Apply strict boundary configurations
    AND rsi_value BETWEEN @min_rsi AND @max_rsi
    AND momentum_1h_pct >= @min_momentum_1h
    AND volume_ratio >= @min_volume_ratio
    
    -- Trigger conditional rules based on user parameters
    AND (@require_buy_signal = 0 OR combined_signal IN ('BUY', 'STRONG_BUY'))
    AND (@filter_falling_knives = 0 OR trend_environment <> 'STRONG_BEAR_TREND (DANGEROUS)')

ORDER BY 
    -- Master Sort Priority Layout
    calculated_reversal_score DESC, 
    rsi_value ASC, -- Sharper entry relative to price floor
    momentum_1h_pct DESC, -- Highest immediate bounce power
    timestamp DESC; -- Cleanest real-time relevance