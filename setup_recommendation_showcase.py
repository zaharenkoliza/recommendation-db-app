import subprocess
import os

def setup_showcase():
    print("=== Setting up Showcase Student for Recommendation System ===")
    
    sql = [
        "BEGIN;",
        # 1. Ensure group exists
        "INSERT INTO s335141.groups (id) VALUES ('P3321') ON CONFLICT DO NOTHING;",
        
        # 2. Ensure curriculum and sections exist for the showcase
        "INSERT INTO s335141.curricula (id_isu, name, year, degree, head) VALUES (999, 'Искусственный интеллект и машинное обучение', 2025, 'bachelor', 'Захаренко Е.А.') ON CONFLICT (id_isu) DO UPDATE SET name = EXCLUDED.name, year = 2025;",
        
        "INSERT INTO s335141.modules (id_isu, name, type_choose) VALUES (999, 'Специализация AI (Обязательно)', 'все') ON CONFLICT (id_isu) DO NOTHING;",
        "INSERT INTO s335141.modules (id_isu, name, type_choose) VALUES (1000, 'Элективы AI (По выбору)', 'з.е.') ON CONFLICT (id_isu) DO NOTHING;",

        "INSERT INTO s335141.sections (id, position, id_curricula, id_module) VALUES (9999, 1, 999, 999) ON CONFLICT (id) DO NOTHING;",
        "INSERT INTO s335141.sections (id, position, id_curricula, id_module) VALUES (10000, 2, 999, 1000) ON CONFLICT (id) DO NOTHING;",
        
        # 3. Track
        "INSERT INTO s335141.tracks (id, name, number, id_section) VALUES (10, 'Искусственный интеллект в образовании', 1, 9999) ON CONFLICT (id) DO UPDATE SET id_section = EXCLUDED.id_section;",

        # 3.5 Disciplines in Modules
        "INSERT INTO s335141.rpd (id_isu, id_discipline, name, status) VALUES (99991, 6206, 'Линейная алгебра (шоукейс)', 'новая') ON CONFLICT (id_isu) DO NOTHING;",
        "INSERT INTO s335141.disciplines_in_modules (id, implementer, id_module, id_rpd, position, changable) VALUES (99991, 1, 999, 99991, 1, false) ON CONFLICT ON CONSTRAINT uk_rpd_module DO NOTHING;",
        "INSERT INTO s335141.disciplines_in_modules (id, implementer, id_module, id_rpd, position, changable) VALUES (99992, 1, 999, 21451, 2, false) ON CONFLICT ON CONSTRAINT uk_rpd_module DO NOTHING;", 
        "INSERT INTO s335141.disciplines_in_modules (id, implementer, id_module, id_rpd, position, changable) VALUES (99993, 1, 999, 16579, 3, false) ON CONFLICT ON CONSTRAINT uk_rpd_module DO NOTHING;", 
        "INSERT INTO s335141.disciplines_in_modules (id, implementer, id_module, id_rpd, position, changable) VALUES (99994, 1, 999, 52372, 4, false) ON CONFLICT ON CONSTRAINT uk_rpd_module DO NOTHING;", 
        "INSERT INTO s335141.disciplines_in_modules (id, implementer, id_module, id_rpd, position, changable) VALUES (99995, 1, 999, 32911, 5, false) ON CONFLICT ON CONSTRAINT uk_rpd_module DO NOTHING;", 
        "INSERT INTO s335141.disciplines_in_modules (id, implementer, id_module, id_rpd, position, changable) VALUES (99996, 1, 999, 16583, 6, false) ON CONFLICT ON CONSTRAINT uk_rpd_module DO NOTHING;", 
        
        "INSERT INTO s335141.rpd (id_isu, id_discipline, name, status) VALUES (10001, 5910, 'Коммуникации и командообразование', 'новая') ON CONFLICT (id_isu) DO NOTHING;",
        "INSERT INTO s335141.disciplines_in_modules (id, implementer, id_module, id_rpd, position, changable) VALUES (10001, 1, 1000, 10001, 1, true) ON CONFLICT ON CONSTRAINT uk_rpd_module DO NOTHING;",
        "INSERT INTO s335141.rpd (id_isu, id_discipline, name, status) VALUES (10002, 5912, 'Критическое мышление и письмо', 'новая') ON CONFLICT (id_isu) DO NOTHING;",
        "INSERT INTO s335141.disciplines_in_modules (id, implementer, id_module, id_rpd, position, changable) VALUES (10002, 1, 1000, 10002, 2, true) ON CONFLICT ON CONSTRAINT uk_rpd_module DO NOTHING;",
        "INSERT INTO s335141.rpd (id_isu, id_discipline, name, status) VALUES (10003, 5913, 'Информатика (базовый уровень)', 'новая') ON CONFLICT (id_isu) DO NOTHING;",
        "INSERT INTO s335141.disciplines_in_modules (id, implementer, id_module, id_rpd, position, changable) VALUES (10003, 1, 1000, 10003, 3, true) ON CONFLICT ON CONSTRAINT uk_rpd_module DO NOTHING;",

        # 3.6 Semesters
        "DELETE FROM s335141.discp_starts WHERE id_discp_module IN (99991, 99992, 99993, 99994, 99995, 99996, 10001, 10002, 10003);",
        "INSERT INTO s335141.discp_starts (id_discp_module, sem) VALUES (99991, 1);", 
        "INSERT INTO s335141.discp_starts (id_discp_module, sem) VALUES (99992, 1);", 
        "INSERT INTO s335141.discp_starts (id_discp_module, sem) VALUES (99993, 1);", 
        "INSERT INTO s335141.discp_starts (id_discp_module, sem) VALUES (99994, 2);", 
        "INSERT INTO s335141.discp_starts (id_discp_module, sem) VALUES (99995, 3);", 
        "INSERT INTO s335141.discp_starts (id_discp_module, sem) VALUES (99996, 3);", 
        "INSERT INTO s335141.discp_starts (id_discp_module, sem) VALUES (10001, 3);", 
        "INSERT INTO s335141.discp_starts (id_discp_module, sem) VALUES (10002, 3);", 
        "INSERT INTO s335141.discp_starts (id_discp_module, sem) VALUES (10003, 3);",

        # 4. Student
        "INSERT INTO s335141.students (id, name, group_id, track_id, curriculum_id, status_id) VALUES (335200, 'Максим Соколов (Пример)', 'P3321', 10, 999, 1) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, track_id = EXCLUDED.track_id, curriculum_id = EXCLUDED.curriculum_id;",
        
        # 5. Credentials
        "DELETE FROM s335141.appuser WHERE login = 'maksim';",
        "INSERT INTO s335141.appuser (id, login, password, role, student_id) SELECT COALESCE(MAX(id), 0) + 1, 'maksim', 'password', 'STUDENT', 335200 FROM s335141.appuser;",
        
        # 6. Performance
        "DELETE FROM s335141.student_performance WHERE student_id = 335200;",
        "INSERT INTO s335141.student_performance (student_id, discipline_id, grade, status) VALUES (335200, 6206, 5, 'Passed');",
        "INSERT INTO s335141.student_performance (student_id, discipline_id, grade, status) VALUES (335200, 6196, 5, 'Passed');",
        "INSERT INTO s335141.student_performance (student_id, discipline_id, grade, status) VALUES (335200, 6383, 4, 'Passed');",
        "INSERT INTO s335141.student_performance (student_id, discipline_id, grade, status, attempt_number) VALUES (335200, 6150, 2, 'Failed', 1);",
        
        # 7. Manual Prerequisites for next semester courses
        "DELETE FROM s335141.discipline_prerequisites WHERE discipline_id IN (6132, 6230);",
        "INSERT INTO s335141.discipline_prerequisites (discipline_id, prerequisite_id, source) VALUES (6132, 6196, 'manual');", # Stat depends on Math
        "COMMIT;"
    ]
    
    with open("showcase_setup.sql", "w", encoding="utf-8") as f:
        f.write("\n".join(sql))
        
    print("Injecting SQL into Postgres...")
    subprocess.run("docker exec -i itmo_db psql -U postgres -d itmo_db < showcase_setup.sql", shell=True)
    
    print("Running migration to Neo4j...")
    try:
        subprocess.run(["python", "migrate.py"], check=True)
    except:
        subprocess.run(["py", "migrate.py"], check=True)
        
    print("\n=== Showcase Setup Complete! ===")

if __name__ == "__main__":
    setup_showcase()
