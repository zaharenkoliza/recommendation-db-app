import subprocess
import sys

def run_command(cmd, description):
    print(f"--- {description} ---")
    # Using shell=True for windows command execution compatibility
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, encoding='utf-8')
    if result.returncode == 0:
        print(result.stdout)
    else:
        print(f"Ошибка: {result.stderr}")
        # Not exiting immediately to allow user to see output
        return False
    return True

def main():
    print("🚀 Запуск автоматического построения графа пререквизитов...")

    # 1. SQL запрос для генерации связей в PostgreSQL
    # Логика: если дисциплина r1 находится в обязательном модуле m1, 
    # который идет раньше модуля m2 (где находится r2) в том же учебном плане,
    # то r1 становится пререквизитом для r2.
    sql_query = """
    INSERT INTO s335141.discipline_prerequisites (discipline_id, prerequisite_id)
    SELECT DISTINCT r2.id_discipline, r1.id_discipline
    FROM s335141.sections s1
    JOIN s335141.sections s2 ON s1.id_curricula = s2.id_curricula
    JOIN s335141.modules m1 ON s1.id_module = m1.id_isu
    JOIN s335141.disciplines_in_modules dim1 ON dim1.id_module = m1.id_isu
    JOIN s335141.rpd r1 ON dim1.id_rpd = r1.id_isu
    JOIN s335141.modules m2 ON s2.id_module = m2.id_isu
    JOIN s335141.disciplines_in_modules dim2 ON dim2.id_module = m2.id_isu
    JOIN s335141.rpd r2 ON dim2.id_rpd = r2.id_isu
    WHERE s1.position < s2.position 
      AND m1.type_choose = 'все'
      AND r1.id_discipline IS NOT NULL 
      AND r2.id_discipline IS NOT NULL
      AND r1.id_discipline <> r2.id_discipline
    ON CONFLICT DO NOTHING;
    """
    
    # Cleaning query for single-line execution in docker exec
    clean_sql = " ".join(sql_query.split())
    psql_cmd = f'docker exec -i itmo_db psql -U postgres -d itmo_db -c "{clean_sql}"'
    
    if run_command(psql_cmd, "Генерация пререквизитов в PostgreSQL"):
        # 2. Запуск миграции в Neo4j
        run_command("py migrate.py", "Синхронизация данных с Neo4j (Knowledge Graph)")
        print("\n✅ Успех! Теперь граф рекомендаций учитывает структуру учебных планов.")
    else:
        print("\n❌ Произошла ошибка при работе с базой данных.")

if __name__ == "__main__":
    main()
