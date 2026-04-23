"""
Роуты управления учебными планами (Конструктор ОП).
Перенесено из PHP-бэкенда первого проекта.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from app.database import get_pg_conn
from app.auth import require_admin

router = APIRouter(tags=["admin"])


@router.get("/curricula")
def get_curricula(user: dict = Depends(require_admin)):
    """Список всех учебных планов."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT id_isu, name, year, degree, head
            FROM s335141.curricula
            ORDER BY year DESC, name
        """)
        return [
            {"id_isu": r[0], "name": r[1], "year": r[2], "degree": r[3], "head": r[4]}
            for r in cur.fetchall()
        ]
    finally:
        conn.close()


@router.get("/curricula/{id_isu}")
def get_curriculum(id_isu: int, user: dict = Depends(require_admin)):
    """Детали учебного плана: информация + полное дерево секций и дисциплин."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        # 1. Основная информация
        cur.execute("SELECT id_isu, name, year, degree, head FROM s335141.curricula WHERE id_isu = %s", (id_isu,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Учебный plan не найден")
        info = {"id_isu": row[0], "name": row[1], "year": row[2], "degree": row[3], "head": row[4]}

        # 2. Получаем все секции этого плана одним запросом
        cur.execute("""
            SELECT s.id, s.id_module, s.id_parent_section, s.position, 
                   m.name as module_name, m.type_choose, m.choose_count
            FROM s335141.sections s
            JOIN s335141.modules m ON s.id_module = m.id_isu
            WHERE s.id_curricula = %s
            ORDER BY s.id_parent_section NULLS FIRST, s.position
        """, (id_isu,))
        all_sections_rows = cur.fetchall()

        # 3. Получаем все дисциплины в модулях этого плана
        # Сначала найдем все ID модулей, которые есть в этом плане
        module_ids = list(set([r[1] for r in all_sections_rows]))
        disciplines_by_module = {}
        if module_ids:
            cur.execute("""
                SELECT dm.id_module, dm.id_rpd, r.name, dm.position
                FROM s335141.disciplines_in_modules dm
                JOIN s335141.rpd r ON dm.id_rpd = r.id_isu
                WHERE dm.id_module IN %s
                ORDER BY dm.position
            """, (tuple(module_ids),))
            for m_id, rpd_id, name, pos in cur.fetchall():
                if m_id not in disciplines_by_module:
                    disciplines_by_module[m_id] = []
                disciplines_by_module[m_id].append({"id": rpd_id, "name": name, "position": pos})

        # 4. Строим дерево (двухпроходный подход для надежности)
        sections_map = {}
        for r in all_sections_rows:
            s_id, m_id, parent_id, pos, m_name, t_choose, c_count = r
            sections_map[s_id] = {
                "id": s_id,
                "module_id": m_id,
                "module_name": m_name,
                "type_choose": t_choose,
                "choose_count": c_count,
                "position": pos,
                "parent_id": parent_id,
                "children": [],
                "disciplines": disciplines_by_module.get(m_id, [])
            }

        roots = []
        for s_id, section in sections_map.items():
            parent_id = section["parent_id"]
            if parent_id is None:
                roots.append(section)
            else:
                if parent_id in sections_map:
                    sections_map[parent_id]["children"].append(section)
                else:
                    # Если родитель не в этом плане (странно, но бывает), делаем корнем
                    roots.append(section)

        return {"info": info, "sections": roots}
    finally:
        conn.close()


@router.get("/disciplines")
def get_disciplines(user: dict = Depends(require_admin)):
    """Список всех дисциплин."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, name, comment FROM s335141.disciplines ORDER BY name")
        return [
            {"id": r[0], "name": r[1], "comment": r[2]}
            for r in cur.fetchall()
        ]
    finally:
        conn.close()


@router.get("/disciplines/{disc_id}")
def get_discipline(disc_id: int, user: dict = Depends(require_admin)):
    """Детали одной дисциплины."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id, name, comment FROM s335141.disciplines WHERE id = %s", (disc_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Дисциплина не найдена")
        return {"id": row[0], "name": row[1], "comment": row[2]}
    finally:
        conn.close()


@router.get("/tracks/{curriculum_id}")
def get_tracks(curriculum_id: int, user: dict = Depends(require_admin)):
    """Список треков учебного плана."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        # Curriculum info
        cur.execute("SELECT id_isu, name, year FROM s335141.curricula WHERE id_isu = %s", (curriculum_id,))
        row = cur.fetchone()
        info = {"id_isu": row[0], "name": row[1], "year": row[2]} if row else None

        cur.execute("""
            SELECT t.id, t.name, t.number, t.count_limit
            FROM s335141.tracks t
            JOIN s335141.sections s ON t.id_section = s.id
            WHERE s.id_curricula = %s
            ORDER BY t.number
        """, (curriculum_id,))
        tracks = [
            {"id": r[0], "name": r[1], "number": r[2], "count_limit": r[3]}
            for r in cur.fetchall()
        ]

        return {"info": info, "tracks": tracks}
    finally:
        conn.close()
