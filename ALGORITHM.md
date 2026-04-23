# Алгоритм автоматического построения графа пререквизитов

Данный документ описывает логику, по которой система автоматически устанавливает зависимости между учебными дисциплинами на основе структуры учебных планов в PostgreSQL.

## 1. Концепция
Логика базируется на предположении, что образовательная программа имеет строгую последовательность. Если блок дисциплин помечен как обязательный и стоит в учебном плане раньше другого блока, то все дисциплины из первого блока являются необходимыми входными требованиями (пререквизитами) для дисциплин второго блока.

## 2. Используемые данные (Schema: s335141)
Для работы алгоритма используются следующие таблицы:
*   **`sections`**: Хранит структуру учебного плана, привязку к модулям и позицию (`position`).
*   **`modules`**: Содержит тип выбора (`type_choose`). Нас интересуют модули с типом `'все'`.
*   **`disciplines_in_modules`** и **`rpd`**: Связывают модули с конкретными дисциплинами.
*   **`discipline_prerequisites`**: Таблица-результат, куда записываются связи.

## 3. Логическое правило
Для каждого учебного плана (`id_curricula`):
1.  Берется пара разделов `s1` и `s2`, принадлежащих этому плану.
2.  Проверяется условие: `s1.position < s2.position` (Раздел 1 идет раньше Раздела 2).
3.  Проверяется условие: `m1.type_choose = 'все'` (Модуль Раздела 1 является обязательным).
4.  Для каждой дисциплины `D1` из модуля `m1` и каждой дисциплины `D2` из модуля `m2` создается запись:
    *   `discipline_id` = `D2.id`
    *   `prerequisite_id` = `D1.id`

## 4. SQL Реализация
```sql
INSERT INTO s335141.discipline_prerequisites (discipline_id, prerequisite_id)
SELECT DISTINCT r2.id_discipline, r1.id_discipline
FROM s335141.sections s1
JOIN s335141.sections s2 ON s1.id_curricula = s2.id_curricula
JOIN s335141.modules m1 ON s1.id_module = m1.id_isu
JOIN s335141.disciplines_in_modules dim1 ON dim1.id_module = m1.id_isu
JOIN s335141.rpd r1 ON dim1.id_rpd = r1.id_isu
JOIN s335141.modules m2 ON s2.id_module = m2.id_isu
JOIN s335141.disciplines_in_modules dim2 ON dim2.id_module = m2.id_isu
JOIN s335141.rpd r2 ON dim2.id_rpd = r2.id_isu
WHERE s1.position < s2.position 
  AND m1.type_choose = 'все'
  AND r1.id_discipline IS NOT NULL 
  AND r2.id_discipline IS NOT NULL
  AND r1.id_discipline <> r2.id_discipline
ON CONFLICT DO NOTHING;
```

## 5. Применение в системе
После выполнения данного алгоритма в PostgreSQL необходимо запустить скрипт синхронизации `migrate.py`. Это перенесет созданные связи в Neo4j, где они будут использоваться API-сервером для фильтрации доступных студенту курсов.
