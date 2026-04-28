from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.database import get_pg_conn, neo4j_db
from app.routes import recommendations, auth, admin
from app.auth import get_current_user, require_admin
from fastapi import Depends, HTTPException, status

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
def get_students(current_user: dict = Depends(require_admin)):
    pg_conn = get_pg_conn()
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT s.id, s.name, s.group_id, t.name as track_name, ss.status_name
        FROM s335141.students s
        LEFT JOIN s335141.tracks t ON s.track_id = t.id
        LEFT JOIN s335141.student_status ss ON s.status_id = ss.id
        ORDER BY s.name LIMIT 100
    """)
    students = [
        {"id": row[0], "name": row[1], "group_id": row[2], "track": row[3], "status": row[4]} 
        for row in cur.fetchall()
    ]
    pg_conn.close()
    return students

@app.get("/students/{student_id}")
def get_student_details(student_id: int, current_user: dict = Depends(get_current_user)):
    if current_user.get("student_id") != student_id and current_user.get("role") != "ADMIN":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot view details for other students")
    pg_conn = get_pg_conn()
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT s.id, s.name, s.group_id, t.name, ss.status_name, c.name, c.year
        FROM s335141.students s
        LEFT JOIN s335141.tracks t ON s.track_id = t.id
        LEFT JOIN s335141.student_status ss ON s.status_id = ss.id
        LEFT JOIN s335141.curricula c ON s.curriculum_id = c.id_isu
        WHERE s.id = %s
    """, (student_id,))
    student = cur.fetchone()
    pg_conn.close()
    
    if not student:
        return {"error": "Student not found"}
    
    # Calculate course based on curriculum year (assuming current year is 2026)
    current_year = 2026
    curriculum_year = student[6]
    course = (current_year - curriculum_year + 1) if curriculum_year else 3 # Default to 3 for showcase if not set
    
    return {
        "id": student[0], 
        "name": student[1], 
        "group_id": student[2], 
        "track": student[3] or "Общий трек",
        "status": student[4] or "Активен",
        "curriculum": student[5] or "Прикладная информатика",
        "course": course
    }

@app.get("/student/curriculum")
def get_my_curriculum(current_user: dict = Depends(get_current_user)):
    student_id = current_user.get("student_id")
    if not student_id:
        raise HTTPException(status_code=400, detail="Only students have a curriculum")
    
    pg_conn = get_pg_conn()
    cur = pg_conn.cursor()
    try:
        # 1. Find curriculum ID directly from student record
        cur.execute("""
            SELECT curriculum_id 
            FROM s335141.students 
            WHERE id = %s
        """, (student_id,))
        row = cur.fetchone()
        if not row:
            # Fallback if track is not linked to a section yet
            # For the showcase, we'll try to find any curriculum if the student has no track link
            # But in a real system, we'd raise 404
            cur.execute("SELECT id_isu FROM s335141.curricula LIMIT 1")
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Curriculum not found for this student")
        
        curriculum_id = row[0]
        
        # 2. Reuse the logic from admin.get_curriculum (but we'll implement it here or import it)
        # To avoid circular imports, I'll implement a simplified version or the same logic
        from app.routes.admin import get_curriculum
        # Note: we need to bypass the require_admin dependency or call the logic directly
        # Since get_curriculum is a function, we can just call it and pass a mock user
        return get_curriculum(curriculum_id, user={"role": "ADMIN"}) # Internal call
    finally:
        pg_conn.close()

@app.get("/students/{student_id}/progress")
def get_student_progress(student_id: int, current_user: dict = Depends(get_current_user)):
    if current_user.get("student_id") != student_id and current_user.get("role") != "ADMIN":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot view progress for other students")
    pg_conn = get_pg_conn()
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT sp.id, d.name, sp.grade, sp.status, sp.attempt_number, sp.updated_at
        FROM s335141.student_performance sp
        JOIN s335141.disciplines d ON sp.discipline_id = d.id
        WHERE sp.student_id = %s
        ORDER BY sp.status DESC, sp.updated_at DESC
    """, (student_id,))
    rows = cur.fetchall()
    pg_conn.close()

    passed = []
    failed = []
    enrolled = []
    for row in rows:
        entry = {
            "id": row[0],
            "discipline_name": row[1],
            "grade": row[2],
            "status": row[3],
            "attempt_number": row[4],
            "updated_at": str(row[5]) if row[5] else None
        }
        if row[3] == "Passed":
            passed.append(entry)
        elif row[3] == "Failed":
            failed.append(entry)
        else:
            enrolled.append(entry)

    return {
        "student_id": student_id,
        "summary": {
            "total": len(rows),
            "passed": len(passed),
            "failed": len(failed),
            "enrolled": len(enrolled)
        },
        "passed": passed,
        "failed": failed,
        "enrolled": enrolled
    }

app.include_router(auth.router, prefix="/auth")
app.include_router(recommendations.router, prefix="/api")
app.include_router(admin.router, prefix="/admin")
