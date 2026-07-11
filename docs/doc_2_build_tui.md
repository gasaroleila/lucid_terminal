# Lucid TUI

The terminal dashboard running on top of Bonsai_term library. Frontend of lucid stystem app.

# Design

The dashboard design is shown below;
![1783801064982](image/doc_2_build_tui/1783801064982.png)

# Components

## Top Bar

orienting context. The instrument you're focused on (AAPL), a session clock, and the health of your market data feed. That green "feed" dot and the 0.4ms latency number tell you the prices below are live and current. If the dot went red or latency spiked, you'd stop trusting everything on the screen — that's why it sits at the very top.

## Order Book

This is every resting buy and sell order in the market, stacked by price. The red rows on top are asks (people willing to sell), the green rows on the bottom are bids (people willing to buy). Price runs down the middle, size is how much is available at each price, and the bars on the right are just a visual sense of where the volume is concentrated. The dividing line in the middle shows the spread (0.02 — the gap between the best buy and best sell) and the mid price (187.20, roughly "fair" right now).

## Position

what you currently own. Each row is a symbol, how much you hold (+1,200 means long 1,200 shares; -500 means short), and the unrealized P&L on that holding — money you'd make or lose if you closed it right now at the current price. Green is winning, red is losing.

## Risk

your aggregate exposure, summed across everything. Net delta is your overall directional bet (how much you gain per $1 the market moves). Vega is your exposure to volatility. Gross exposure is total capital at risk. These are the numbers that tell you how much trouble you could be in if the market moves against you, regardless of which individual positions caused it.

## P&L

the scoreboard. Your total profit or loss for the day, split into realized (already locked in from closed trades) and unrealized (still open, could still swing). This is the single number most traders glance at most often.

## Order Entry

how you act. Consists of two actions (buy/sell), a quantity field, and a limit price field that a user types in. The user presses F1 to buy after typing in these values or F2 to Sell. The "Working: 2" means you have two orders resting in the market that haven't filled yet. The hotkeys (F1/F2/esc) reflect that real trading is keyboard-driven users don't have time to reach for a mouse.

## Bottom Bar

plumbing health. Confirmation your connection to the venue is alive, how many messages you've processed, whether any data was dropped, and risk-limit warnings. That amber "vega limit 80%" is a heads-up that you're approaching a preset ceiling on volatility exposure — a nudge to slow down before a system or risk manager stops you.
