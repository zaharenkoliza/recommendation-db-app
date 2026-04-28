"""
Роуты управления учебными планами (Конструктор ОП).
Перенесено из PHP-бэкенда первого проекта.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Optional
from app.database import get_pg_conn
from app.auth import require_admin, get_current_user

router = APIRouter(tags=["admin"])


# ── Pydantic-модели ──────────────────────────────
class CurriculumCreate(BaseModel):
    id_isu: int
    name: str
    year: int
    degree: str = "bachelor"
    head: Optional[str] = None

class CurriculumUpdate(BaseModel):
    name: Optional[str] = None
    year: Optional[int] = None
    degree: Optional[str] = None
    head: Optional[str] = None

class TrackCreate(BaseModel):
    name: str
    number: int
    id_section: int
    count_limit: Optional[int] = None

class TrackUpdate(BaseModel):
    name: Optional[str] = None
    number: Optional[int] = None
    count_limit: Optional[int] = None

class DisciplineUpdate(BaseModel):
    name: Optional[str] = None
    comment: Optional[str] = None

class PrerequisiteRequest(BaseModel):
    discipline_id: int
    prerequisite_id: int

class ModuleImport(BaseModel):
    id_isu: int
    name: str
    type_choose: str = "все"
    choose_count: int = 1
    disciplines: list[dict] # {id_rpd, name, position, semester}

class SectionImport(BaseModel):
    id_module: int
    module_name: str
    position: int
    type_choose: str = "все"
    children: list['SectionImport'] = []
    disciplines: list[dict] = [] # Optional direct disciplines

class CurriculumImport(BaseModel):
    id_isu: int
    name: str
    year: int
    degree: str = "bachelor"
    head: Optional[str] = None
    sections: list[SectionImport]


@router.get("/curricula")
def get_curricula(user: dict = Depends(get_current_user)):
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
def get_curriculum(id_isu: int, user: dict = Depends(get_current_user)):
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

        disciplines_flat = []
        seen = set()
        for mod_discs in disciplines_by_module.values():
            for d in mod_discs:
                if d["id"] not in seen:
                    seen.add(d["id"])
                    disciplines_flat.append(d)

        return {"info": info, "sections": roots, "disciplines_flat": disciplines_flat}
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


@router.get("/disciplines/{disc_id}/graph")
def get_discipline_graph(disc_id: int, user: dict = Depends(get_current_user)):
    """Получение графа зависимостей для конкретной дисциплины."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        # 1. Получаем основную инфо о целевой дисциплине
        cur.execute("SELECT id, name FROM s335141.disciplines WHERE id = %s", (disc_id,))
        target = cur.fetchone()
        if not target:
            raise HTTPException(status_code=404, detail="Дисциплина не найдена")

        nodes = [{"id": str(target[0]), "label": target[1], "type": "target"}]
        edges = []
        visited_nodes = {target[0]}

        # 2. Получаем пререквизиты (что ДО)
        cur.execute("""
            SELECT p.id, p.name, dp.source
            FROM s335141.discipline_prerequisites dp
            JOIN s335141.disciplines p ON dp.prerequisite_id = p.id
            WHERE dp.discipline_id = %s
        """, (disc_id,))
        for p_id, p_name, source in cur.fetchall():
            if p_id not in visited_nodes:
                nodes.append({"id": str(p_id), "label": p_name, "type": "pre"})
                visited_nodes.add(p_id)
            edges.append({
                "id": f"e{p_id}-{disc_id}", 
                "source": str(p_id), 
                "target": str(disc_id),
                "label": "Вручную" if source == "manual" else "Авто"
            })

        # 3. Получаем последующие (что ПОСЛЕ)
        cur.execute("""
            SELECT d.id, d.name, dp.source
            FROM s335141.discipline_prerequisites dp
            JOIN s335141.disciplines d ON dp.discipline_id = d.id
            WHERE dp.prerequisite_id = %s
        """, (disc_id,))
        for f_id, f_name, source in cur.fetchall():
            if f_id not in visited_nodes:
                nodes.append({"id": str(f_id), "label": f_name, "type": "post"})
                visited_nodes.add(f_id)
            edges.append({
                "id": f"e{disc_id}-{f_id}", 
                "source": str(disc_id), 
                "target": str(f_id),
                "label": "Вручную" if source == "manual" else "Авто"
            })

        return {"nodes": nodes, "edges": edges}
    finally:
        conn.close()




# ══════════════════════════════════════════════════════════
# CRUD: Учебные планы
# ══════════════════════════════════════════════════════════

