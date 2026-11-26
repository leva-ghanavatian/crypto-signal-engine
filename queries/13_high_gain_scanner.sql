-- =====================================================
-- 13_high_gain_scanner.sql
-- =====================================================
-- PURPOSE: Find coins with 10-20% daily gain potential
--          Specifically for small capital, high volatility trading
-- =====================================================

USE db_Trading;

DECLARE @current_time BIGINT = CAST(DATEDIFF(SECOND, '1970-01-01', GETUTCDATE()) AS BIGINT);

-- =====================================================
-- HIGH GAIN CANDIDATES (10-20% daily potential)
-- =====================================================

WITH 
-- Get current data
current_data AS (
    SELECT 
        symbol,
        timestamp,
        DATEADD(MINUTE, 210, DATEADD(SECOND, timestamp, '1970-01-01')) as datetime_tehran,
        CAST((@current_time - timestamp) / 3600.0 AS DECIMAL(5,1)) as hours_ago,
        
        -- Key metrics for high gain
        ROUND([close], 2) as price,
        ROUND(price_change_1, 2) as momentum_1h,
        ROUND(price_change_2, 2) as momentum_2h,
        ROUND(price_change_3, 2) as momentum_3h,
        
        -- Bollinger (squeeze detection)
        CASE 
            WHEN [BBM_20_2.0_2.0] > 0 
            THEN ROUND(([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) / [BBM_20_2.0_2.0] * 100, 2)
            ELSE 0
        END as bandwidth_pct,
        CASE 
            WHEN ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) > 0
            THEN ROUND(([close] - [BBL_20_2.0_2.0]) / ([BBU_20_2.0_2.0] - [BBL_20_2.0_2.0]) * 100, 1)
            ELSE 50
        END as bb_position,
        
        -- Volume (liquidity check)
        volume,
        ROUND(VWMA_20, 0) as avg_volume,
        CASE WHEN VWMA_20 > 0 THEN ROUND(volume / VWMA_20, 2) ELSE 0 END as volume_ratio,
        
        -- RSI (not overbought)
        ROUND(RSI, 1) as rsi,
        
        -- MACD (momentum confirmation)
        ROUND(MACDh_12_26_9, 4) as macd_histogram,
        
        -- Price acceleration
        ROUND(momentum_acceleration, 2) as acceleration,
        
        -- Volume Price Trend (accumulation)
        ROUND(OBV, 0) as obv
        
    FROM tab_calculated_60
    WHERE timestamp >= @current_time - (3 * 60 * 60)  -- Last 3 hours only
),

