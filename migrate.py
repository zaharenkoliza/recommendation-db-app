import subprocess
import json
import sys
from neo4j import GraphDatabase

def run_psql(query):
    cmd = [
        "docker", "exec", "itmo_db", "psql", "-U", "postgres", "-d", "itmo_db", "-A", "-t", "-q", "-c",
        f"SELECT json_agg(t) FROM ({query}) t"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
    if result.returncode != 0:
        return []
    raw = "".join(result.stdout.splitlines()).strip()
    if not raw: return []
    try: return json.loads(raw)
    except: return []

def migrate():
    print("Fetching data...")
    programs = run_psql("SELECT id_isu as id, name, year FROM s335141.curricula")
    tracks = run_psql("SELECT id, name, id_section FROM s335141.tracks")
    modules = run_psql("SELECT id_isu as id, name FROM s335141.modules")
    disciplines = run_psql("SELECT id, name FROM s335141.disciplines")
    students = run_psql("SELECT id, name as full_name, group_id FROM s335141.students")
    
    sections = run_psql("SELECT id, id_curricula, id_module FROM s335141.sections")
    
    # New tables
    prereqs = run_psql("SELECT discipline_id, prerequisite_id FROM s335141.discipline_prerequisites")
    progress = run_psql("SELECT student_id, discipline_id FROM s335141.student_performance WHERE status = 'Passed'")
    debts = run_psql("SELECT student_id, discipline_id FROM s335141.student_performance WHERE status = 'Failed'")

    driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))
    with driver.session() as session:
        print("Syncing nodes...")
        session.run("MATCH (n) DETACH DELETE n")
        session.run("UNWIND $data AS row CREATE (n:Program {id: row.id, name: row.name, year: row.year})", data=programs)
        session.run("UNWIND $data AS row CREATE (n:Track {id: row.id, name: row.name})", data=tracks)
        session.run("UNWIND $data AS row CREATE (n:Module {id: row.id, name: row.name})", data=modules)
        session.run("UNWIND $data AS row CREATE (n:Discipline {id: row.id, name: row.name})", data=disciplines)
        session.run("UNWIND $data AS row CREATE (n:Student {id: row.id, full_name: row.full_name})", data=students)

        print("Syncing basic relationships...")
        session.run("UNWIND $data AS row MATCH (p:Program {id: row.id_curricula}), (m:Module {id: row.id_module}) MERGE (p)-[:CONTAINS_MODULE]->(m)", data=sections)
        
        track_to_module = run_psql("SELECT t.id as track_id, s.id_module FROM s335141.tracks t JOIN s335141.sections s ON t.id_section = s.id")
        session.run("UNWIND $data AS row MATCH (t:Track {id: row.track_id}), (m:Module {id: row.id_module}) MERGE (t)-[:HAS_MODULE]->(m)", data=track_to_module)

        disc_to_mod = run_psql("SELECT r.id_discipline, dim.id_module FROM s335141.rpd r JOIN s335141.disciplines_in_modules dim ON r.id_isu = dim.id_rpd")
        session.run("UNWIND $data AS row MATCH (d:Discipline {id: row.id_discipline}), (m:Module {id: row.id_module}) MERGE (d)-[:PART_OF]->(m)", data=disc_to_mod)
        
        session.run("MATCH (t:Track)-[:HAS_MODULE]->(m:Module)<-[:PART_OF]-(d:Discipline) MERGE (t)-[:INCLUDES]->(d)")

        print("Syncing prerequisites, progress and debts...")
        session.run("UNWIND $data AS row MATCH (d:Discipline {id: row.discipline_id}), (p:Discipline {id: row.prerequisite_id}) MERGE (d)-[:REQUIRES]->(p)", data=prereqs)
        session.run("UNWIND $data AS row MATCH (s:Student {id: row.student_id}), (d:Discipline {id: row.discipline_id}) MERGE (s)-[:COMPLETED]->(d)", data=progress)
        session.run("UNWIND $data AS row MATCH (s:Student {id: row.student_id}), (d:Discipline {id: row.discipline_id}) MERGE (s)-[:HAS_DEBT]->(d)", data=debts)

    driver.close()
    print("Migration complete!")

if __name__ == "__main__":
    migrate()
