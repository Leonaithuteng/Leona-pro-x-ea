# Leona Pro X EA

Leona Pro X EA is an MT5 automated trading system with a Flutter mobile dashboard and FastAPI control service.

## Repository structure

- `mt5/Leona_Pro_X_EA.mq5` — integrated trading EA
- `mt5/Leona_Pro_X_API_Bridge.mq5` — standalone API bridge
- `backend/main.py` — FastAPI service
- `lib/main.dart` — Flutter dashboard

## Integrated EA

The integrated EA uses:

- M5 execution timeframe
- M15/H1 confirmation
- SMA 20
- RSI 14
- ADX 14
- ATR 14
- MACD 12/26/9
- Dynamic risk-based lot sizing
- Daily loss protection
- Maximum drawdown protection
- Consecutive-loss protection
- Breakeven and trailing stop
- Spread, time and volatility filters
- Remote START/STOP
- Remote CLOSE ALL
- Account heartbeat to the mobile backend

## MT5 setup

1. Open MetaEditor from MT5.
2. Open `MQL5/Experts`.
3. Copy `mt5/Leona_Pro_X_EA.mq5` into the Experts folder.
4. Compile it.
5. In MT5, open **Tools → Options → Expert Advisors**.
6. Enable **Allow WebRequest for listed URL**.
7. Add:
   `https://leona-pro-x-api.onrender.com`
8. Attach **Leona Pro X EA** to the desired Weltrade synthetic symbol.
9. Enter the `DeviceId` and `EaToken` supplied by the registration flow.
10. Enable Algo Trading.

## Safety

Do not use live funds until the EA has been tested on a demo account and the complete mobile-to-MT5 command path has been verified.

The API currently uses in-memory state. PostgreSQL persistence and production authentication are the next backend hardening stage.
