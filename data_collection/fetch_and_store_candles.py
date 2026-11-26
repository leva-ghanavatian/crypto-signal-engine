import json
import pandas as pd
from sqlalchemy import create_engine
import urllib
import requests
import time
import pandas_ta as ta
import time

list_dfs=[]
all_dfs = pd.DataFrame()

to_time = int(time.time())
from_time = to_time - (60 * 1 * 60 * 60)

def my_function(symbol: str, max_retries=3):
    resolution = "60"
    url="https://apiv2.nobitex.ir/market/udf/history"
    url_new = f"{url}?symbol={symbol}&resolution={resolution}&from={from_time}&to={to_time}"
    for attempt in range(max_retries):
        try:
            response = requests.get(url_new, timeout=30)
            response.raise_for_status()
            candles_data = response.json()
            if "s" in candles_data and candles_data["s"] == "ok":
                file_name = f"json/candles_{symbol}.json"
                with open(file_name, "w") as json_file:
                    json.dump(candles_data, json_file, indent=4)
                    print(f'✅ {symbol}')
                break  # Success, exit retry loop
            else:
                print(f" ⚠️  {symbol}")
                return
        except requests.exceptions.RequestException as e:
            print(f"❌ {symbol} - Attempt {attempt + 1}/{max_retries} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(2)  # Wait before retry
            else:
                print(f"❌ {symbol} - All retries failed, skipping")
                return

    # --------------------------------------------------------------------------------------------------------
    file_path = f"json/candles_{symbol}.json"
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            json_data = json.load(f)

        df = pd.DataFrame({
            'timestamp': json_data['t'],
            'open': json_data['o'],
            'close': json_data['c'],
            'high': json_data['h'],
            'low': json_data['l'],
            'volume': json_data['v'],
        })
        numeric_cols = ['open', 'high', 'low', 'close', 'volume']
        for col in numeric_cols:
            df[col] = pd.to_numeric(df[col], errors='coerce')
        df['symbol'] = symbol
        #----------------------------------------------------------------------------------------------------------------
        # ---RSI
        df['RSI']=ta.rsi(df['close'])
        #---RSI-EMA
        df['RSI_EMA']=ta.ema(df['RSI'],length = 10)
        #---MACD
        df.ta.macd(close='close', fast=12, slow=26, signal=9, append=True)#
        #---BBANDS
        df.ta.bbands(close='close', length=20,std=2, append=True)#
        #---MFI
        df.ta.mfi(append=True,length=14)#
        #---STOCH
        df.ta.stoch(high='high', low='low', close='close', append=True,fastk_period=14,slowk_priod=1,slowd_period=3)#
        #---CCI
        df.ta.cci(high='high', low='low', close='close', append=True,length=20)#
        #---ATR
        df.ta.atr(append=True,length=14)#
        #---AD
        df.ta.ad(append=True)#
        #---AO
        df.ta.ao(append=True)#
        #---MOM
        df.ta.mom(append=True,length=10)#
        #---STO-RSI
        df.ta.stochrsi(high='high', low='low', close='close', append=True,length=14,rsi_length=14,k=3,d=3)#
        #---WILLR
        df.ta.willr(append=True,length=14)#
        #---UO
        df.ta.uo(append=True,fast=7,medium=14,slow=28)#
        #---ICHIMOKU
        df.ta.ichimoku(append=True,tenkan=9,kijun=26,senkou=52)#
        #---HMA
        df.ta.hma(close='close', length=16, append=True)#
        #---VWMA
        df.ta.vwma(close='close', volume='volume', length=20, append=True)#
        #---ADX
        df.ta.adx(close='close', volume='volume', length=14, append=True)#
        #---OBV
        df.ta.obv(append=True)#
        #---PSAR
        df.ta.psar(append=True,af0=0.02,af=0.02,max_af=0.2)#
        #---TSI
        df.ta.tsi(append=True,fast=13,slow=25)#
        #---EMA10
        df.ta.ema(length=10, append=True)#
        #---EMA20
        df.ta.ema(length=20, append=True)#
        #---EMA50
        df.ta.ema(length=50, append=True)#
        #---SMA10
        df.ta.sma(length=10, append=True)#
        #---SMA50
        df.ta.sma(length=50, append=True)#
        #---Keltner
        df.ta.kc(append=True)#
        #---CMF
        df.ta.cmf(append=True)#
        #---Rate of Change (ROC) - measures percentage change
        df.ta.roc(append=True, length=5)  # 5-period ROC (faster than 10)
        df.ta.roc(append=True, length=2)  # 2-period ROC (very fast)
        #---Price momentum
        df['price_change_1'] = df['close'].pct_change() * 100
        df['price_change_2'] = df['close'].pct_change(2) * 100
        df['price_change_3'] = df['close'].pct_change(3) * 100
        #---Acceleration (change in momentum)
        df['momentum_acceleration'] = df['price_change_1'].diff()
        #---Volume Weighted Average Price (VWAP)
        df['vwap'] = (df['close'] * df['volume']).cumsum() / df['volume'].cumsum()
        #---Relative Vigor Index (RVGI)
        df.ta.rvgi(append=True, length=14)
        #---BOP (Balance of Power)
        df.ta.bop(append=True)

        #---CHOP (Choppiness Index) - identifies trending vs ranging
        df.ta.chop(append=True, length=14)

#----------------------------------------------------------------------------------------------------------------
        list_dfs.append(df)
          
    except Exception as e:
        print(f'❌error: {e}')
#------------------------------------------------------------------------------------------------------------------------

if __name__ == "__main__":
    print(from_time)
    print(to_time)

    cryptos_to_analyze_causion = ['PHAIRT','ACTIRT', 'YGGIRT','XAIIRT', 'GOATIRT', 'EGLDIRT','TRBIRT', 'MOODENGIRT','QNTIRT']
    crypros_deleted = ['1BBABYDOGEIRT', 'ZENTIRT', 'ZETAIRT','WAXPIRT', 'XCVIRT','UMAIRT',
                        'WINIRT' , 'WAVESIRT' ,'VINEIRT', 'USUALIRT', 'TWTIRT', 'TRACIRT', 'TAPSIRT',
                        'SPXIRT' ,'STGIRT','SAFTIRT','SHIBIRT', 'SFPIRT', 'SENSOIRT', 'RDNTIRT',
                       'RUNEIRT', 'RPLIRT', 'RLCIRT', 'REQIRT', 'RENIRT', 'RBTCIRT', 'PERPIRT',
                       'PYRIRT','POLSIRT', 'PIXFIIRT', 'PIXELIRT', 'PEOPLEIRT','ORBSIRT', 'OXTIRT',
                        'OSMOIRT', 'ORAIIRT', 'OPULIRT', 'OMIRT', 'NKNIRT','NFTIRT', 'NEXOIRT', 'MTLIRT',
                        'MNTIRT', 'MKRIRT', 'MEMEFIIRT', 'KNCIRT','KCSIRT', 'IDIRT','ILVIRT', 'GOATSIRT',
                        'GNOIRT', 'GALAIRT','FLRIRT', 'FXSIRT', 'FLOKIIRT', 'ELONIRT','ELFIRT', 'COWIRT',
                       'CVCIRT', 'CTSIIRT', 'CSIXIRT', 'CHRIRT', 'C98IRT', 'CATSIRT','BANIRT','BNTIRT',
                        'BADGERIRT', 'BTTCIRT', 'BSWIRT', 'BONKIRT', 'BGBIRT','ANIMEIRT','AUCTIONIRT',
                        'ALPHAIRT', 'AUDIOIRT', 'ARKMIRT', 'AMPIRT', 'ALICEIRT', 'AIOZIRT', 'ACHIRT',
                       'BIGTIMEIRT','CYBERIRT', 'BIGTIMEIRT', 'POWRIRT','BALIRT', 'MEIRT', 'WBTCIRT','YFIIRT'
                       ]
                        
    cryptos_to_analyze = [ '1INCHIRT','AAVEIRT', 'ADAIRT', 'AGLDIRT', 'ANKRIRT', 'APEIRT', 'API3IRT', 'ARBIRT',
                           'ATOMIRT', 'AIRT', 'AVAXIRT', 'AXSIRT', 'AEVOIRT','ALGOIRT','APTIRT','ATHIRT','AIXBTIRT',
                           'BANANAIRT', 'BATIRT', 'BCHIRT', 'BICOIRT', 'BLURIRT', 'BTCIRT','BANDIRT',
                           'BNBIRT','BOMEIRT','CAKEIRT', 'CATIIRT', 'CELRIRT', 'CGPTIRT', 'CHZIRT',
                           'COMPIRT', 'COOKIEIRT', 'CRVIRT','CVXIRT','DAIIRT', 'DASHIRT', 'DEXEIRT',
                           'DOGEIRT', 'DOGSIRT', 'DOTIRT', 'DYDXIRT', 'EIGENIRT', 'ENAIRT', 'ENJIRT',
                           'ENSIRT', 'ETCIRT', 'ETHFIIRT','ETHIRT','EGALAIRT','FETIRT', 'FILIRT', 'FORMIRT', 'FLOWIRT',
                           'GLMIRT', 'GMXIRT', 'GMTIRT', 'GRTIRT','GIRT', 'HMSTRIRT', 'HBARIRT','HOTIRT','IMXIRT', 'INJIRT','IOIRT',
                           'JASMYIRT','JSTIRT', 'JTOIRT', 'JUPIRT','KAITOIRT','LDOIRT','LINKIRT', 'LPTIRT', 'LRCIRT',
                           'LTCIRT', 'LAYERIRT', 'MAGICIRT', 'MAJORIRT', 'MANAIRT', 'MASKIRT', 'MDTIRT', 'MEMEIRT',
                           'METISIRT', 'MORPHOIRT','MOVEIRT','NEARIRT', 'NMRIRT', 'NOTIRT', 'NEIROIRT','OMGIRT', 'ONEIRT',
                           'ONDOIRT', 'OPIRT','ORCAIRT','PAXGIRT', 'PEPE2IRT', 'PEPEIRT', 'PENDLEIRT', 'PENGUIRT', 'PNUTIRT',
                           'POLIRT', 'PYTHIRT','PUMPIRT', 'RAYIRT', 'RENDERIRT', 'RSRIRT',
                           'SAMOIRT', 'SANDIRT', 'SEIIRT', 'SKLIRT', 'SLPIRT', 'SNXIRT', 'SSVIRT', 'STORJIRT', 'SUIIRT', 
                           'SUSHIIRT', 'SIRT','SOLIRT','STRKIRT','SNTIRT','SAHARAIRT','SYRUPIRT','TNSRIRT', 'TONIRT', 'TRXIRT',
                           'TIRT','TURBOIRT', 'UNIIRT', 'USDCIRT','VIRTUALIRT','WIFIRT', 'WLDIRT', 'WOOIRT',
                           'WIRT','XAUTIRT', 'XLMIRT', 'XRPIRT', 'XIRT', 'XTZIRT', 'XMRIRT', 
                           'ZROIRT','ZECIRT','ZRXIRT','ZILIRT', '1K_SHIBIRT', '1B_BABYDOGEIRT', 'EDUIRT',
                           'SAFEIRT', 'LINEAIRT', 'KMNOIRT', 'MEWIRT', 'AVNTIRT',
                           'ASTERIRT', 'ZORAIRT', 'METIRT', 'WALIRT', 'BARDIRT', 'BEAMXIRT', 'ATIRT', 'LAIRT', 'SPKIRT', 'HUMAIRT', 'ZAMAIRT',
                           'CHIPIRT', 'AWEIRT', 'BASEDIRT', 'ROBOIRT', 'HOMEIRT', 'GRASSIRT', 'ZBTIRT',
                           '1K_BONKIRT', 'BIOIRT', '2ZIRT', 'BREVIRT', 'PROVEIRT',
                           '1K_CHEEMSIRT', 'ZKIRT', 'CFGIRT', 'USDTIRT', 'GIGGLEIRT', 'WETIRT', 'DOODIRT', 'FLUIDIRT',
                           'REDIRT', 'HYPEIRT', 'EDGEIRT', '1M_PEPEIRT', 'ZENIRT', 'MMTIRT',
                           'KITEIRT', 'EULIRT', 'LITIRT', 'SENTIRT' ,'SUPERIRT', '100K_FLOKIIRT'
                          ]

for symbol in cryptos_to_analyze:
    my_function(symbol)

    #--------------------------

try:
    all_dfs = pd.concat(list_dfs,ignore_index=True)
    # server = 'localhost\\SQLEXPRESS'
    server = 'localhost'  
    database = 'db_Trading'
    table_name = f'tab_calculated_60' 
    params = urllib.parse.quote_plus(f'DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server};DATABASE={database};Trusted_Connection=yes')
    conn_str = f'mssql+pyodbc:///?odbc_connect={params}'
    engine = create_engine(conn_str)
    all_dfs = all_dfs.replace([float('inf'), float('-inf')], None).where(pd.notnull(all_dfs), None)
    all_dfs.to_sql(table_name, engine, index=False, if_exists='replace')
    list_dfs=[]
    #---
except Exception as e:
    print(f'❌ error: {e}')