@router.post("/curricula", status_code=201)
def create_curriculum(body: CurriculumCreate, user: dict = Depends(require_admin)):
    """Создание нового учебного плана."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO s335141.curricula (id_isu, name, year, degree, head) VALUES (%s, %s, %s, %s, %s) RETURNING id_isu",
            (body.id_isu, body.name, body.year, body.degree, body.head)
        )
        conn.commit()
        return {"id_isu": body.id_isu, "name": body.name, "year": body.year, "degree": body.degree, "head": body.head}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Ошибка при создании плана: {str(e)}")
    finally:
        conn.close()


@router.put("/curricula/{id_isu}")
def update_curriculum(id_isu: int, body: CurriculumUpdate, user: dict = Depends(require_admin)):
    """Обновление учебного плана."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        # Собираем только заполненные поля
        updates = []
        values = []
        for field, value in body.dict(exclude_none=True).items():
            updates.append(f"{field} = %s")
            values.append(value)

        if not updates:
            raise HTTPException(status_code=400, detail="Нет данных для обновления")

        values.append(id_isu)
        cur.execute(
            f"UPDATE s335141.curricula SET {', '.join(updates)} WHERE id_isu = %s RETURNING id_isu, name, year, degree, head",
            tuple(values)
        )
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Учебный план не найден")
        conn.commit()
        return {"id_isu": row[0], "name": row[1], "year": row[2], "degree": row[3], "head": row[4]}
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Ошибка обновления: {str(e)}")
    finally:
        conn.close()


@router.delete("/curricula/{id_isu}")
def delete_curriculum(id_isu: int, user: dict = Depends(require_admin)):
    """Удаление учебного плана."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        # Удаляем связанные секции и дочерние данные
        cur.execute("DELETE FROM s335141.sections WHERE id_curricula = %s", (id_isu,))
        cur.execute("DELETE FROM s335141.curricula WHERE id_isu = %s RETURNING id_isu", (id_isu,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Учебный план не найден")
        conn.commit()
        return {"deleted": True, "id_isu": id_isu}
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Ошибка удаления: {str(e)}")
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════
# CRUD: Треки
# ══════════════════════════════════════════════════════════

@router.post("/tracks", status_code=201)
def create_track(body: TrackCreate, user: dict = Depends(require_admin)):
    """Создание нового трека."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO s335141.tracks (name, number, id_section, count_limit) VALUES (%s, %s, %s, %s) RETURNING id",
            (body.name, body.number, body.id_section, body.count_limit)
        )
        new_id = cur.fetchone()[0]
        conn.commit()
        return {"id": new_id, "name": body.name, "number": body.number, "id_section": body.id_section, "count_limit": body.count_limit}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Ошибка создания трека: {str(e)}")
    finally:
        conn.close()


@router.put("/tracks/{track_id}/edit")
def update_track(track_id: int, body: TrackUpdate, user: dict = Depends(require_admin)):
    """Обновление трека."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        updates = []
        values = []
        for field, value in body.dict(exclude_none=True).items():
            updates.append(f"{field} = %s")
            values.append(value)

        if not updates:
            raise HTTPException(status_code=400, detail="Нет данных для обновления")

        values.append(track_id)
        cur.execute(
            f"UPDATE s335141.tracks SET {', '.join(updates)} WHERE id = %s RETURNING id, name, number, count_limit",
            tuple(values)
        )
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Трек не найден")
        conn.commit()
        return {"id": row[0], "name": row[1], "number": row[2], "count_limit": row[3]}
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Ошибка обновления: {str(e)}")
    finally:
        conn.close()


@router.delete("/tracks/{track_id}")
def delete_track(track_id: int, user: dict = Depends(require_admin)):
    """Удаление трека."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        cur.execute("DELETE FROM s335141.tracks WHERE id = %s RETURNING id", (track_id,))
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Трек не найден")
        conn.commit()
        return {"deleted": True, "id": track_id}
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Ошибка удаления: {str(e)}")
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════
# CRUD: Дисциплины
# ══════════════════════════════════════════════════════════

