import os
from datetime import datetime, timezone
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, JSON, String, create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./leona_pro_x.db")
connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, connect_args=connect_args, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    username: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Device(Base):
    __tablename__ = "devices"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    device_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    device_name: Mapped[str] = mapped_column(String(100))
    broker: Mapped[str] = mapped_column(String(100), default="Weltrade")
    account: Mapped[str | None] = mapped_column(String(100), nullable=True)
    token: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    status: Mapped[str] = mapped_column(String(30), default="REGISTERED")
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    balance: Mapped[float | None] = mapped_column(Float, nullable=True)
    equity: Mapped[float | None] = mapped_column(Float, nullable=True)
    profit: Mapped[float | None] = mapped_column(Float, nullable=True)
    drawdown: Mapped[float | None] = mapped_column(Float, nullable=True)
    ea_active: Mapped[bool] = mapped_column(Boolean, default=False)
    risk_percent: Mapped[float] = mapped_column(Float, default=1.0)
    lot_size: Mapped[float] = mapped_column(Float, default=0.01)
    sizing_mode: Mapped[str] = mapped_column(String(20), default="RISK")
    sl_points: Mapped[int] = mapped_column(Integer, default=150)
    tp_points: Mapped[int] = mapped_column(Integer, default=250)
    max_daily_loss: Mapped[float] = mapped_column(Float, default=3.0)
    max_drawdown: Mapped[float] = mapped_column(Float, default=10.0)
    open_positions: Mapped[int] = mapped_column(Integer, default=0)
    open_profit: Mapped[float] = mapped_column(Float, default=0.0)
    signal_score: Mapped[int] = mapped_column(Integer, default=0)
    atr: Mapped[float] = mapped_column(Float, default=0.0)
    spread: Mapped[float] = mapped_column(Float, default=0.0)
    symbol: Mapped[str | None] = mapped_column(String(100), nullable=True)


class Command(Base):
    __tablename__ = "commands"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    command_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    device_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    command: Mapped[str] = mapped_column(String(50))
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    status: Mapped[str] = mapped_column(String(30), default="QUEUED")
    message: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Activity(Base):
    __tablename__ = "activity"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    event_type: Mapped[str] = mapped_column(String(50))
    device_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    command_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    status: Mapped[str | None] = mapped_column(String(30), nullable=True)
    message: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


def init_db():
    Base.metadata.create_all(bind=engine)
    migrate_device_columns()


def migrate_device_columns():
    """Add risk columns to older deployments without destroying existing data."""
    inspector = inspect(engine)
    if "devices" not in inspector.get_table_names():
        return
    existing = {col["name"] for col in inspector.get_columns("devices")}
    additions = [
        ("risk_percent", "FLOAT DEFAULT 1.0"),
        ("lot_size", "FLOAT DEFAULT 0.01"),
        ("sizing_mode", "VARCHAR(20) DEFAULT 'RISK'"),
        ("sl_points", "INTEGER DEFAULT 150"),
        ("tp_points", "INTEGER DEFAULT 250"),
        ("max_daily_loss", "FLOAT DEFAULT 3.0"),
        ("max_drawdown", "FLOAT DEFAULT 10.0"),
        ("open_positions", "INTEGER DEFAULT 0"),
        ("open_profit", "FLOAT DEFAULT 0.0"),
        ("signal_score", "INTEGER DEFAULT 0"),
        ("atr", "FLOAT DEFAULT 0.0"),
        ("spread", "FLOAT DEFAULT 0.0"),
        ("symbol", "VARCHAR(100)"),
    ]
    with engine.begin() as conn:
        for name, definition in additions:
            if name not in existing:
                conn.execute(text("ALTER TABLE devices ADD COLUMN " + name + " " + definition))
