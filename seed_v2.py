import random
import subprocess

def run_psql(query):
    cmd = ["docker", "exec", "-i", "itmo_db", "psql", "-U", "postgres", "-d", "itmo_db", "-t", "-A", "-c", query]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]

def seed():
    print("Fetching disciplines and students...")
    discipline_ids = run_psql("SELECT id FROM s335141.disciplines")
    student_ids = run_psql("SELECT id FROM s335141.students")
    
    if not discipline_ids or not student_ids:
        print("Error: No disciplines or students found.")
        return

    sql = ["BEGIN;"]
    
    # 1. Add some logical prerequisites
    # (These IDs are from the previous query results)
    prereqs = [
        (6132, 6196), # Math Stats -> Math Analysis
        (6230, 6132), # ML -> Math Stats
        (6230, 6383), # ML -> Data Processing
        (6150, 6130), # Eng Graphics -> Projection Geometry
        (6138, 6142), # VR Dev -> Functional Programming
    ]
    for d_id, p_id in prereqs:
        sql.append(f"INSERT INTO s335141.discipline_prerequisites (discipline_id, prerequisite_id) VALUES ({d_id}, {p_id}) ON CONFLICT DO NOTHING;")

    # 2. Add progress for existing students
    print(f"Generating progress for {len(student_ids)} students...")
    for s_id in student_ids:
        # Each student completed 5-12 random disciplines
        num_completed = random.randint(5, 12)
        completed = random.sample(discipline_ids, min(num_completed, len(discipline_ids)))
        for d_id in completed:
            grade = random.choice([3, 4, 5])
            sql.append(f"INSERT INTO s335141.student_progress (student_id, discipline_id, grade, is_completed) VALUES ({s_id}, {d_id}, {grade}, true) ON CONFLICT DO NOTHING;")

    sql.append("COMMIT;")
    
    print("Writing seed_v2.sql...")
    with open("seed_v2.sql", "w", encoding="utf-8") as f:
        f.write("\n".join(sql))
    
    print("Executing seed_v2.sql...")
    subprocess.run("cmd /c \"docker exec -i itmo_db psql -U postgres -d itmo_db < seed_v2.sql\"", shell=True)
    print("Seeding complete!")

if __name__ == "__main__":
    seed()
