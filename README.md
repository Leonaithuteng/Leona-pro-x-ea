# Leona Pro X EA

Leona Pro X EA is an MT5 automated trading system with a Flutter mobile dashboard and FastAPI control service.

## Repository structure

- `mt5/Leona_Pro_X_EA.mq5` — integrated trading EA
- `mt5/Leona_Pro_X_EA_LIVE_v32_FIXED.mq5` — current API-connected v3.2 synthetic scalper with smart spread and ATR exits
- `mt5/Leona_Pro_X_API_Bridge.mq5` — standalone API bridge
- `backend/main.py` — FastAPI service
- `lib/main.dart` — Flutter dashboard

## Integrated EA

The current live EA uses:

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
8. Attach **Leona_Pro_X_EA_LIVE_v32_FIXED** to the desired Weltrade synthetic symbol.
9. Sign in to the Android app, use the registered MT5 device, then enter its `DeviceId` and `EaToken` in the EA inputs.
10. Add `https://leona-pro-x-api.onrender.com` to the MT5 WebRequest allow-list and enable Algo Trading.

## Safety

Do not use live funds until the EA has been tested on a demo account and the complete mobile-to-MT5 command path has been verified.

The API now uses SQLAlchemy persistence with PostgreSQL support on Render and SQLite fallback for development. Mobile API routes require a bearer session, devices are associated with users, and commands are scoped to the target device.

### Required Render environment variables

- `DATABASE_URL` — PostgreSQL connection string
- `LEONA_JWT_SECRET` — long random JWT signing secret
- `LEONA_ADMIN_USERNAME` — bootstrap administrator username
- `LEONA_ADMIN_PASSWORD` — bootstrap administrator password

Do not commit these values to GitHub. The EA still authenticates separately with its device token.


### v3.2 live fixes

- API heartbeat and remote commands retained.
- Smart synthetic spread filter uses live Bid/Ask and SYMBOL_POINT with ATR-relative limits.
- ATR-based SL/TP with configurable risk-reward and synthetic-safe bounds.
- Mobile dashboard authenticates against the FastAPI service and reads real EA heartbeat state.
