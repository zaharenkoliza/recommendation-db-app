from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import get_pg_conn, neo4j_db
from app.routes import recommendations

app = FastAPI(title="ITMO Educational Program Management System")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For development, allow all
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def read_root():
    return {"status": "online", "message": "Welcome to ITMO EP Management System"}

@app.get("/stats")
def get_stats():
    # Example SQL query
    pg_conn = get_pg_conn()
    cur = pg_conn.cursor()
    cur.execute("SELECT count(*) FROM s335141.disciplines")
    disc_count = cur.fetchone()[0]
    pg_conn.close()

    # Example Neo4j query
    neo_count = neo4j_db.query("MATCH (n) RETURN count(n) as count")[0]['count']

    return {
        "postgres_disciplines": disc_count,
        "neo4j_nodes": neo_count
    }

@app.get("/students")
def get_students():
    pg_conn = get_pg_conn()
    cur = pg_conn.cursor()
    cur.execute("SELECT id, name FROM s335141.students ORDER BY name LIMIT 100")
    students = [{"id": row[0], "name": row[1]} for row in cur.fetchall()]
    pg_conn.close()
    return students

@app.get("/students/{student_id}")
def get_student_details(student_id: int):
    pg_conn = get_pg_conn()
    cur = pg_conn.cursor()
    cur.execute("SELECT id, name, group_id FROM s335141.students WHERE id = %s", (student_id,))
    student = cur.fetchone()
    pg_conn.close()
    if not student:
        return {"error": "Student not found"}
    return {"id": student[0], "name": student[1], "group_id": student[2]}

app.include_router(recommendations.router, prefix="/api")
