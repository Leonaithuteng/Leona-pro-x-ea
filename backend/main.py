from datetime import datetime, timedelta, timezone
from typing import Optional
import os
import secrets

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
from jose import jwt

app = FastAPI(title="Leona Pro X EA API", version="1.1.0")

JWT_SECRET = os.getenv("LEONA_JWT_SECRET", "CHANGE_THIS_SECRET_BEFORE_PRODUCTION")
JWT_ALGORITHM = "HS256"

devices = {}
commands = []
activity = []


class LoginRequest(BaseModel):
    username: str
    password: str


class DeviceRegister(BaseModel):
    device_name: str = Field(min_length=1, max_length=100)
    broker: str = "Weltrade"
    account: Optional[str] = None


class CommandRequest(BaseModel):
    command: str
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


def find_device_by_token(token: Optional[str]):
    if not token:
        return None
    for item in devices.values():
        if secrets.compare_digest(item["token"], token):
            return item
    return None


@app.get("/")
def root():
    return {"name": "Leona Pro X EA API", "status": "online", "version": "1.1.0"}


@app.get("/health")
def health():
    return {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}


@app.post("/api/v1/auth/login")
def login(request: LoginRequest):
    if not request.username or not request.password:
        raise HTTPException(status_code=400, detail="Username and password are required")
    return {"access_token": create_token(request.username), "token_type": "bearer"}


@app.post("/api/v1/devices/register")
def register_device(request: DeviceRegister, x_ea_token: Optional[str] = Header(default=None)):
    token = x_ea_token or secrets.token_urlsafe(32)
    device_id = secrets.token_hex(8)
    devices[device_id] = {
        "device_id": device_id,
        "device_name": request.device_name,
        "broker": request.broker,
        "account": request.account,
        "token": token,
        "status": "REGISTERED",
        "last_seen": None,
        "balance": None,
        "equity": None,
        "profit": None,
        "drawdown": None,
        "ea_active": False,
    }
    return {"device_id": device_id, "ea_token": token, "status": "REGISTERED"}


@app.get("/api/v1/ea/status")
def ea_status():
    if not devices:
        return {"connected": False, "ea_active": False, "balance": None, "equity": None, "profit": None, "drawdown": None}
    device = next(iter(devices.values()))
    return {
        "connected": device["last_seen"] is not None,
        "ea_active": device.get("ea_active", False),
        "balance": device.get("balance"),
        "equity": device.get("equity"),
        "profit": device.get("profit"),
        "drawdown": device.get("drawdown"),
        "last_seen": device["last_seen"],
    }


@app.post("/api/v1/ea/heartbeat")
def heartbeat(heartbeat_data: Heartbeat, x_ea_token: Optional[str] = Header(default=None)):
    device = find_device_by_token(x_ea_token)
    if device is None:
        raise HTTPException(status_code=401, detail="Invalid EA token")

    now = datetime.now(timezone.utc).isoformat()
    device.update({
        "last_seen": now,
        "balance": heartbeat_data.balance,
        "equity": heartbeat_data.equity,
        "profit": heartbeat_data.profit,
        "drawdown": heartbeat_data.drawdown,
        "ea_active": heartbeat_data.ea_active,
    })
    return {"status": "OK", "server_time": now}


@app.post("/api/v1/ea/command")
def create_command(request: CommandRequest):
    allowed = {"START_ROBOT", "STOP_ROBOT", "CLOSE_ALL", "UPDATE_RISK"}
    if request.command not in allowed:
        raise HTTPException(status_code=400, detail="Unsupported command")

    command = {
        "command_id": secrets.token_hex(12),
        "command": request.command,
        "payload": request.payload,
        "status": "QUEUED",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    commands.append(command)
    return command


@app.get("/api/v1/devices/{device_id}/commands")
def get_commands(device_id: str, x_ea_token: Optional[str] = Header(default=None)):
    device = devices.get(device_id)
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    if not x_ea_token or not secrets.compare_digest(device["token"], x_ea_token):
        raise HTTPException(status_code=401, detail="Invalid EA token")

    return [command for command in commands if command["status"] == "QUEUED"]


@app.post("/api/v1/commands/result")
def command_result(result: CommandResult, x_ea_token: Optional[str] = Header(default=None)):
    device = find_device_by_token(x_ea_token)
    if device is None:
        raise HTTPException(status_code=401, detail="Invalid EA token")

    for command in commands:
        if command["command_id"] == result.command_id:
            command["status"] = result.status
            command["message"] = result.message
            activity.append({
                "type": "COMMAND_RESULT",
                "device_id": device["device_id"],
                "command_id": result.command_id,
                "status": result.status,
                "message": result.message,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })
            return {"status": "RECORDED", "command_id": result.command_id}

    raise HTTPException(status_code=404, detail="Command not found")


@app.get("/api/v1/activity")
def get_activity():
    return {"items": activity[-100:], "count": len(activity)}
