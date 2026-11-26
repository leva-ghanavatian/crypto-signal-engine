# =====================================================
# Crypto Profit/Loss Calculator
# =====================================================

def calculate_prices(entry_price, number_of_coins, profit_percent, loss_percent):
    """
    Calculate target prices for profit taking and stop loss
    
    Parameters:
    - entry_price: Your purchase price per coin
    - number_of_coins: How many coins you bought
    - profit_percent: Desired profit percentage (e.g., 10 for 10%)
    - loss_percent: Stop loss percentage (e.g., 5 for 5%)
    
    Returns:
    - Dictionary with all calculated prices and totals
    """
    
    # Calculate total investment
    total_investment = entry_price * number_of_coins
    
    # Calculate profit target price
    profit_price = entry_price * (1 + profit_percent / 100)
    profit_amount_per_coin = entry_price * (profit_percent / 100)
    total_profit = total_investment * (profit_percent / 100)
    
    # Calculate stop loss price
    stop_loss_price = entry_price * (1 - loss_percent / 100)
    loss_amount_per_coin = entry_price * (loss_percent / 100)
    total_loss = total_investment * (loss_percent / 100)
    
    results = {
        'entry_price': entry_price,
        'number_of_coins': number_of_coins,
        'total_investment': total_investment,
        'profit_percent': profit_percent,
        'loss_percent': loss_percent,
        'profit_price': round(profit_price, 2),
        'profit_amount_per_coin': round(profit_amount_per_coin, 2),
        'total_profit': round(total_profit, 2),
        'stop_loss_price': round(stop_loss_price, 2),
        'loss_amount_per_coin': round(loss_amount_per_coin, 2),
        'total_loss': round(total_loss, 2),
        'risk_reward_ratio': round(profit_percent / loss_percent, 2)
    }
    
    return results


def display_results(results):
    """Print the calculated results in a nice format"""
    
    print("=" * 50)
    print("CRYPTO PROFIT/LOSS CALCULATOR")
    print("=" * 50)
    print(f"\nENTRY INFORMATION")
    print(f"   Entry Price:           {results['entry_price']:,.2f} Toman")
    print(f"   Number of Coins:       {results['number_of_coins']:,.4f}")
    print(f"   Total Investment:      {results['total_investment']:,.2f} Toman")
    print(f"   Profit Percent:        {results['profit_percent']}%")
    print(f"   Stop Loss Percent:     {results['loss_percent']}%")
    print(f"   Risk/Reward Ratio:     {results['risk_reward_ratio']}:1")
    
    print(f"\nPROFIT TARGET")
    print(f"   Price:                 {results['profit_price']:,.2f} Toman")
    print(f"   Profit per Coin:       +{results['profit_amount_per_coin']:,.2f} Toman")
    print(f"   TOTAL PROFIT:          +{results['total_profit']:,.2f} Toman")
    
    print(f"\nSTOP LOSS")
    print(f"   Price:                 {results['stop_loss_price']:,.2f} Toman")
    print(f"   Loss per Coin:         -{results['loss_amount_per_coin']:,.2f} Toman")
    print(f"   TOTAL LOSS:            -{results['total_loss']:,.2f} Toman")
    print("=" * 50)


# =====================================================
# ADJUST THESE VARIABLES - CHANGE YOUR VALUES HERE
# =====================================================

# Your entry price (what you paid per coin)
entry_price = 105452

# How many coins you bought
number_of_coins = 5.1

# Adjust these percentages as you want
profit_percent = 3   # Target profit (e.g., 10 = 10% gain)
loss_percent = 3      # Stop loss (e.g., 5 = 5% loss)

# =====================================================
# RUN THE CALCULATION
# =====================================================

# Calculate
results = calculate_prices(entry_price, number_of_coins, profit_percent, loss_percent)

# Display results
display_results(results)

# Key values for further use
print(f"\nprofit_price = {results['profit_price']}")
print(f"stop_loss_price = {results['stop_loss_price']}")
print(f"total_profit = {results['total_profit']}")
print(f"total_loss = {results['total_loss']}")