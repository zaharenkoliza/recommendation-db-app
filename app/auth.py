"""
Модуль авторизации: JWT-токены, проверка пароля, зависимости FastAPI.
"""
import jwt
from datetime import datetime, timedelta
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.database import get_pg_conn

# ── Настройки ──────────────────────────────────────────────
SECRET_KEY = "itmo-academic-portal-secret-key-2026"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 часа

security = HTTPBearer()


# ── Работа с токенами ──────────────────────────────────────
def create_access_token(data: dict) -> str:
    """Создает JWT-токен с данными пользователя."""
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> dict:
    """Декодирует и проверяет JWT-токен."""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Токен истёк"
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Невалидный токен"
        )


# ── Зависимости FastAPI ───────────────────────────────────
def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    """
    Зависимость: извлекает текущего пользователя из JWT-токена.
    Возвращает dict с полями: id, login, role, student_id.
    """
    payload = decode_token(credentials.credentials)
    return {
        "id": payload.get("id"),
        "login": payload.get("login"),
        "role": payload.get("role"),
        "student_id": payload.get("student_id"),
    }


def require_admin(user: dict = Depends(get_current_user)) -> dict:
    """Зависимость: пропускает только пользователей с ролью ADMIN."""
    if user.get("role") != "ADMIN":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: требуется роль Администратор"
        )
    return user


def require_student(user: dict = Depends(get_current_user)) -> dict:
    """Зависимость: пропускает только пользователей с ролью STUDENT."""
    if user.get("role") != "STUDENT":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Доступ запрещён: требуется роль Студент"
        )
    return user


# ── Работа с БД ────────────────────────────────────────────
def authenticate_user(login: str, password: str) -> dict | None:
    """
    Проверяет логин/пароль в таблице appuser.
    Возвращает данные пользователя или None.
    """
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT id, login, password, role, student_id FROM s335141.appuser WHERE login = %s",
            (login,)
        )
        row = cur.fetchone()
        if not row:
            return None

        stored_password = row[2]
        # Простая проверка пароля (в продакшене нужен bcrypt)
        if password != stored_password:
            return None

        return {
            "id": row[0],
            "login": row[1],
            "role": row[3],
            "student_id": row[4],
        }
    finally:
        conn.close()
