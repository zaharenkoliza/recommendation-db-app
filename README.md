# ITMO SmartRec (Educational Program Management System)

Информационная система управления образовательной программой с гибридной архитектурой (PostgreSQL + Neo4j). Система позволяет не только хранить данные об учебных планах, но и проводить семантический анализ программы, проверять пререквизиты и давать интеллектуальные рекомендации студентам.

## 📚 Документация по разделам

*   [**PRESENTATION_PLAN.md**](./PRESENTATION_PLAN.md) — План защиты проекта по дисциплине "Базы данных".
*   [**ALGORITHM.md**](./ALGORITHM.md) — Описание алгоритма построения «умных» пререквизитов (Jaccard similarity, Transitive reduction).
*   [**Backend API (app/)**](./app/README.md) — Документация серверной части (FastAPI, структура роутов, логика рекомендаций).
*   [**Frontend Client (frontend/)**](./frontend/README.md) — Документация клиентской части (React, структура интерфейсов).

## 🏗 Архитектура

Проект состоит из трех основных слоев:
1.  **PostgreSQL (Relational Layer)**: Хранит основные структурированные данные (Учебные планы, дисциплины, треки, оценки студентов). Гарантирует консистентность данных. Схема создается через `db/init.sql`.
2.  **Neo4j (Knowledge Graph Layer)**: Используется как графовая надстройка. Строит сложные цепочки зависимостей (пререквизиты), анализирует траектории и формирует рекомендации.
3.  **FastAPI + React**: Бэкенд, объединяющий базы данных, и современный фронтенд для удобного взаимодействия студентов и администраторов.

## 📂 Структура проекта

```
recommendation-db-app/
├── db/                      # Инициализация PostgreSQL (DDL + данные)
│   └── init.sql
├── app/                     # Бэкенд (FastAPI)
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py
│   ├── database.py
│   ├── auth.py
│   ├── routes/              # API эндпоинты
│   └── management/          # Управляющие скрипты (запускаются внутри контейнера)
│       ├── migrate.py       # ETL: PostgreSQL → Neo4j
│       ├── build_prerequisites.py  # Генерация умных пререквизитов
│       └── seed_showcase.py # Создание демо-данных
├── frontend/                # Фронтенд (React + Vite)
│   ├── Dockerfile
│   └── src/
├── docker-compose.yml
└── README.md
```

## 🚀 Быстрый старт (Docker Compose)

### 1. Запуск инфраструктуры
Склонируйте репозиторий и запустите все сервисы:
```bash
docker compose up -d --build
```

### 2. Первый запуск (Инициализация данных)
Чтобы наполнить систему демонстрационными данными и построить граф пререквизитов, запустите единый скрипт настройки:
```bash
docker exec -it itmo_backend python -m app.management.setup_all
```

### 3. Доступ к сервисам
После сборки и инициализации будут доступны:
*   **Frontend (UI)**: [http://localhost:3000](http://localhost:3000) (логин: `maksim`, пароль: `password`)
*   **Backend API**: [http://localhost:8000/docs](http://localhost:8000/docs) (Swagger UI)
*   **Neo4j Browser**: [http://localhost:7474](http://localhost:7474) (login: `neo4j`, pass: `password`)
*   **PostgreSQL**: `localhost:5433` (db: `itmo_db`, user: `postgres`, password: `rootpassword`)

## 🔄 Жизненный цикл данных

*   **Автоматическая синхронизация**: Теперь вам не нужно вручную запускать скрипты при изменении данных через интерфейс. Бэкенд автоматически обновляет граф в Neo4j после каждого изменения в PostgreSQL.
*   **Ручное управление (для разработчиков)**:
    ```bash
    # Полная пересборка графа и анализ пререквизитов
    docker exec -it itmo_backend python -m app.management.setup_all
    
    # Только синхронизация PostgreSQL -> Neo4j
    docker exec -it itmo_backend python -m app.management.migrate
    ```
