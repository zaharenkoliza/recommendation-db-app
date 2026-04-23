"""
Роуты авторизации: вход в систему и получение информации о текущем пользователе.
"""
from fastapi import APIRouter, HTTPException, status, Depends
from pydantic import BaseModel
from app.auth import authenticate_user, create_access_token, get_current_user

router = APIRouter(tags=["auth"])


class LoginRequest(BaseModel):
    login: str
    password: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict


@router.post("/login", response_model=LoginResponse)
def login(body: LoginRequest):
    """
    Авторизация пользователя.
    Принимает логин и пароль, возвращает JWT-токен.
    """
    user = authenticate_user(body.login, body.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный логин или пароль"
        )

    token = create_access_token({
        "id": user["id"],
        "login": user["login"],
        "role": user["role"],
        "student_id": user["student_id"],
    })

    return LoginResponse(
        access_token=token,
        user={
            "id": user["id"],
            "login": user["login"],
            "role": user["role"],
            "student_id": user["student_id"],
        }
    )


@router.get("/me")
def get_me(user: dict = Depends(get_current_user)):
    """Возвращает информацию о текущем авторизованном пользователе."""
    return user