-- Score each coin for high-gain potential
scored AS (
    SELECT 
        *,
        
        -- =====================================================
        -- HIGH GAIN SCORE (0-100)
        -- =====================================================
        CAST(
            -- Momentum weight (30 points) - MOST IMPORTANT for high gain
            (CASE WHEN momentum_1h > 2.0 THEN 30
                  WHEN momentum_1h > 1.5 THEN 25
                  WHEN momentum_1h > 1.0 THEN 20
                  WHEN momentum_1h > 0.5 THEN 15
                  ELSE 0 END) +
            
            -- Volume weight (25 points) - Confirmation
            (CASE WHEN volume_ratio >= 2.0 THEN 25
                  WHEN volume_ratio >= 1.5 THEN 20
                  WHEN volume_ratio >= 1.2 THEN 15
                  ELSE 0 END) +
            
            -- Acceleration weight (20 points) - Getting faster
            (CASE WHEN acceleration > 0.5 THEN 20
                  WHEN acceleration > 0.2 THEN 15
                  WHEN acceleration > 0 THEN 10
                  ELSE 0 END) +
            
            -- Squeeze/Bandwidth weight (15 points)
            (CASE WHEN bandwidth_pct BETWEEN 6 AND 12 THEN 15
                  WHEN bandwidth_pct < 15 THEN 10
                  ELSE 0 END) +
            
            -- RSI weight (10 points) - Room to run
            (CASE WHEN rsi BETWEEN 40 AND 60 THEN 10
                  WHEN rsi BETWEEN 30 AND 40 THEN 8
                  ELSE 0 END)
        AS INT) as high_gain_score,
        
        -- =====================================================
        -- GAIN EXPECTATION
        -- =====================================================
        CASE 
            WHEN momentum_1h > 2.0 AND volume_ratio > 1.5 AND acceleration > 0.5
                THEN 'EXPECT 15-20% GAIN'
            WHEN momentum_1h > 1.5 AND volume_ratio > 1.2
                THEN 'EXPECT 10-15% GAIN'
            WHEN momentum_1h > 1.0 AND volume_ratio > 1.0
                THEN 'EXPECT 5-10% GAIN'
            ELSE 'LOW EXPECTATION'
        END as expected_gain,
        
        -- =====================================================
        -- ENTRY URGENCY (When to buy)
        -- =====================================================
        CASE 
            WHEN momentum_1h > 1.0 AND acceleration > 0 AND volume_ratio > 1.2
                THEN 'BUY_NOW - Momentum accelerating'
            WHEN momentum_1h > 1.5 AND volume_ratio > 1.0
                THEN 'BUY_SOON - Strong move'
            WHEN momentum_1h > 0.5 AND bandwidth_pct < 10
                THEN 'WATCH - Squeeze building'
            ELSE 'WAIT'
        END as entry_urgency,
        
        -- =====================================================
        -- COIN TYPE CLASSIFICATION
        -- =====================================================
        CASE 
            WHEN symbol LIKE '%MEME%' OR symbol LIKE '%DOG%' OR symbol LIKE '%PEPE%'
                THEN 'MEME_COIN'
            WHEN symbol LIKE '%AI%' OR symbol LIKE '%FET%' OR symbol LIKE '%AGIX%'
                THEN 'AI_COIN'
            WHEN symbol LIKE '%GAME%' OR symbol LIKE '%SAND%' OR symbol LIKE '%MANA%'
                THEN 'GAMING_COIN'
            ELSE 'OTHER'
        END as coin_type
        
    FROM current_data
)

-- Final output - Only high gain candidates
SELECT 
    symbol,
    coin_type,
    datetime_tehran,
    hours_ago,
    price,
    
    -- Momentum (most important)
    momentum_1h as momentum_1h_pct,
    acceleration,
    
    -- Volume
    volume_ratio,
    
    -- Squeeze status
    bandwidth_pct,
    bb_position as bb_position_pct,
    
    -- RSI
    rsi,
    macd_histogram,
    
    -- Scores
    high_gain_score,
    expected_gain,
    entry_urgency,
    
    -- =====================================================
    -- TRADE ACTION (Fixed CONCAT)
    -- =====================================================
    CASE 
        WHEN high_gain_score >= 70 AND entry_urgency = 'BUY_NOW'
            THEN 'BUY ' + symbol + ' - Target 10-15% in 24h'
        WHEN high_gain_score >= 60 AND entry_urgency IN ('BUY_NOW', 'BUY_SOON')
            THEN 'CONSIDER ' + symbol + ' - Good risk/reward'
        WHEN high_gain_score >= 50
            THEN 'WATCH ' + symbol + ' - Set price alert'
        ELSE 'PASS'
    END as action,
    
    -- Suggested take profit levels
    CASE 
        WHEN high_gain_score >= 70 
            THEN 'TP1: +10%, TP2: +15%, TP3: +20%'
        WHEN high_gain_score >= 60 
            THEN 'TP1: +8%, TP2: +12%, TP3: +15%'
        ELSE NULL
    END as take_profit_levels,
    
    -- Stop loss suggestion
    CASE 
        WHEN high_gain_score >= 60 
            THEN '-5% from entry'
        ELSE NULL
    END as stop_loss

FROM scored
WHERE hours_ago <= 2  -- Only very recent
    AND momentum_1h > 0.5  -- At least some momentum
    AND volume_ratio >= 0.8  -- Decent volume
    AND high_gain_score >= 50  -- Minimum score
    
ORDER BY 
    high_gain_score DESC,
    momentum_1h DESC;