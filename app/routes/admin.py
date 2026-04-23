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


@router.get("/tracks/{id}/details")
def get_track_details(id: int, user: dict = Depends(require_admin)):
    """Получение детальной структуры учебного плана для конкретного трека."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        # 1. Получаем инфо о треке и его родителе (плане)
        cur.execute("""
            SELECT t.id_section, s.id_curricula, t.name, t.number, c.name as cur_name, c.year
            FROM s335141.tracks t
            JOIN s335141.sections s ON t.id_section = s.id
            JOIN s335141.curricula c ON s.id_curricula = c.id_isu
            WHERE t.id = %s
        """, (id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Трек не найден")
        
        target_section_id, cur_id, track_name, track_num, cur_name, cur_year = row

        # 2. Получаем все секции этого плана
        cur.execute("""
            SELECT s.id, s.id_module, s.id_parent_section, s.position, 
                   m.name as module_name, m.type_choose, m.choose_count
            FROM s335141.sections s
            JOIN s335141.modules m ON s.id_module = m.id_isu
            WHERE s.id_curricula = %s
            ORDER BY s.id_parent_section NULLS FIRST, s.position
        """, (cur_id,))
        all_sections_rows = cur.fetchall()

        # 3. Получаем дисциплины с информацией о семестрах
        module_ids = list(set([r[1] for r in all_sections_rows]))
        disciplines_by_module = {}
        all_disciplines_flat = []

        if module_ids:
            # Получаем базовую инфо о дисциплинах
            cur.execute("""
                SELECT dm.id_module, dm.id_rpd, r.name, dm.position, r.study_format, dm.implementer
                FROM s335141.disciplines_in_modules dm
                JOIN s335141.rpd r ON dm.id_rpd = r.id_isu
                WHERE dm.id_module IN %s
                ORDER BY dm.position
            """, (tuple(module_ids),))
            base_discs = cur.fetchall()

            # Получаем семестры для этих дисциплин
            # В этой базе семестр определяется через s335141.discp_starts (стартовый семестр)
            # и s335141.semester_rpd (длительность/смещение)
            cur.execute("""
                SELECT ds.id_discp_module, ds.sem as start_sem, sr.number_from_start
                FROM s335141.discp_starts ds
                JOIN s335141.disciplines_in_modules dim ON ds.id_discp_module = dim.id
                JOIN s335141.semester_rpd sr ON dim.id_rpd = sr.id_rpd
                WHERE dim.id_module IN %s
            """, (tuple(module_ids),))
            semesters_info = {}
            for dm_id, start_sem, offset in cur.fetchall():
                if dm_id not in semesters_info:
                    semesters_info[dm_id] = []
                semesters_info[dm_id].append(start_sem + offset - 1)

            for m_id, rpd_id, name, pos, format, impl in base_discs:
                # Находим ID в disciplines_in_modules (нужно для семестров)
                # Для простоты возьмем первый попавшийся ID (в реальности нужно точное совпадение)
                cur.execute("SELECT id FROM s335141.disciplines_in_modules WHERE id_module=%s AND id_rpd=%s", (m_id, rpd_id))
                dm_row = cur.fetchone()
                dm_id = dm_row[0] if dm_row else None
                
                sems = semesters_info.get(dm_id, [1]) # По умолчанию 1 семестр
                
                disc_item = {
                    "id": rpd_id, 
                    "name": name, 
                    "position": pos, 
                    "format": format, 
                    "implementer": impl,
                    "semesters": sems
                }
                
                if m_id not in disciplines_by_module:
                    disciplines_by_module[m_id] = []
                disciplines_by_module[m_id].append(disc_item)
                all_disciplines_flat.append(disc_item)

        # 4. Строим дерево
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
                    roots.append(section)

        return {
            "track": {"id": id, "name": track_name, "number": track_num},
            "curriculum": {"id": cur_id, "name": cur_name, "year": cur_year},
            "sections": roots,
            "disciplines_flat": all_disciplines_flat
        }
    finally:
        conn.close()


