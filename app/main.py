from fastapi import FastAPI
from app.database import get_pg_conn, neo4j_db
from app.routes import recommendations

app = FastAPI(title="ITMO Educational Program Management System")

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

app.include_router(recommendations.router, prefix="/api")
