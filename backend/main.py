from datetime import datetime, timedelta, timezone
from typing import Optional
import os
import secrets

from fastapi import FastAPI, Header, HTTPException, Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from jose import jwt, JWTError
from passlib.context import CryptContext
from sqlalchemy import select, desc

from .database import SessionLocal, init_db, User, Device, Command, Activity

app = FastAPI(title="Leona Pro X EA API", version="1.3.0")

JWT_SECRET = os.getenv("LEONA_JWT_SECRET")
if not JWT_SECRET:
    JWT_SECRET = "DEV_ONLY_CHANGE_ME"
JWT_ALGORITHM = "HS256"
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer = HTTPBearer(auto_error=False)

@app.on_event("startup")
def startup():
    init_db()
    bootstrap_admin()

class LoginRequest(BaseModel):
    username: str
    password: str

class DeviceRegister(BaseModel):
    device_name: str = Field(min_length=1, max_length=100)
    broker: str = "Weltrade"
    account: Optional[str] = None

class CommandRequest(BaseModel):
    command: str
    device_id: Optional[str] = None
    payload: dict = {}

class CommandResult(BaseModel):
    command_id: str
    status: str
    message: Optional[str] = None

class Heartbeat(BaseModel):
    balance: Optional[float] = None
    equity: Optional[float] = None
    profit: Optional[float] = None
    drawdown: Optional[float] = None
    ea_active: bool = False

def create_token(username: str) -> str:
    expires = datetime.now(timezone.utc) + timedelta(hours=12)
    return jwt.encode({"sub": username, "exp": expires}, JWT_SECRET, algorithm=JWT_ALGORITHM)

def bootstrap_admin():
    username = os.getenv("LEONA_ADMIN_USERNAME")
    password = os.getenv("LEONA_ADMIN_PASSWORD")
    if not username or not password:
        return
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.username == username))
        if user is None:
            db.add(User(username=username, password_hash=pwd_context.hash(password), active=True))
            db.commit()

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="Authentication required")
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        username = payload.get("sub")
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    if not username:
        raise HTTPException(status_code=401, detail="Invalid session")
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.username == username))
        if user is None or not user.active:
            raise HTTPException(status_code=401, detail="User account unavailable")
        return user

def find_device_by_token(db, token: Optional[str]):
    if not token:
        return None
    return db.scalar(select(Device).where(Device.token == token))

@app.get("/")
def root():
    return {"name": "Leona Pro X EA API", "status": "online", "version": "1.3.0"}

@app.get("/health")
def health():
    with SessionLocal() as db:
        db.execute(select(Device).limit(1))
    return {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}

@app.post("/api/v1/auth/login")
def login(request: LoginRequest):
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.username == request.username))
        if user is None or not user.active or not pwd_context.verify(request.password, user.password_hash):
            raise HTTPException(status_code=401, detail="Invalid username or password")
    return {"access_token": create_token(request.username), "token_type": "bearer"}

@app.get("/api/v1/auth/me")
def me(user: User = Depends(get_current_user)):
    return {"username": user.username, "active": user.active}

@app.post("/api/v1/devices/register")
def register_device(request: DeviceRegister, user: User = Depends(get_current_user), x_ea_token: Optional[str] = Header(default=None)):
    with SessionLocal() as db:
        token = x_ea_token or secrets.token_urlsafe(32)
        device_id = secrets.token_hex(8)
        device = Device(user_id=user.id, device_id=device_id, device_name=request.device_name,
                        broker=request.broker, account=request.account, token=token, status="REGISTERED")
        db.add(device)
        db.commit()
        return {"device_id": device_id, "ea_token": token, "status": "REGISTERED"}

@app.get("/api/v1/devices")
def list_devices(user: User = Depends(get_current_user)):
    with SessionLocal() as db:
        rows = db.scalars(select(Device).where(Device.user_id == user.id).order_by(desc(Device.id))).all()
        return {"items": [{"device_id": d.device_id, "device_name": d.device_name, "broker": d.broker,
                           "account": d.account, "status": d.status, "last_seen": d.last_seen.isoformat() if d.last_seen else None,
                           "balance": d.balance, "equity": d.equity, "profit": d.profit, "drawdown": d.drawdown,
                           "ea_active": d.ea_active} for d in rows]}

