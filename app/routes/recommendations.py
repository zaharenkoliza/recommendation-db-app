from fastapi import APIRouter, Depends, HTTPException, status
from app.database import neo4j_db
from app.auth import require_student, require_admin, get_current_user

router = APIRouter(tags=["recommendations"])

@router.get("/recommend/{student_id}")
def recommend_courses(student_id: int, current_user: dict = Depends(get_current_user)):
    if current_user.get("student_id") != student_id and current_user.get("role") != "ADMIN":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot view recommendations for other students")
    """
    Интеллектуальный алгоритм подбора курсов:
    1. Находим дисциплины, входящие в трек студента (или доступные в программе).
    2. Исключаем уже пройденные.
    3. Проверяем, что все пререквизиты выполнены.
    """
    # 1. Сначала найдем треки студента (через связь STUDIES_ON или через группу)
    # Для упрощения допустим, что мы ищем по всем доступным дисциплинам, 
    # которые студент еще не прошел и может пройти.
    
    query = """
    MATCH (s:Student {id: $student_id})
    MATCH (d:Discipline)
    WHERE NOT (s)-[:COMPLETED]->(d)
    
    // Проверяем, является ли дисциплина долгом
    OPTIONAL MATCH (s)-[debt_rel:HAS_DEBT]->(d)
    WITH s, d, debt_rel IS NOT NULL as is_debt
    
    // Проверяем пререквизиты (только для новых курсов, долги можно пересдавать сразу)
    OPTIONAL MATCH (d)-[:REQUIRES]->(req:Discipline)
    WITH s, d, is_debt, collect(req) as all_reqs
    WHERE is_debt OR all(r IN all_reqs WHERE (s)-[:COMPLETED]->(r))
    
    RETURN d.name as name, 
           d.id as id, 
           is_debt,
           size(all_reqs) as prerequisite_count,
           [r IN all_reqs WHERE r IS NOT NULL | r.name] as prerequisite_names
    ORDER BY is_debt DESC, size(all_reqs) DESC
    LIMIT 10
    """
    
    results = neo4j_db.query(query, {"student_id": student_id})
    
    for r in results:
        if r.get("is_debt"):
            r["reason"] = "СРОЧНО: Академическая задолженность"
        else:
            req_names = r.get("prerequisite_names", [])
            if req_names and len(req_names) > 0:
                r["reason"] = f"Доступно на основе: {', '.join(req_names)}"
            else:
                r["reason"] = "Базовая дисциплина (нет пререквизитов)"
            
    return {
        "student_id": student_id,
        "recommended_disciplines": results
    }

@router.get("/track-disciplines/{track_name}")
def get_track_disciplines(track_name: str, current_user: dict = Depends(get_current_user)):
    query = """
    MATCH (t:Track)-[:INCLUDES]->(d:Discipline)
    WHERE t.name CONTAINS $track_name
    RETURN d.name as discipline_name, d.id as id
    """
    results = neo4j_db.query(query, {"track_name": track_name})
    return {"track": track_name, "disciplines": results}
