import random
import subprocess

def run_sql(query):
    cmd = ["docker", "exec", "-i", "itmo_db", "psql", "-U", "postgres", "-d", "itmo_db", "-c", query]
    subprocess.run(cmd, shell=True)

def seed_showcase_v3():
    print("Reforming showcase data...")
    # Clear old data
    run_sql("DELETE FROM s335141.student_progress WHERE student_id > 100000 OR student_id BETWEEN 2000 AND 3000;")
    run_sql("DELETE FROM s335141.students WHERE id > 100000 OR id BETWEEN 2000 AND 3000;")

    sql = ["BEGIN;"]

    # 1. Create realistic groups
    groups = ['P3321', 'P3322', 'K3220', 'K3221', 'M3101']
    for g in groups:
        sql.append(f"INSERT INTO s335141.groups (id) VALUES ('{g}') ON CONFLICT DO NOTHING;")

    # 2. Showcase Personas with 6-digit ISU and Tracks
    # Tracks: 10 (AI), 11 (Game Dev), 7 (Design)
    personas = [
        # ISU, Name, Group, Track_ID, Completed_Disciplines
        (335141, 'Алексей Иванов (AI)', 'P3321', 10, [6196]), 
        (336222, 'Мария Петрова (GameDev)', 'K3220', 11, [6130]),
        (337333, 'Дмитрий Сидоров (Design)', 'P3322', 7, [6130]),
        (408111, 'Елена Соколова (AI Pro)', 'P3321', 10, [6196, 6132, 6383]),
        (409222, 'Николай Волков (GameDev Pro)', 'K3220', 11, [6130, 6150, 6142]),
    ]

    for isu, name, group, track_id, completed in personas:
        sql.append(f"INSERT INTO s335141.students (id, name, group_id, track_id, status_id) VALUES ({isu}, '{name}', '{group}', {track_id}, 1) ON CONFLICT (id) DO UPDATE SET status_id = 1;")
        for d_id in completed:
            # Успешная сдача
            sql.append(f"INSERT INTO s335141.student_performance (student_id, discipline_id, grade, status) VALUES ({isu}, {d_id}, 5, 'Passed') ON CONFLICT DO NOTHING;")

    # Добавляем долг Николаю Волкову (409222) в единую таблицу
    sql.append("UPDATE s335141.students SET status_id = 4 WHERE id = 409222;") # Кандидат на отчисление
    sql.append("INSERT INTO s335141.student_performance (student_id, discipline_id, grade, status, attempt_number) VALUES (409222, 6196, 2, 'Failed', 1) ON CONFLICT DO NOTHING;")

    sql.append("COMMIT;")

    with open("showcase_v3.sql", "w", encoding="utf-8") as f:
        f.write("\n".join(sql))

    print("Injecting new ISU-based data...")
    subprocess.run("cmd /c \"docker exec -i itmo_db psql -U postgres -d itmo_db < showcase_v3.sql\"", shell=True)
    
    print("Updating Knowledge Graph...")
    subprocess.run("py migrate.py", shell=True)
    print("Migration successful!")

if __name__ == "__main__":
    seed_showcase_v3()