@app.get("/api/v1/ea/status")
def ea_status(user: User = Depends(get_current_user)):
    with SessionLocal() as db:
        device = db.scalar(select(Device).where(Device.user_id == user.id).order_by(desc(Device.id)))
        if device is None:
            return {"connected": False, "ea_active": False, "balance": None, "equity": None, "profit": None, "drawdown": None}
        connected = device.last_seen is not None and (datetime.now(timezone.utc) - device.last_seen).total_seconds() < 30
        return {"connected": connected, "ea_active": device.ea_active, "balance": device.balance,
                "equity": device.equity, "profit": device.profit, "drawdown": device.drawdown,
                "device_id": device.device_id, "last_seen": device.last_seen.isoformat() if device.last_seen else None}

@app.post("/api/v1/ea/heartbeat")
def heartbeat(heartbeat_data: Heartbeat, x_ea_token: Optional[str] = Header(default=None)):
    with SessionLocal() as db:
        device = find_device_by_token(db, x_ea_token)
        if device is None:
            raise HTTPException(status_code=401, detail="Invalid EA token")
        device.last_seen = datetime.now(timezone.utc)
        device.balance = heartbeat_data.balance
        device.equity = heartbeat_data.equity
        device.profit = heartbeat_data.profit
        device.drawdown = heartbeat_data.drawdown
        device.ea_active = heartbeat_data.ea_active
        device.status = "ONLINE"
        db.commit()
        return {"status": "OK", "server_time": datetime.now(timezone.utc).isoformat()}

@app.post("/api/v1/ea/command")
def create_command(request: CommandRequest, user: User = Depends(get_current_user)):
    allowed = {"START_ROBOT", "STOP_ROBOT", "CLOSE_ALL", "UPDATE_RISK"}
    if request.command not in allowed:
        raise HTTPException(status_code=400, detail="Unsupported command")
    with SessionLocal() as db:
        device = None
        if request.device_id:
            device = db.scalar(select(Device).where(Device.device_id == request.device_id, Device.user_id == user.id))
        else:
            device = db.scalar(select(Device).where(Device.user_id == user.id).order_by(desc(Device.id)))
        if device is None:
            raise HTTPException(status_code=404, detail="No trading device registered")
        command = Command(command_id=secrets.token_hex(12), device_id=device.device_id,
                          command=request.command, payload=request.payload, status="QUEUED")
        db.add(command)
        db.commit()
        db.refresh(command)
        return {"command_id": command.command_id, "device_id": device.device_id, "command": command.command,
                "payload": command.payload, "status": command.status, "created_at": command.created_at.isoformat()}

@app.get("/api/v1/devices/{device_id}/commands")
def get_commands(device_id: str, x_ea_token: Optional[str] = Header(default=None)):
    with SessionLocal() as db:
        device = db.scalar(select(Device).where(Device.device_id == device_id))
        if device is None or not x_ea_token or not secrets.compare_digest(device.token, x_ea_token):
            raise HTTPException(status_code=401, detail="Invalid device credentials")
        rows = db.scalars(select(Command).where(Command.device_id == device_id, Command.status == "QUEUED").order_by(Command.id)).all()
        return [{"command_id": c.command_id, "command": c.command, "payload": c.payload,
                 "status": c.status, "created_at": c.created_at.isoformat()} for c in rows]

@app.post("/api/v1/commands/result")
def command_result(result: CommandResult, x_ea_token: Optional[str] = Header(default=None)):
    with SessionLocal() as db:
        device = find_device_by_token(db, x_ea_token)
        if device is None:
            raise HTTPException(status_code=401, detail="Invalid EA token")
        command = db.scalar(select(Command).where(Command.command_id == result.command_id, Command.device_id == device.device_id))
        if command is None:
            raise HTTPException(status_code=404, detail="Command not found")
        command.status = result.status
        command.message = result.message
        command.completed_at = datetime.now(timezone.utc)
        db.add(Activity(event_type="COMMAND_RESULT", device_id=device.device_id,
                        command_id=command.command_id, status=result.status, message=result.message))
        db.commit()
        return {"status": "RECORDED", "command_id": result.command_id}

@app.get("/api/v1/activity")
def get_activity(user: User = Depends(get_current_user)):
    with SessionLocal() as db:
        device_ids = [d.device_id for d in db.scalars(select(Device).where(Device.user_id == user.id)).all()]
        rows = db.scalars(select(Activity).where(Activity.device_id.in_(device_ids)).order_by(desc(Activity.id)).limit(100)).all() if device_ids else []
        return {"items": [{"type": a.event_type, "device_id": a.device_id, "command_id": a.command_id,
                           "status": a.status, "message": a.message, "timestamp": a.created_at.isoformat()} for a in rows], "count": len(rows)}
