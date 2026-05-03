"""
Построение «умных» пререквизитов на основе Jaccard similarity и Transitive Reduction.

Алгоритм:
1. Получить структурных кандидатов из БД (дисциплины в одном модуле)
2. Отфильтровать по семантической схожести названий (Jaccard > 0.25)
3. Применить Transitive Reduction для удаления избыточных связей
4. Записать результат в PostgreSQL
5. Синхронизировать в Neo4j

Запуск внутри контейнера:
    python -m app.management.build_prerequisites
"""

import re
from collections import defaultdict
from app.database import get_pg_conn
from app.management.migrate import migrate


def get_disciplines():
    """Получить словарь {id: name} всех дисциплин."""
    conn = get_pg_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id, name FROM s335141.disciplines")
            return {row[0]: row[1] for row in cur.fetchall()}
    finally:
        conn.close()


def get_word_set(text):
    """Получить множество значимых слов из текста."""
    text = text.lower()
    text = re.sub(r'[^\w\s]', ' ', text)
    stop_words = {'как', 'для', 'это', 'был', 'была', 'оно', 'они', 'и', 'в', 'на', 'с', 'по', 'об', 'от'}
    return set(w for w in text.split() if len(w) > 2 and w not in stop_words)


def jaccard_similarity(s1, s2):
    if not s1 or not s2:
        return 0
    return len(s1 & s2) / len(s1 | s2)


def get_structural_candidates():
    """Получить пары дисциплин-кандидатов на основе структуры учебного плана."""
    conn = get_pg_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT DISTINCT r1.id_discipline, r2.id_discipline
                FROM s335141.sections s1
                JOIN s335141.sections s2 ON s1.id_curricula = s2.id_curricula 
                  AND s1.id_parent_section IS NOT DISTINCT FROM s2.id_parent_section
                  AND s2.position > s1.position
                JOIN s335141.modules m1 ON s1.id_module = m1.id_isu
                JOIN s335141.modules m2 ON s2.id_module = m2.id_isu
                JOIN s335141.disciplines_in_modules dim1 ON dim1.id_module = m1.id_isu
                JOIN s335141.rpd r1 ON dim1.id_rpd = r1.id_isu
                JOIN s335141.disciplines_in_modules dim2 ON dim2.id_module = m2.id_isu
                JOIN s335141.rpd r2 ON dim2.id_rpd = r2.id_isu
                WHERE m1.type_choose = 'все'
                  AND r1.id_discipline IS NOT NULL AND r2.id_discipline IS NOT NULL
                  AND r1.id_discipline <> r2.id_discipline
            """)
            return [(row[0], row[1]) for row in cur.fetchall()]
    finally:
        conn.close()


def execute_sql(query):
    """Выполнить SQL-команду (INSERT/UPDATE/DELETE)."""
    conn = get_pg_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(query)
        conn.commit()
    finally:
        conn.close()


def main():
    print("Starting Smart Prerequisite Analysis...")

    disciplines = get_disciplines()
    if not disciplines:
        print("No disciplines found. Check DB connection.")
        return

    fingerprints = {id_: get_word_set(name) for id_, name in disciplines.items()}

    print("Step 1: Fetching structural candidates from DB...")
    candidates = get_structural_candidates()
    print(f"Found {len(candidates)} structural candidates.")

    print("Step 2: Filtering by semantic similarity and subject matching...")
    final_links = []

    for d1, d2 in candidates:
        if d1 not in fingerprints or d2 not in fingerprints:
            continue

        sim = jaccard_similarity(fingerprints[d1], fingerprints[d2])
        name1, name2 = disciplines[d1], disciplines[d2]

        is_sequence = False
        if name1[:8].lower() == name2[:8].lower():
            is_sequence = True
        elif any(token in name2.lower() for token in ["часть 2", "часть 3", "продвинутый", "углубленный"]):
            if name1[:6].lower() == name2[:6].lower():
                is_sequence = True

        if sim > 0.25 or is_sequence:
            final_links.append((d2, d1))

    print(f"Filtered down to {len(final_links)} semantic links.")

    print("Step 3: Applying Transitive Reduction...")
    adj = defaultdict(set)
    for d, p in final_links:
        adj[d].add(p)

    def has_path(start, end, target_to_skip, visited, d_global):
        if start == end:
            return True
        visited.add(start)
        for neighbor in adj[start]:
            if neighbor == target_to_skip and start == d_global:
                continue
            if neighbor not in visited:
                if has_path(neighbor, end, target_to_skip, visited, d_global):
                    return True
        return False

    reduced_links = []
    for d, p in final_links:
        if not has_path(d, p, p, set(), d):
            reduced_links.append((d, p))

    print(f"Final reduced links: {len(reduced_links)}")

    print("Step 4: Updating Database...")
    execute_sql("DELETE FROM s335141.discipline_prerequisites WHERE source = 'auto'")

    if reduced_links:
        values = [f"({d}, {p}, 'auto')" for d, p in reduced_links]
        for i in range(0, len(values), 500):
            chunk = values[i:i + 500]
            execute_sql(
                f"INSERT INTO s335141.discipline_prerequisites (discipline_id, prerequisite_id, source) "
                f"VALUES {', '.join(chunk)} ON CONFLICT DO NOTHING"
            )

    print("Step 5: Syncing to Neo4j...")
    migrate()

    print("\nSmart Analysis Complete!")


if __name__ == "__main__":
    main()
