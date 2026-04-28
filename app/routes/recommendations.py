from fastapi import APIRouter, Depends, HTTPException, status
from app.database import neo4j_db
from app.auth import require_student, require_admin, get_current_user

router = APIRouter(tags=["recommendations"])

@router.get("/recommend/{student_id}")
def recommend_courses(student_id: int, current_user: dict = Depends(get_current_user)):
    if current_user.get("student_id") != student_id and current_user.get("role") != "ADMIN":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot view recommendations for other students")

    # 1. Calculate current semester based on enrollment year
    # We fetch it from Program node linked to Student
    prog_query = "MATCH (s:Student {id: $student_id})-[:STUDIES_ON]->(p:Program) RETURN p.year as year"
    prog_res = neo4j_db.query(prog_query, {"student_id": student_id})
    
    if not prog_res:
        next_semester = 1
    else:
        import datetime
        now = datetime.datetime.now()
        enrollment_year = prog_res[0]["year"]
        
        # Correct Academic Semester Calculation
        if now.month < 9:
            academic_year_index = now.year - enrollment_year - 1
        else:
            academic_year_index = now.year - enrollment_year
            
        is_spring = 2 <= now.month <= 8
        current_semester = academic_year_index * 2 + (2 if is_spring else 1)
        next_semester = current_semester + 1

    query = """
    MATCH (s:Student {id: $student_id})-[:STUDIES_ON]->(p:Program)
    MATCH (p)-[:CONTAINS_MODULE]->(m:Module)<-[:PART_OF]-(d:Discipline)
    WITH DISTINCT d, s, m
    WHERE NOT (s)-[:COMPLETED]->(d)
    
    // Filter by next semester
    AND ($next_semester IN d.semesters OR $next_semester = 1)

    // Проверяем, является ли дисциплина долгом
    OPTIONAL MATCH (s)-[debt_rel:HAS_DEBT]->(d)
    WITH s, d, m, debt_rel IS NOT NULL as is_debt
    
    // Получаем пререквизиты и проверяем их выполнение
    OPTIONAL MATCH (d)-[r:REQUIRES]->(req:Discipline)
    WITH s, d, m, is_debt, req, r
    OPTIONAL MATCH (s)-[c:COMPLETED]->(req)
    
    WITH s, d, m, is_debt, 
         collect({name: req.name, source: r.source, completed: c IS NOT NULL}) as all_reqs
    
    // Оставляем только если это долг ИЛИ все пререквизиты выполнены
    WHERE is_debt OR all(x IN all_reqs WHERE x.name IS NULL OR x.completed = true)
    
    RETURN d.name as name, 
           d.id as id, 
           is_debt,
           m.type_choose as type_choose,
           m.name as module_name,
           size([x IN all_reqs WHERE x.name IS NOT NULL]) as prerequisite_count,
           [x IN all_reqs WHERE x.name IS NOT NULL] as prerequisites
    ORDER BY is_debt DESC, prerequisite_count DESC
    LIMIT 20
    """
    
    results = neo4j_db.query(query, {"student_id": student_id, "next_semester": next_semester})
    
    mandatory = []
    elective_map = {} # module_name -> list of disciplines
    
    for r in results:
        type_choose = r.get("type_choose")
        is_debt = r.get("is_debt")
        
        # Determine labels and reasons
        type_label = "Обязательная" if type_choose == "все" else "По выбору"
        
        if is_debt:
            r["reason"] = "СРОЧНО: Академическая задолженность"
            mandatory.append(r)
        elif type_choose == "все":
            prereqs = [p for p in r.get("prerequisites", []) if p.get('name')]
            if prereqs:
                auto = [p['name'] for p in prereqs if p['source'] == 'auto']
                manual = [p['name'] for p in prereqs if p['source'] == 'manual']
                parts = []
                if manual: parts.append(f"Требуется (вручную): {', '.join(manual)}")
                if auto: parts.append(f"Основано на программе: {', '.join(auto)}")
                r["reason"] = f"{type_label} | " + " | ".join(parts)
            else:
                r["reason"] = f"{type_label} | Рекомендуется по плану"
            mandatory.append(r)
        else:
            # Elective grouping
            module_name = r.get("module_name") or "Блок по выбору"
            
            if module_name not in elective_map:
                elective_map[module_name] = []
            
            r["reason"] = "Выберите эту или другую дисциплину из блока"
            elective_map[module_name].append(r)

    # Convert elective_map to list of groups
    elective_groups = []
    for name, discs in elective_map.items():
        elective_groups.append({
            "module_name": name,
            "disciplines": discs
        })
            
    return {
        "student_id": student_id,
        "next_semester": next_semester,
        "mandatory": mandatory,
        "elective_groups": elective_groups
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