@router.put("/disciplines/{disc_id}")
def update_discipline(disc_id: int, body: DisciplineUpdate, user: dict = Depends(require_admin)):
    """Обновление дисциплины."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        updates = []
        values = []
        for field, value in body.dict(exclude_none=True).items():
            updates.append(f"{field} = %s")
            values.append(value)

        if not updates:
            raise HTTPException(status_code=400, detail="Нет данных для обновления")

        values.append(disc_id)
        cur.execute(
            f"UPDATE s335141.disciplines SET {', '.join(updates)} WHERE id = %s RETURNING id, name, comment",
            tuple(values)
        )
        row = cur.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Дисциплина не найдена")
        conn.commit()
        return {"id": row[0], "name": row[1], "comment": row[2]}
    except HTTPException:
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Ошибка обновления: {str(e)}")
    finally:
        conn.close()

# ══════════════════════════════════════════════════════════
# ПРЕ-РЕКВИЗИТЫ: Ручное управление
# ══════════════════════════════════════════════════════════

@router.post("/prerequisites", status_code=201)
def add_prerequisite(body: PrerequisiteRequest, user: dict = Depends(require_admin)):
    """Добавление ручного пререквизита."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO s335141.discipline_prerequisites (discipline_id, prerequisite_id, source) VALUES (%s, %s, 'manual') ON CONFLICT DO NOTHING",
            (body.discipline_id, body.prerequisite_id)
        )
        conn.commit()
        return {"status": "ok"}
    finally:
        conn.close()

@router.delete("/prerequisites")
def delete_prerequisite(discipline_id: int, prerequisite_id: int, user: dict = Depends(require_admin)):
    """Удаление пререквизита."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        cur.execute(
            "DELETE FROM s335141.discipline_prerequisites WHERE discipline_id = %s AND prerequisite_id = %s",
            (discipline_id, prerequisite_id)
        )
        conn.commit()
        return {"status": "ok"}
    finally:
        conn.close()


# ══════════════════════════════════════════════════════════
# ИМПОРТ: Учебные планы из JSON
# ══════════════════════════════════════════════════════════

@router.post("/import-curriculum", status_code=201)
def import_curriculum(body: CurriculumImport, user: dict = Depends(require_admin)):
    """Комплексный импорт учебного плана со всей структурой."""
    conn = get_pg_conn()
    cur = conn.cursor()
    try:
        # 1. Создаем/обновляем учебный план
        cur.execute("""
            INSERT INTO s335141.curricula (id_isu, name, year, degree, head)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (id_isu) DO UPDATE SET name = EXCLUDED.name, year = EXCLUDED.year
        """, (body.id_isu, body.name, body.year, body.degree, body.head))

        # 2. Рекурсивная функция для импорта секций
        def process_section(section: SectionImport, parent_id: Optional[int] = None):
            # 2.1 Создаем модуль
            cur.execute("""
                INSERT INTO s335141.modules (id_isu, name, type_choose)
                VALUES (%s, %s, %s)
                ON CONFLICT (id_isu) DO UPDATE SET name = EXCLUDED.name, type_choose = EXCLUDED.type_choose
                RETURNING id_isu
            """, (section.id_module, section.module_name, section.type_choose))
            
            # 2.2 Создаем секцию
            cur.execute("""
                INSERT INTO s335141.sections (id_curricula, id_module, id_parent_section, position)
                VALUES (%s, %s, %s, %s)
                RETURNING id
            """, (body.id_isu, section.id_module, parent_id, section.position))
            section_id = cur.fetchone()[0]

            # 2.3 Обрабатываем дисциплины
            for disc in section.disciplines:
                # Гарантируем наличие дисциплины
                cur.execute("INSERT INTO s335141.disciplines (id, name) VALUES (%s, %s) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name", (disc['id_discipline'], disc['name']))
                
                # Создаем RPD
                cur.execute("""
                    INSERT INTO s335141.rpd (id_isu, id_discipline, name)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (id_isu) DO UPDATE SET name = EXCLUDED.name
                """, (disc['id_rpd'], disc['id_discipline'], disc['name']))

                # Привязываем к модулю
                cur.execute("""
                    INSERT INTO s335141.disciplines_in_modules (id_module, id_rpd, position)
                    VALUES (%s, %s, %s)
                    ON CONFLICT ON CONSTRAINT uk_rpd_module DO UPDATE SET position = EXCLUDED.position
                    RETURNING id
                """, (section.id_module, disc['id_rpd'], disc['position']))
                dim_id = cur.fetchone()[0]

                # Записываем семестр
                if 'semester' in disc:
                    cur.execute("""
                        INSERT INTO s335141.discp_starts (id_discp_module, sem)
                        VALUES (%s, %s)
                        ON CONFLICT ON CONSTRAINT uk_discp_start DO UPDATE SET sem = EXCLUDED.sem
                    """, (dim_id, disc['semester']))

            # 2.4 Обрабатываем вложенные секции
            for child in section.children:
                process_section(child, section_id)

        # Запуск импорта
        for section in body.sections:
            process_section(section)

        conn.commit()
        return {"status": "Curriculum imported successfully", "id_isu": body.id_isu}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=f"Import failed: {str(e)}")
    finally:
        conn.close()
