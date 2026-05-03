"""
Единый скрипт инициализации системы.
Наполняет PostgreSQL демо-данными и строит граф в Neo4j.

Запуск внутри контейнера:
    python -m app.management.setup_all
"""

from app.management.seed_showcase import seed
from app.management.build_prerequisites import main as build_prereqs

def setup():
    print("🚀 Starting Full System Setup...")
    
    # 1. Наполнение базовыми данными
    seed()
    
    # 2. Анализ и построение графа (уже включает в себя migrate)
    build_prereqs()
    
    print("\n✨ System Setup Successfully Finished!")

if __name__ == "__main__":
    setup()
