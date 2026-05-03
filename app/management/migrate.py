"""
ETL: PostgreSQL → Neo4j
Синхронизация данных из реляционной базы в графовую.

Запуск внутри контейнера:
    python -m app.management.migrate
"""

from neo4j import GraphDatabase
from app.database import get_pg_conn, settings


def run_query(query):
    """Выполнить SQL-запрос и вернуть результат как список словарей."""
    conn = get_pg_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT json_agg(t) FROM ({query}) t")
            result = cur.fetchone()[0]
            return result if result else []
    finally:
        conn.close()


def migrate():
    print("Fetching data...")
    programs = run_query("SELECT id_isu as id, name, year FROM s335141.curricula")
    tracks = run_query("SELECT id, name, id_section FROM s335141.tracks")
    modules = run_query("SELECT id_isu as id, name, type_choose FROM s335141.modules")
    disciplines = run_query("""
        SELECT d.id, d.name, COALESCE(json_agg(DISTINCT ds.sem) FILTER (WHERE ds.sem IS NOT NULL), '[]') as semesters
        FROM s335141.disciplines d
        LEFT JOIN s335141.rpd r ON r.id_discipline = d.id
        LEFT JOIN s335141.disciplines_in_modules dim ON dim.id_rpd = r.id_isu
        LEFT JOIN s335141.discp_starts ds ON ds.id_discp_module = dim.id
        GROUP BY d.id, d.name
    """)
    students = run_query("SELECT id, name as full_name, group_id, curriculum_id FROM s335141.students")
    sections = run_query("SELECT id, id_curricula, id_module FROM s335141.sections")

    # Новые таблицы
    prereqs = run_query("SELECT discipline_id, prerequisite_id, source FROM s335141.discipline_prerequisites")
    progress = run_query("SELECT student_id, discipline_id FROM s335141.student_performance WHERE status = 'Passed'")
    debts = run_query("SELECT student_id, discipline_id FROM s335141.student_performance WHERE status = 'Failed'")

    driver = GraphDatabase.driver(settings.NEO4J_URI, auth=(settings.NEO4J_USER, settings.NEO4J_PASSWORD))

    def sync_data(tx):
        print("Syncing nodes...")
        tx.run("MATCH (n) DETACH DELETE n")
        tx.run("UNWIND $data AS row CREATE (n:Program {id: row.id, name: row.name, year: row.year})", data=programs)
        tx.run("UNWIND $data AS row CREATE (n:Track {id: row.id, name: row.name})", data=tracks)
        tx.run("UNWIND $data AS row CREATE (n:Module {id: row.id, name: row.name, type_choose: row.type_choose})", data=modules)
        tx.run("""
            UNWIND $data AS row 
            CREATE (n:Discipline {id: row.id, name: row.name, semesters: row.semesters})
        """, data=disciplines)
        tx.run("UNWIND $data AS row CREATE (n:Student {id: row.id, full_name: row.full_name, curriculum_id: row.curriculum_id})", data=students)

        print("Syncing basic relationships...")
        tx.run("UNWIND $data AS row MATCH (p:Program {id: row.id_curricula}), (m:Module {id: row.id_module}) MERGE (p)-[:CONTAINS_MODULE]->(m)", data=sections)

        track_to_module = run_query("SELECT t.id as track_id, s.id_module FROM s335141.tracks t JOIN s335141.sections s ON t.id_section = s.id")
        tx.run("UNWIND $data AS row MATCH (t:Track {id: row.track_id}), (m:Module {id: row.id_module}) MERGE (t)-[:HAS_MODULE]->(m)", data=track_to_module)

        disc_to_mod = run_query("SELECT r.id_discipline, dim.id_module FROM s335141.rpd r JOIN s335141.disciplines_in_modules dim ON r.id_isu = dim.id_rpd")
        tx.run("UNWIND $data AS row MATCH (d:Discipline {id: row.id_discipline}), (m:Module {id: row.id_module}) MERGE (d)-[:PART_OF]->(m)", data=disc_to_mod)

        tx.run("MATCH (t:Track)-[:HAS_MODULE]->(m:Module)<-[:PART_OF]-(d:Discipline) MERGE (t)-[:INCLUDES]->(d)")

        print("Syncing prerequisites, progress and debts...")
        tx.run("UNWIND $data AS row MATCH (s:Student {id: row.id}), (p:Program {id: row.curriculum_id}) MERGE (s)-[:STUDIES_ON]->(p)", data=[s for s in students if s.get('curriculum_id')])
        tx.run("""
            UNWIND $data AS row 
            MATCH (d:Discipline {id: row.discipline_id}), (p:Discipline {id: row.prerequisite_id}) 
            MERGE (d)-[r:REQUIRES]->(p)
            SET r.source = row.source
        """, data=prereqs)
        tx.run("UNWIND $data AS row MATCH (s:Student {id: row.student_id}), (d:Discipline {id: row.discipline_id}) MERGE (s)-[:COMPLETED]->(d)", data=progress)
        tx.run("UNWIND $data AS row MATCH (s:Student {id: row.student_id}), (d:Discipline {id: row.discipline_id}) MERGE (s)-[:HAS_DEBT]->(d)", data=debts)

    with driver.session() as session:
        session.execute_write(sync_data)

    driver.close()
    print("Migration complete!")


if __name__ == "__main__":
    migrate()
