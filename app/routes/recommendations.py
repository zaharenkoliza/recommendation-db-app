from fastapi import APIRouter
from app.database import neo4j_db

router = APIRouter(tags=["recommendations"])

@router.get("/recommend/{student_id}")
def recommend_courses(student_id: int):
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
    // Находим все дисциплины, которые потенциально доступны
    MATCH (d:Discipline)
    WHERE NOT (s)-[:COMPLETED]->(d)
    
    // Проверяем пререквизиты: 
    // Либо их нет, либо все они в статусе COMPLETED у этого студента
    OPTIONAL MATCH (d)-[:REQUIRES]->(req:Discipline)
    WITH s, d, collect(req) as all_reqs
    WHERE all(r IN all_reqs WHERE (s)-[:COMPLETED]->(r))
    
    RETURN d.name as name, d.id as id, size(all_reqs) as prerequisite_count
    ORDER BY prerequisite_count DESC
    LIMIT 10
    """
    
    results = neo4j_db.query(query, {"student_id": student_id})
    return {
        "student_id": student_id,
        "recommended_disciplines": results
    }

@router.get("/track-disciplines/{track_name}")
def get_track_disciplines(track_name: str):
    query = """
    MATCH (t:Track)-[:INCLUDES]->(d:Discipline)
    WHERE t.name CONTAINS $track_name
    RETURN d.name as discipline_name, d.id as id
    """
    results = neo4j_db.query(query, {"track_name": track_name})
    return {"track": track_name, "disciplines": results}
