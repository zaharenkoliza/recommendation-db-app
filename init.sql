CREATE USER s335141 WITH PASSWORD 'password'; ALTER USER s335141 WITH SUPERUSER;
--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4
-- Dumped by pg_dump version 16.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: s335141; Type: SCHEMA; Schema: -; Owner: s335141
--

CREATE SCHEMA s335141;


ALTER SCHEMA s335141 OWNER TO s335141;

--
-- Name: assessment_type; Type: TYPE; Schema: s335141; Owner: s335141
--

CREATE TYPE s335141.assessment_type AS ENUM (
    'Экзамен',
    'Зачет',
    'Дифф. зачет',
    'Курсовая работа',
    'Курсовой проект'
);


ALTER TYPE s335141.assessment_type OWNER TO s335141;

--
-- Name: change_type; Type: TYPE; Schema: s335141; Owner: s335141
--

CREATE TYPE s335141.change_type AS ENUM (
    'delete',
    'add'
);


ALTER TYPE s335141.change_type OWNER TO s335141;

--
-- Name: degree_type; Type: TYPE; Schema: s335141; Owner: s335141
--

CREATE TYPE s335141.degree_type AS ENUM (
    'bachelor',
    'master'
);


ALTER TYPE s335141.degree_type OWNER TO s335141;

--
-- Name: module_choose_type; Type: TYPE; Schema: s335141; Owner: s335141
--

CREATE TYPE s335141.module_choose_type AS ENUM (
    'з.е',
    'кол-во',
    'все',
    'з.е.',
    'любое'
);


ALTER TYPE s335141.module_choose_type OWNER TO s335141;

--
-- Name: rpd_status; Type: TYPE; Schema: s335141; Owner: s335141
--

CREATE TYPE s335141.rpd_status AS ENUM (
    'новая',
    'черновик',
    'в работе',
    'на доработке',
    'одобрена',
    'на экспертизе',
    'на подписи'
);


ALTER TYPE s335141.rpd_status OWNER TO s335141;

--
-- Name: study_format_type; Type: TYPE; Schema: s335141; Owner: s335141
--

CREATE TYPE s335141.study_format_type AS ENUM (
    'оф',
    'микс',
    'он',
    'о',
    'null',
    ''
);


ALTER TYPE s335141.study_format_type OWNER TO s335141;

--
-- Name: workload_type; Type: TYPE; Schema: s335141; Owner: s335141
--

CREATE TYPE s335141.workload_type AS ENUM (
    'Лек',
    'Пр',
    'Лаб',
    'К',
    'УСРС'
);


ALTER TYPE s335141.workload_type OWNER TO s335141;


CREATE FUNCTION s335141.export_curricula() RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    result JSONB;
BEGIN
	-- SELECT * FROM s335141.sections WHERE ID_curricula = id AND ID_parent_section IS NULL ORDER BY position;

	RETURN (WITH RECURSIVE section_tree AS (
		SELECT 
			s.id,
			s.id_parent_section,
			jsonb_build_object(
				'id', s.id,
				'children', jsonb_agg(
					jsonb_build_object(
						'id', child.id,
						'children', '[]'::jsonb
					)
				) FILTER (WHERE child.id IS NOT NULL)
			) AS json_data
		FROM sections s
		LEFT JOIN sections child ON child.id_parent_section = s.id
		GROUP BY s.id
	)
	SELECT jsonb_pretty(
		jsonb_agg(json_data)
	) AS sections_tree
	FROM section_tree
	WHERE id_parent_section IS NULL);
END;
$$;


ALTER FUNCTION s335141.export_curricula() OWNER TO s335141;

--
-- Name: filter_sections_to_path(integer, integer); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.filter_sections_to_path(root_section_id integer, target_section_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    result JSONB;
BEGIN
    WITH RECURSIVE section_tree AS (
        -- Базовый случай: начинаем с корневого раздела
        SELECT 
            id,
            ID_parent_section,
            name,
            jsonb_build_object(
                'id', id,
                'name', name,
                'children', '[]'::jsonb
            ) AS json_data,
            id = target_section_id AS is_target,
            ARRAY[id] AS path
        FROM sections
        WHERE id = root_section_id
        
        UNION ALL
        
        -- Рекурсивно добавляем дочерние разделы
        SELECT 
            s.id,
            s.ID_parent_section,
            s.name,
            jsonb_build_object(
                'id', s.id,
                'name', s.name,
                'children', '[]'::jsonb
            ) AS json_data,
            s.id = target_section_id OR st.is_target AS is_target,
            st.path || s.id AS path
        FROM sections s
        JOIN section_tree st ON s.ID_parent_section = st.id
        WHERE NOT s.id = ANY(st.path) -- Предотвращаем циклические ссылки
    ),
    filtered_tree AS (
        -- Оставляем только разделы, которые ведут к целевому разделу
        SELECT 
            st.id,
            st.ID_parent_section,
            st.json_data,
            st.is_target
        FROM section_tree st
        WHERE st.is_target OR EXISTS (
            SELECT 1 FROM section_tree child 
            WHERE child.ID_parent_section = st.id AND child.is_target
        )
    )
    SELECT jsonb_agg(ft.json_data)
    INTO result
    FROM filtered_tree ft
    WHERE ft.ID_parent_section IS NULL;
    
    RETURN result;
END;
$$;


ALTER FUNCTION s335141.filter_sections_to_path(root_section_id integer, target_section_id integer) OWNER TO s335141;

--
-- Name: get_full_section_tree(); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.get_full_section_tree() RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    result JSONB;
BEGIN
    -- Создаем временную таблицу для хранения дерева
    CREATE TEMP TABLE IF NOT EXISTS temp_tree (
        id INTEGER PRIMARY KEY,
        id_parent_section INTEGER,
        children JSONB DEFAULT '[]'::jsonb
    );
    
    -- Вставляем все разделы во временную таблицу
    INSERT INTO temp_tree (id, id_parent_section)
    SELECT id, id_parent_section FROM sections;
    
    -- Рекурсивно обновляем детей, начиная с листьев
    WITH RECURSIVE bottom_up AS (
        -- Начинаем с листьев (разделов без детей)
        SELECT id, id_parent_section
        FROM temp_tree
        WHERE id NOT IN (
            SELECT DISTINCT id_parent_section 
            FROM temp_tree 
            WHERE id_parent_section IS NOT NULL
        )
        
        UNION ALL
        
        -- Поднимаемся вверх по иерархии
        SELECT t.id, t.id_parent_section
        FROM temp_tree t
        JOIN bottom_up bu ON t.id = bu.id_parent_section
    )
    -- Для каждого узла обновляем children
    UPDATE temp_tree tt
    SET children = (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', c.id,
            'children', c.children
        )), '[]'::jsonb)
        FROM temp_tree c
        WHERE c.id_parent_section = tt.id
    )
    WHERE tt.id IN (SELECT id FROM bottom_up);
    
    -- Получаем только корневые элементы
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id,
        'children', children
    )), '[]'::jsonb)
    INTO result
    FROM temp_tree
    WHERE id_parent_section IS NULL;
    
    DROP TABLE IF EXISTS temp_tree;
    RETURN result;
END;
$$;


ALTER FUNCTION s335141.get_full_section_tree() OWNER TO s335141;

--
-- Name: insertdiscp(jsonb); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.insertdiscp(data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    existing_module RECORD;
BEGIN
    -- Проверяем, существует ли модуль
    SELECT * INTO existing_module FROM Disciplines WHERE name = (data->>'name');

	IF NOT FOUND THEN
		SELECT Disciplines.* INTO existing_module FROM RPD 
		JOIN Disciplines ON RPD.id_discipline = Disciplines.id
		WHERE RPD.name = (data->>'name') AND Disciplines.name IS NOT NULL;
	END IF;

    IF NOT FOUND THEN
        -- Вставляем новый модуль, если он не существует
        INSERT INTO Disciplines (name)
        VALUES (data->>'name')
        RETURNING id INTO existing_module.id;  -- Сохраняем новый ID в existing_module
        RAISE NOTICE 'Section with ID % inserted.', existing_module.id;
    END IF;

    -- Возвращаем ID существующего или вновь вставленного модуля
    RETURN existing_module.id;
END;
$$;


ALTER FUNCTION s335141.insertdiscp(data jsonb) OWNER TO s335141;

--
-- Name: insertdiscpinmodule(jsonb); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.insertdiscpinmodule(data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    existing_module RECORD;
BEGIN
	SELECT * INTO existing_module FROM Disciplines_in_modules 
	where ID_module = (data->>'ID_module')::INTEGER
	AND ID_RPD = (data->>'ID_RPD')::INTEGER;

	IF NOT FOUND THEN
        INSERT INTO Disciplines_in_modules 
		(implementer, position, ID_RPD, ID_module, changable)
        VALUES (data->>'implementer', 
		(data->>'position')::INTEGER, 
		(data->>'ID_RPD')::INTEGER, 
		(data->>'ID_module')::INTEGER,
		(data->>'changable')::BOOLEAN)
		RETURNING id INTO existing_module.id;
    END IF;
	
    RETURN existing_module.id;
END;
$$;


ALTER FUNCTION s335141.insertdiscpinmodule(data jsonb) OWNER TO s335141;

--
-- Name: insertrpd(jsonb); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.insertrpd(data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    existing_module RECORD;
BEGIN
    -- Проверяем, существует ли модуль
    SELECT * INTO existing_module FROM RPD WHERE id_isu = (data->>'id_isu')::INTEGER;

    IF NOT FOUND THEN
        -- Вставляем новый модуль, если он не существует
        INSERT INTO RPD (id_isu, name, study_format, id_discipline, status, comment)
        VALUES ((data->>'id_isu')::INTEGER, 
		data->>'name', 
		(data->>'study_format')::"study_format_type", 
		(data->>'id_discipline')::INTEGER,
		(data->>'status')::"rpd_status",
		data->>'comment');
    ELSE
		UPDATE RPD
		SET name = data->>'name',
			study_format = (data->>'study_format')::"study_format_type",
			id_discipline = (data->>'id_discipline')::INTEGER,
			status = (data->>'status')::"rpd_status",
			comment = (data->>'comment')
		WHERE id_isu = (data->>'id_isu')::INTEGER;
    END IF;

	RETURN 0;
END;
$$;


ALTER FUNCTION s335141.insertrpd(data jsonb) OWNER TO s335141;

--
-- Name: insertsection(jsonb); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.insertsection(data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    existing_module RECORD;
BEGIN
	SELECT * INTO existing_module FROM sections 
	where ID_module = (data->>'ID_module')::INTEGER
	AND ID_parent_section = (data->>'ID_parent_section')::INTEGER;

	IF NOT FOUND THEN
        INSERT INTO sections (position, ID_curricula, ID_module, ID_parent_section)
        VALUES ((data->>'position')::INTEGER, 
		(data->>'ID_curricula')::INTEGER, 
		(data->>'ID_module')::INTEGER, 
		(data->>'ID_parent_section')::INTEGER)
		RETURNING id INTO existing_module.id;
		RAISE NOTICE 'Section with ID % inserted.', (data->>'id_isu')::INTEGER;
    END IF;
	
    RETURN existing_module.id;
END;
$$;


ALTER FUNCTION s335141.insertsection(data jsonb) OWNER TO s335141;

--
-- Name: insertsemesterrpd(jsonb); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.insertsemesterrpd(data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    existing_record RECORD;
    rpd_id INT;
    semester_id INT;
    cr INT;
    semester_key TEXT;
    semester_value jsonb;
    assessment_item jsonb;
    workload_item jsonb;
BEGIN
    RAISE NOTICE 'Начало обработки';
    
    -- Получаем ID РПД
    rpd_id := (data->>'id_RPD')::INTEGER;

    -- Обрабатываем каждый семестр из входных данных
    FOR semester_key, semester_value IN SELECT * FROM jsonb_each(data->'semesters') LOOP
        -- Извлекаем количество кредитов
        cr := (semester_value->>'credits')::INTEGER;

        -- Проверяем существование семестра
        SELECT id INTO semester_id FROM Semester_RPD 
        WHERE id_RPD = rpd_id
        AND number_from_start = semester_key::INT;

        IF NOT FOUND THEN
            -- Создаем новый семестр
            INSERT INTO Semester_RPD 
            (number_from_start, credits, id_RPD)
            VALUES (semester_key::INT, cr, rpd_id)
            RETURNING id INTO semester_id;
            RAISE NOTICE 'Добавлен новый семестр ID: %', semester_id;
        ELSE
            -- Обновляем существующий семестр
            UPDATE Semester_RPD
            SET credits = cr
            WHERE id_RPD = rpd_id
            AND number_from_start = semester_key::INT;
            RAISE NOTICE 'Обновлен существующий семестр ID: %', semester_id;
        END IF;

        -- Обработка форм аттестации
        FOR assessment_item IN SELECT * FROM jsonb_array_elements(semester_value->'assessment') LOOP
            -- Проверяем существование формы аттестации
            PERFORM 1 FROM assessments 
            WHERE id_sem = semester_id
            AND type = (assessment_item->>'type')::assessment_type;

			RAISE NOTICE 'ЭТО ТИП%', (assessment_item->>'type');
    
            IF NOT FOUND THEN
                INSERT INTO assessments 
                (type, id_sem)
                VALUES ((assessment_item->>'type')::assessment_type, semester_id);
                RAISE NOTICE 'Добавлена новая форма аттестации: %', (assessment_item->>'type');
            END IF;
        END LOOP;

        -- Удаляем формы аттестации, которых нет во входных данных
        DELETE FROM assessments
        WHERE id_sem = semester_id
        AND NOT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(semester_value->'assessment') AS a
            WHERE (a->>'type')::assessment_type = assessments.type
        );

        -- Обработка видов нагрузки
        FOR workload_item IN SELECT * FROM jsonb_array_elements(semester_value->'workload') LOOP
            -- Проверяем существование вида нагрузки
            PERFORM 1 FROM Workloads 
            WHERE id_sem = semester_id
            AND type = (workload_item->>'type')::workload_type;
    
            IF NOT FOUND THEN
                -- Добавляем новый вид нагрузки
                INSERT INTO Workloads 
                (hours, type, id_sem)
                VALUES ((workload_item->>'hours')::INT,
                       (workload_item->>'type')::workload_type, 
                       semester_id);
                RAISE NOTICE 'Добавлен новый вид нагрузки: %', (workload_item->>'type');
            ELSE
                -- Обновляем существующий вид нагрузки
                UPDATE Workloads
                SET hours = (workload_item->>'hours')::INT
                WHERE id_sem = semester_id
                AND type = (workload_item->>'type')::workload_type;
                RAISE NOTICE 'Обновлен вид нагрузки: %', (workload_item->>'type');
            END IF;
        END LOOP;

        -- Удаляем виды нагрузки, которых нет во входных данных
        DELETE FROM Workloads
        WHERE id_sem = semester_id
        AND NOT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(semester_value->'workload') AS w
            WHERE (w->>'type')::workload_type = Workloads.type
        );
    END LOOP;

	DELETE FROM semester_rpd
	WHERE id_RPD = rpd_id
	AND NOT EXISTS (
		SELECT 1
		FROM jsonb_each(data->'semesters') AS s(key, value)
		WHERE s.key::INT = semester_rpd.number_from_start
	);
    
    RETURN 1; -- Возвращаем 1 в случае успеха
END;
$$;


ALTER FUNCTION s335141.insertsemesterrpd(data jsonb) OWNER TO s335141;

--
-- Name: is_section_in_subtree(integer, integer); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.is_section_in_subtree(parent_id integer, target_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    result BOOLEAN;
BEGIN
    -- Рекурсивный запрос для поиска в поддереве
    WITH RECURSIVE subtree AS (
        -- Базовый случай: начальная секция
        SELECT id, id_parent_section
        FROM sections
        WHERE id = parent_id
        
        UNION ALL
        
        -- Рекурсивный случай: все дочерние секции
        SELECT s.id, s.id_parent_section
        FROM sections s
        JOIN subtree st ON s.id_parent_section = st.id
    )
    SELECT EXISTS (
        SELECT 1 FROM subtree WHERE id = target_id
    ) INTO result;
    
    RETURN result;
END;
$$;


ALTER FUNCTION s335141.is_section_in_subtree(parent_id integer, target_id integer) OWNER TO s335141;


--
-- Name: memo_insert_discp_starts(integer, integer, integer, integer); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.memo_insert_discp_starts(p_sem integer, p_id_rpd integer, p_id_curricula integer, p_id_change integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_discp_module_id integer;
    v_discp_start_id integer;
BEGIN
    -- Создаем временную таблицу для хранения ID дисциплин
    CREATE TEMP TABLE temp_discp_modules AS
    SELECT dm.id
    FROM Disciplines_in_modules dm
    JOIN Sections s ON s.id_module = dm.id_module
    WHERE dm.ID_RPD = p_id_rpd AND s.id_curricula = p_id_curricula;

    -- Вставляем записи в Discp_starts и сразу связываем с изменениями
    FOR v_discp_module_id IN SELECT id FROM temp_discp_modules
    LOOP
        INSERT INTO Discp_starts (sem, ID_discp_module)
        VALUES (p_sem, v_discp_module_id)
        RETURNING id INTO v_discp_start_id;

        INSERT INTO Change_discp_starts (id_change, ID_discp_start)
        VALUES (p_id_change, v_discp_start_id);
    END LOOP;

    -- Удаляем временную таблицу
    DROP TABLE temp_discp_modules;
END;
$$;


ALTER FUNCTION s335141.memo_insert_discp_starts(p_sem integer, p_id_rpd integer, p_id_curricula integer, p_id_change integer) OWNER TO s335141;

--
-- Name: memo_insert_discp_starts(integer, integer, integer, integer, integer); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.memo_insert_discp_starts(p_sem integer, p_id_rpd integer, p_id_curricula integer, p_id_change integer, p_id_module integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	inserted_id INT;
BEGIN
	 -- Вставка в таблицу Discp_starts и получение идентификаторов
    INSERT INTO Discp_starts (sem, ID_discp_module)
    SELECT p_sem, dm.id
    FROM Disciplines_in_modules dm
    JOIN Sections s ON s.id_module = dm.id_module
    WHERE dm.ID_RPD = p_id_rpd AND s.id_curricula = p_id_curricula AND s.id_module = p_id_module
    RETURNING id INTO inserted_id;

	INSERT INTO Change_discp_starts (id_change, ID_discp_start)
	VALUES (p_id_change, inserted_id);
END;
$$;


ALTER FUNCTION s335141.memo_insert_discp_starts(p_sem integer, p_id_rpd integer, p_id_curricula integer, p_id_change integer, p_id_module integer) OWNER TO s335141;


--
-- Name: uniondiscp(jsonb); Type: FUNCTION; Schema: s335141; Owner: s335141
--

CREATE FUNCTION s335141.uniondiscp(data jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	discp_id INT;
	discp_element jsonb;
	old_id INT;
BEGIN
	INSERT INTO Disciplines (name) 
	VALUES (data->>'name') 
	ON CONFLICT (name) 
	DO UPDATE SET name = EXCLUDED.name 
	RETURNING id INTO discp_id;

	IF discp_id IS NULL THEN
        SELECT id INTO discp_id 
        FROM Disciplines 
        WHERE name = data->>'name';
    END IF;

	FOR discp_element IN SELECT * FROM jsonb_array_elements(data->'discp')
	LOOP
		old_id := (discp_element#>>'{}')::INT;
		UPDATE RPD SET id_discipline = discp_id WHERE id_discipline = old_id;
		UPDATE s338859.Mentors_in_desciplines SET id_discipline = discp_id WHERE id_discipline = old_id;
		UPDATE s338859.Disciplines_of_teachers SET id_discipline = discp_id WHERE id_discipline = old_id;
		
		DELETE FROM Disciplines WHERE id = old_id;
	END LOOP;

	RETURN discp_id;
END;
$$;


ALTER FUNCTION s335141.uniondiscp(data jsonb) OWNER TO s335141;
--

CREATE TABLE s335141.appuser (
    id integer NOT NULL,
    login character varying(50) NOT NULL,
    password character varying(255) NOT NULL,
    role character varying(20) DEFAULT 'user'::character varying
);


ALTER TABLE s335141.appuser OWNER TO s335141;

--
-- Name: assessments; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.assessments (
    id integer NOT NULL,
    type s335141.assessment_type NOT NULL,
    id_sem integer NOT NULL
);


ALTER TABLE s335141.assessments OWNER TO s335141;

--
-- Name: TABLE assessments; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.assessments IS 'Виды аттестаций по дисциплинам';


--
-- Name: COLUMN assessments.type; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.assessments.type IS 'Тип аттестации';


--
-- Name: COLUMN assessments.id_sem; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.assessments.id_sem IS 'Ссылка на семестр в РПД';


--
-- Name: assessments_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.assessments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.assessments_id_seq OWNER TO s335141;

--
-- Name: assessments_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.assessments_id_seq OWNED BY s335141.assessments.id;

--
-- Name: change_discp_module; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.change_discp_module (
    id_change integer NOT NULL,
    id_discp_module integer NOT NULL
);


ALTER TABLE s335141.change_discp_module OWNER TO s335141;

--
-- Name: TABLE change_discp_module; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.change_discp_module IS 'Связь изменений с дисциплинами в модулях';


--
-- Name: COLUMN change_discp_module.id_change; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.change_discp_module.id_change IS 'Ссылка на запись об изменении';


--
-- Name: COLUMN change_discp_module.id_discp_module; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.change_discp_module.id_discp_module IS 'Ссылка на дисциплину в модуле';


--
-- Name: change_discp_starts; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.change_discp_starts (
    id_change integer NOT NULL,
    id_discp_start integer NOT NULL
);


ALTER TABLE s335141.change_discp_starts OWNER TO s335141;

--
-- Name: TABLE change_discp_starts; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.change_discp_starts IS 'Связь изменений с периодами начала дисциплин';


--
-- Name: COLUMN change_discp_starts.id_change; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.change_discp_starts.id_change IS 'Ссылка на запись об изменении';


--
-- Name: COLUMN change_discp_starts.id_discp_start; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.change_discp_starts.id_discp_start IS 'Ссылка на период начала дисциплины';


--
-- Name: change_rpd; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.change_rpd (
    id_change integer NOT NULL,
    id_rpd integer NOT NULL
);


ALTER TABLE s335141.change_rpd OWNER TO s335141;

--
-- Name: TABLE change_rpd; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.change_rpd IS 'Связь изменений с рабочими программами дисциплин';


--
-- Name: COLUMN change_rpd.id_change; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.change_rpd.id_change IS 'Ссылка на запись об изменении';


--
-- Name: COLUMN change_rpd.id_rpd; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.change_rpd.id_rpd IS 'Ссылка на РПД';


--
-- Name: change_section; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.change_section (
    id_change integer NOT NULL,
    id_section integer NOT NULL
);


ALTER TABLE s335141.change_section OWNER TO s335141;

--
-- Name: changes; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.changes (
    id integer NOT NULL,
    type s335141.change_type NOT NULL,
    comment text,
    id_memorandum integer NOT NULL
);


ALTER TABLE s335141.changes OWNER TO s335141;

--
-- Name: TABLE changes; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.changes IS 'Журнал изменений учебных планов';


--
-- Name: COLUMN changes.type; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.changes.type IS 'Тип изменения (добавление/удаление)';


--
-- Name: COLUMN changes.comment; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.changes.comment IS 'Пояснение к изменению';


--
-- Name: COLUMN changes.id_memorandum; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.changes.id_memorandum IS 'Ссылка на меморандум, утверждающий изменение';


--
-- Name: changes_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.changes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.changes_id_seq OWNER TO s335141;

--
-- Name: changes_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.changes_id_seq OWNED BY s335141.changes.id;


--
-- Name: curricula; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.curricula (
    id_isu integer NOT NULL,
    name character varying(256) NOT NULL,
    year integer NOT NULL,
    degree s335141.degree_type NOT NULL,
    head character varying(64) NOT NULL,
    status boolean
);


ALTER TABLE s335141.curricula OWNER TO s335141;

--
-- Name: disciplines; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.disciplines (
    id integer NOT NULL,
    name character varying(256) NOT NULL,
    comment text
);


ALTER TABLE s335141.disciplines OWNER TO s335141;

--
-- Name: disciplines_in_modules; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.disciplines_in_modules (
    id integer NOT NULL,
    implementer character varying(64) NOT NULL,
    "position" integer NOT NULL,
    id_rpd integer NOT NULL,
    id_module integer NOT NULL,
    changable boolean NOT NULL,
    CONSTRAINT chk_position_positive CHECK (("position" > 0))
);


ALTER TABLE s335141.disciplines_in_modules OWNER TO s335141;

--
-- Name: TABLE disciplines_in_modules; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.disciplines_in_modules IS 'Связь дисциплин (РПД) с учебными модулями';


--
-- Name: COLUMN disciplines_in_modules.implementer; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.disciplines_in_modules.implementer IS 'Ответственный за реализацию';


--
-- Name: COLUMN disciplines_in_modules."position"; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.disciplines_in_modules."position" IS 'Позиция в модуле (порядковый номер)';


--
-- Name: COLUMN disciplines_in_modules.id_rpd; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.disciplines_in_modules.id_rpd IS 'Ссылка на рабочую программу дисциплины';


--
-- Name: COLUMN disciplines_in_modules.id_module; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.disciplines_in_modules.id_module IS 'Ссылка на учебный модуль';


--
-- Name: discp_starts; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.discp_starts (
    id integer NOT NULL,
    id_discp_module integer NOT NULL,
    sem integer NOT NULL,
    CONSTRAINT chk_sem_positive CHECK ((sem > 0))
);


ALTER TABLE s335141.discp_starts OWNER TO s335141;

--
-- Name: TABLE discp_starts; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.discp_starts IS 'Семестры начала дисциплин в модулях';


--
-- Name: COLUMN discp_starts.id_discp_module; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.discp_starts.id_discp_module IS 'Ссылка на дисциплину в модуле';


--
-- Name: COLUMN discp_starts.sem; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.discp_starts.sem IS 'Номер семестра, в котором начинается дисциплина';


--
-- Name: modules; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.modules (
    id_isu integer NOT NULL,
    name character varying(256) NOT NULL,
    choose_count integer,
    type_choose s335141.module_choose_type NOT NULL
);


ALTER TABLE s335141.modules OWNER TO s335141;

--
-- Name: rpd; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.rpd (
    id_isu integer NOT NULL,
    name character varying(256) NOT NULL,
    comment text,
    id_discipline integer NOT NULL,
    status s335141.rpd_status NOT NULL,
    study_format s335141.study_format_type
);


ALTER TABLE s335141.rpd OWNER TO s335141;

--
-- Name: TABLE rpd; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.rpd IS 'Рабочие программы дисциплин';


--
-- Name: semester_rpd; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.semester_rpd (
    id integer NOT NULL,
    number_from_start integer NOT NULL,
    credits integer NOT NULL,
    id_rpd integer NOT NULL,
    CONSTRAINT chk_number_positive CHECK ((number_from_start > 0))
);


ALTER TABLE s335141.semester_rpd OWNER TO s335141;

--
-- Name: TABLE semester_rpd; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.semester_rpd IS 'Семестры для рабочих программ дисциплин (РПД)';


--
-- Name: COLUMN semester_rpd.number_from_start; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.semester_rpd.number_from_start IS 'Порядковый номер семестра с начала обучения';


--
-- Name: COLUMN semester_rpd.credits; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.semester_rpd.credits IS 'Количество зачетных единиц для семестра';


--
-- Name: COLUMN semester_rpd.id_rpd; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.semester_rpd.id_rpd IS 'Ссылка на рабочую программу дисциплины';


--
-- Name: workloads; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.workloads (
    id integer NOT NULL,
    hours integer,
    type s335141.workload_type NOT NULL,
    id_sem integer NOT NULL
);


ALTER TABLE s335141.workloads OWNER TO s335141;

--
-- Name: TABLE workloads; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.workloads IS 'Учебная нагрузка по видам занятий';


--
-- Name: COLUMN workloads.hours; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.workloads.hours IS 'Количество академических часов';


--
-- Name: COLUMN workloads.type; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.workloads.type IS 'Тип нагрузки (лекции/практики/лабы/консультации)';


--
-- Name: COLUMN workloads.id_sem; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.workloads.id_sem IS 'Ссылка на семестр в РПД';


--
-- Name: disciplines_full; Type: VIEW; Schema: s335141; Owner: s335141
--

CREATE VIEW s335141.disciplines_full AS
 SELECT r.name AS rpd_name,
    r.status,
    d.name AS discipline_name,
    m.name AS module_name,
    m.type_choose,
    ((ds.sem + s.number_from_start) - 1) AS semester_number,
    s.credits,
    dim."position",
    dim.implementer,
    sum(
        CASE
            WHEN (w.type = 'Лек'::s335141.workload_type) THEN w.hours
            ELSE 0
        END) AS lectures_hours,
    sum(
        CASE
            WHEN (w.type = 'Пр'::s335141.workload_type) THEN w.hours
            ELSE 0
        END) AS practice_hours,
    sum(
        CASE
            WHEN (w.type = 'Лаб'::s335141.workload_type) THEN w.hours
            ELSE 0
        END) AS labs_hours
   FROM ((((((s335141.rpd r
     JOIN s335141.disciplines d ON ((r.id_discipline = d.id)))
     JOIN s335141.disciplines_in_modules dim ON ((dim.id_rpd = r.id_isu)))
     JOIN s335141.discp_starts ds ON ((ds.id_discp_module = dim.id)))
     JOIN s335141.modules m ON ((dim.id_module = m.id_isu)))
     JOIN s335141.semester_rpd s ON ((s.id_rpd = r.id_isu)))
     JOIN s335141.workloads w ON ((w.id_sem = s.id)))
  GROUP BY r.name, r.status, d.name, m.name, m.type_choose, s.number_from_start, s.credits, dim."position", dim.implementer, m.id_isu, ds.sem;


ALTER VIEW s335141.disciplines_full OWNER TO s335141;

--
-- Name: disciplines_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.disciplines_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.disciplines_id_seq OWNER TO s335141;

--
-- Name: disciplines_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.disciplines_id_seq OWNED BY s335141.disciplines.id;


--
-- Name: disciplines_in_modules_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.disciplines_in_modules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.disciplines_in_modules_id_seq OWNER TO s335141;

--
-- Name: disciplines_in_modules_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.disciplines_in_modules_id_seq OWNED BY s335141.disciplines_in_modules.id;


--
-- Name: discp_starts_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.discp_starts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.discp_starts_id_seq OWNER TO s335141;

--
-- Name: discp_starts_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.discp_starts_id_seq OWNED BY s335141.discp_starts.id;


--
-- Name: groups; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.groups (
    id integer NOT NULL
);


ALTER TABLE s335141.groups OWNER TO s335141;

--
-- Name: memorandums; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.memorandums (
    id integer NOT NULL,
    date date DEFAULT CURRENT_DATE NOT NULL,
    link character varying(256)
);


ALTER TABLE s335141.memorandums OWNER TO s335141;

--
-- Name: TABLE memorandums; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON TABLE s335141.memorandums IS 'Меморандумы и служебные записки';


--
-- Name: COLUMN memorandums.date; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.memorandums.date IS 'Дата создания документа';


--
-- Name: COLUMN memorandums.link; Type: COMMENT; Schema: s335141; Owner: s335141
--

COMMENT ON COLUMN s335141.memorandums.link IS 'Ссылка на электронный документ';


--
-- Name: memorandums_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.memorandums_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.memorandums_id_seq OWNER TO s335141;

--
-- Name: memorandums_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.memorandums_id_seq OWNED BY s335141.memorandums.id;


--
-- Name: sections; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.sections (
    id integer NOT NULL,
    "position" integer NOT NULL,
    id_curricula integer NOT NULL,
    id_module integer NOT NULL,
    id_parent_section integer
);


ALTER TABLE s335141.sections OWNER TO s335141;

--
-- Name: sections_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.sections_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.sections_id_seq OWNER TO s335141;

--
-- Name: sections_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.sections_id_seq OWNED BY s335141.sections.id;


--
-- Name: semester_rpd_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.semester_rpd_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.semester_rpd_id_seq OWNER TO s335141;

--
-- Name: semester_rpd_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.semester_rpd_id_seq OWNED BY s335141.semester_rpd.id;


--
-- Name: specialties; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.specialties (
    code character varying(16) NOT NULL,
    name character varying(64) NOT NULL
);


ALTER TABLE s335141.specialties OWNER TO s335141;

--
-- Name: students; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.students (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    group_id integer
);


ALTER TABLE s335141.students OWNER TO s335141;

--
-- Name: track_specialty; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.track_specialty (
    id_track integer NOT NULL,
    code character varying(16) NOT NULL
);


ALTER TABLE s335141.track_specialty OWNER TO s335141;

--
-- Name: tracks; Type: TABLE; Schema: s335141; Owner: s335141
--

CREATE TABLE s335141.tracks (
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    number integer NOT NULL,
    count_limit integer,
    id_section integer
);


ALTER TABLE s335141.tracks OWNER TO s335141;

--
-- Name: tracks_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.tracks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.tracks_id_seq OWNER TO s335141;

--
-- Name: tracks_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.tracks_id_seq OWNED BY s335141.tracks.id;


--
-- Name: workloads_id_seq; Type: SEQUENCE; Schema: s335141; Owner: s335141
--

CREATE SEQUENCE s335141.workloads_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE s335141.workloads_id_seq OWNER TO s335141;

--
-- Name: workloads_id_seq; Type: SEQUENCE OWNED BY; Schema: s335141; Owner: s335141
--

ALTER SEQUENCE s335141.workloads_id_seq OWNED BY s335141.workloads.id;


--
COPY s335141.assessments (id, type, id_sem) FROM stdin;
2900	Экзамен	3363
2901	Экзамен	3364
2902	Экзамен	3365
2903	Экзамен	3366
2904	Экзамен	3367
2905	Экзамен	3368
2907	Зачет	3370
2908	Зачет	3723
2909	Зачет	3725
2910	Зачет	3726
2911	Зачет	3727
2914	Экзамен	3382
2915	Зачет	3383
2916	Зачет	3384
2917	Зачет	3385
2918	Зачет	3386
2919	Зачет	3387
2920	Зачет	3388
2921	Зачет	3389
2922	Зачет	3390
2923	Зачет	3391
2924	Зачет	3392
2925	Зачет	3393
2926	Экзамен	3394
2927	Зачет	3395
2928	Зачет	3396
2929	Дифф. зачет	3397
2895	Экзамен	3554
2930	Зачет	3398
2897	Курсовая работа	3554
2931	Экзамен	3399
2932	Зачет	3400
2933	Экзамен	3401
2934	Зачет	3402
2935	Экзамен	3403
2936	Зачет	3404
2937	Экзамен	3405
2938	Экзамен	3406
2939	Зачет	3407
2940	Экзамен	3408
2941	Экзамен	3409
2942	Экзамен	3410
2943	Зачет	3411
2944	Экзамен	3412
2945	Экзамен	3413
2946	Экзамен	3414
3857	Зачет	4159
3858	Экзамен	4160
2954	Экзамен	3422
2955	Зачет	3423
2956	Экзамен	3424
2957	Зачет	3425
2958	Экзамен	3426
2959	Зачет	3427
2960	Зачет	3428
3859	Зачет	4161
2962	Экзамен	3429
3860	Экзамен	4162
2964	Зачет	3431
2965	Экзамен	3432
3861	Зачет	4163
3862	Экзамен	4164
3863	Зачет	4165
3864	Экзамен	4166
3865	Зачет	4167
3866	Экзамен	4168
2972	Экзамен	3439
2973	Экзамен	3440
2974	Зачет	3441
2975	Экзамен	3442
3867	Зачет	4169
2977	Экзамен	3444
2979	Зачет	3446
2981	Зачет	3448
2982	Экзамен	3449
2983	Экзамен	3450
2984	Зачет	3451
2985	Зачет	3452
2986	Зачет	3453
2988	Экзамен	3455
2989	Зачет	3456
2990	Зачет	3457
2994	Экзамен	3461
2995	Курсовой проект	3461
2996	Экзамен	3462
2997	Курсовой проект	3462
2998	Экзамен	3463
2999	Курсовой проект	3463
3000	Экзамен	3464
3001	Курсовой проект	3464
3002	Экзамен	3465
3003	Курсовой проект	3465
3004	Экзамен	3466
3005	Курсовой проект	3466
3006	Экзамен	3467
3007	Зачет	3468
3008	Экзамен	3469
3009	Зачет	3470
3010	Экзамен	3471
3011	Экзамен	3472
3012	Курсовой проект	3472
3013	Экзамен	3473
3014	Экзамен	3474
3015	Экзамен	3475
3016	Экзамен	3476
3017	Курсовой проект	3476
3018	Зачет	3477
3020	Зачет	3479
3022	Экзамен	3481
3023	Экзамен	3482
3024	Зачет	3483
3025	Курсовой проект	3483
3026	Зачет	3484
3027	Зачет	3485
3028	Экзамен	3486
3029	Курсовой проект	3486
3030	Зачет	3487
3031	Экзамен	3488
3032	Зачет	3489
3033	Зачет	3490
3034	Экзамен	3491
3035	Экзамен	3492
3036	Экзамен	3493
3037	Экзамен	3494
3038	Экзамен	3495
3039	Экзамен	3496
3040	Экзамен	3497
3041	Экзамен	3498
3042	Экзамен	3499
3043	Экзамен	3500
3044	Зачет	3501
3045	Зачет	3502
3046	Зачет	3503
3047	Зачет	3504
3049	Экзамен	3506
3051	Зачет	3508
3052	Экзамен	3509
3053	Зачет	3510
3054	Экзамен	3511
3055	Зачет	3512
3056	Экзамен	3513
3057	Экзамен	3514
3058	Зачет	3515
3059	Курсовая работа	3515
3060	Экзамен	3516
3062	Курсовая работа	3517
3063	Зачет	3518
3064	Экзамен	3519
3065	Зачет	3520
3066	Экзамен	3521
3067	Зачет	3770
3068	Экзамен	3771
3069	Экзамен	3522
3070	Зачет	3523
3071	Экзамен	3524
3072	Зачет	3525
3073	Курсовая работа	3525
3074	Экзамен	3526
3075	Зачет	3527
3076	Экзамен	3528
3077	Экзамен	3529
3078	Зачет	3530
3079	Экзамен	3531
3080	Зачет	3532
3081	Курсовая работа	3532
3082	Зачет	3533
3730	Экзамен	4067
3731	Экзамен	4068
3736	Зачет	4073
3737	Зачет	4074
3738	Зачет	4075
3739	Экзамен	4077
3740	Экзамен	4078
3741	Зачет	4079
3742	Зачет	4080
3743	Экзамен	4082
3744	Экзамен	4083
3745	Экзамен	4084
3746	Экзамен	4085
3747	Зачет	4086
3748	Курсовой проект	4086
3083	Дифф. зачет	3534
3084	Дифф. зачет	3535
3085	Экзамен	3536
3086	Зачет	3772
3087	Экзамен	3537
3088	Экзамен	3538
3089	Зачет	3539
3090	Зачет	3540
3092	Зачет	3542
3093	Экзамен	3543
3094	Экзамен	3773
3839	Экзамен	4153
3840	Экзамен	4154
3582	Экзамен	3983
3607	Зачет	3984
3608	Экзамен	3985
3611	Экзамен	3986
3612	Зачет	3987
3613	Зачет	3988
3614	Зачет	3989
3615	Зачет	3990
3616	Зачет	3991
3617	Экзамен	3992
3618	Зачет	3993
3619	Экзамен	3994
3620	Зачет	3995
3621	Экзамен	3996
3622	Экзамен	3997
3623	Экзамен	3998
3624	Экзамен	3999
3625	Экзамен	4000
3630	Зачет	4001
3631	Зачет	4002
3635	Зачет	4003
3636	Экзамен	4004
3637	Зачет	4005
3638	Зачет	4006
3639	Экзамен	4007
3640	Экзамен	4008
3553	Экзамен	3982
3641	Зачет	4009
3642	Зачет	4010
3643	Курсовая работа	4010
3644	Экзамен	4011
3645	Зачет	4012
3646	Экзамен	4013
3251	Экзамен	3915
3252	Экзамен	3916
3253	Экзамен	3917
3254	Экзамен	3918
3255	Экзамен	3919
3256	Зачет	3920
3647	Зачет	4014
3648	Зачет	4015
3259	Экзамен	3921
3260	Зачет	3922
3261	Зачет	3923
3262	Зачет	3924
3263	Зачет	3925
3264	Зачет	3926
3265	Зачет	3927
3266	Зачет	3928
3267	Зачет	3929
3268	Зачет	3930
3269	Зачет	3931
3270	Зачет	3932
3271	Зачет	3933
3272	Зачет	3934
3273	Зачет	3935
3274	Зачет	3936
3275	Зачет	3937
3276	Зачет	3938
3277	Зачет	3939
3278	Зачет	3940
3279	Зачет	3941
3280	Зачет	3942
3281	Зачет	3943
3282	Зачет	3944
3283	Зачет	3945
3284	Зачет	3946
3285	Зачет	3947
3286	Зачет	3948
3287	Зачет	3949
3288	Зачет	3950
3289	Зачет	3951
3290	Зачет	3952
3291	Зачет	3953
3292	Зачет	3954
3293	Зачет	3955
3294	Экзамен	3956
3295	Экзамен	3957
3296	Экзамен	3958
3297	Зачет	3959
3298	Экзамен	3960
3299	Экзамен	3961
3300	Курсовой проект	3428
3301	Экзамен	3963
3302	Курсовой проект	3963
3303	Экзамен	3964
3304	Курсовой проект	3964
3307	Экзамен	3965
3308	Курсовой проект	3965
3309	Зачет	3966
3310	Экзамен	3967
3312	Экзамен	3968
3313	Экзамен	3969
3314	Экзамен	3970
3315	Экзамен	3971
3316	Зачет	3972
3317	Курсовой проект	3972
3318	Экзамен	3973
3319	Экзамен	3974
3320	Экзамен	3975
3649	Экзамен	4016
3650	Зачет	4017
3324	Экзамен	3517
3325	Экзамен	3976
3326	Экзамен	3977
3327	Экзамен	3978
3328	Курсовая работа	3978
3651	Зачет	4018
3652	Экзамен	4019
3653	Экзамен	4020
3655	Экзамен	4021
3656	Зачет	4022
3657	Экзамен	4023
3658	Зачет	4024
3659	Зачет	4025
3660	Экзамен	4026
3661	Зачет	4027
3662	Экзамен	4028
3663	Зачет	4029
3664	Экзамен	4030
3665	Зачет	4031
3666	Экзамен	4032
3668	Экзамен	4033
3669	Курсовой проект	4033
3670	Зачет	4034
3671	Экзамен	4035
3672	Зачет	4036
3673	Экзамен	4037
3674	Экзамен	4038
3675	Зачет	4039
3676	Зачет	4040
3677	Экзамен	4041
3678	Зачет	4042
3679	Экзамен	4043
3681	Зачет	4044
3682	Экзамен	4045
3683	Зачет	4046
3684	Экзамен	4047
3685	Зачет	4048
3686	Экзамен	4049
3687	Зачет	4050
3688	Курсовая работа	4050
3689	Экзамен	4051
3690	Зачет	4052
3691	Зачет	4053
3692	Зачет	4054
3693	Экзамен	4055
3694	Зачет	4056
3695	Экзамен	4057
3696	Зачет	4058
3697	Курсовая работа	4058
3698	Экзамен	4059
3699	Зачет	4060
3700	Экзамен	4061
3701	Дифф. зачет	4062
3702	Дифф. зачет	4063
3749	Экзамен	4087
3750	Экзамен	4088
3751	Зачет	3541
3752	Экзамен	4089
3753	Курсовая работа	4089
3754	Зачет	4090
3755	Зачет	4091
3756	Зачет	4092
3757	Экзамен	4093
3758	Зачет	4094
3759	Экзамен	4095
3760	Экзамен	4096
3761	Курсовая работа	4096
3762	Зачет	4097
3763	Зачет	4098
3764	Экзамен	4099
3765	Дифф. зачет	4100
3766	Дифф. зачет	4101
3767	Дифф. зачет	4102
3768	Дифф. зачет	4103
3769	Дифф. зачет	4104
3852	Зачет	4155
3853	Зачет	3505
3855	Дифф. зачет	4156
3856	Дифф. зачет	4157
3868	Экзамен	4170
3870	Экзамен	4171
3871	Зачет	4172
3872	Зачет	4173
3873	Зачет	4174
3874	Зачет	4175
3875	Зачет	4176
3876	Зачет	4177
3877	Зачет	4178
3878	Зачет	4179
3879	Зачет	4180
3880	Зачет	4181
3881	Зачет	4182
3882	Зачет	4183
3883	Зачет	4184
3884	Зачет	4185
3885	Зачет	4186
3886	Зачет	4187
3887	Экзамен	4188
3888	Экзамен	4189
3889	Экзамен	4190
3890	Экзамен	4191
3891	Экзамен	4192
3892	Экзамен	4193
3893	Экзамен	4194
3894	Экзамен	4195
3895	Экзамен	4196
3896	Экзамен	4197
3897	Экзамен	4198
3898	Экзамен	4199
3806	Экзамен	4142
3807	Экзамен	4143
3808	Зачет	4144
3809	Зачет	4145
3810	Зачет	4146
3811	Зачет	4147
3812	Зачет	4148
3813	Зачет	4149
3899	Экзамен	4200
3900	Экзамен	4201
3901	Экзамен	4202
3902	Зачет	4203
3903	Экзамен	4204
3904	Экзамен	4205
3905	Экзамен	4206
3906	Зачет	4207
3907	Зачет	4208
3908	Экзамен	4209
3913	Зачет	4210
3914	Зачет	4211
3915	Курсовая работа	4211
3916	Зачет	4212
3917	Зачет	4213
3918	Экзамен	4214
3919	Экзамен	4215
3920	Экзамен	4216
3921	Экзамен	4217
3923	Экзамен	4218
3924	Зачет	4219
3925	Экзамен	4220
3926	Экзамен	4221
3927	Курсовой проект	4221
3928	Экзамен	4222
3929	Экзамен	4223
3930	Зачет	4224
3931	Экзамен	4225
3932	Экзамен	4226
3933	Курсовой проект	4226
3934	Экзамен	4227
3935	Экзамен	4228
3937	Экзамен	4229
3938	Зачет	4230
3939	Экзамен	4231
3940	Экзамен	4232
3941	Экзамен	4233
3942	Экзамен	4234
3943	Зачет	4235
3945	Зачет	4237
3946	Экзамен	4238
3947	Зачет	4239
3948	Экзамен	4240
3949	Зачет	4241
3950	Экзамен	4242
3951	Зачет	4243
3952	Экзамен	4244
3954	Зачет	4076
3955	Экзамен	4245
3956	Экзамен	4246
3957	Экзамен	4247
3958	Экзамен	4248
3959	Зачет	4249
3960	Курсовой проект	4249
3961	Зачет	4250
3962	Экзамен	4251
3963	Зачет	4252
3964	Экзамен	4253
3965	Экзамен	4254
3966	Экзамен	4255
3967	Зачет	4256
3974	Зачет	3459
3986	Экзамен	4265
3987	Экзамен	4266
3991	Зачет	4267
3998	Экзамен	4268
3999	Экзамен	4269
4001	Зачет	4270
4005	Экзамен	4271
4008	Зачет	4272
4013	Зачет	3454
4019	Зачет	3962
4020	Зачет	3369
4024	Экзамен	4273
4025	Зачет	4274
4029	Зачет	3445
4030	Зачет	3460
4031	Зачет	3443
4032	Зачет	3430
4033	Зачет	3376
4034	Зачет	3728
4035	Зачет	3415
4036	Зачет	3416
4037	Зачет	3417
4038	Зачет	3418
4039	Зачет	3419
4040	Зачет	3420
4041	Зачет	3421
4042	Экзамен	4275
4043	Зачет	4276
4044	Экзамен	3447
4045	Экзамен	4277
4046	Экзамен	4278
4047	Зачет	4279
4048	Зачет	3480
4049	Зачет	4280
4050	Курсовая работа	4280
4052	Экзамен	4281
4053	Экзамен	4282
4054	Экзамен	4283
4055	Зачет	3433
4056	Зачет	3434
4057	Зачет	3435
4058	Зачет	3436
4059	Зачет	3437
4060	Зачет	3438
4061	Экзамен	4284
4062	Экзамен	4285
4063	Экзамен	4286
4064	Экзамен	4287
4065	Экзамен	4288
4066	Экзамен	4289
4067	Зачет	4290
4068	Зачет	4291
4069	Экзамен	4292
4070	Зачет	4293
4071	Зачет	4294
4072	Зачет	4295
4073	Зачет	4296
4074	Экзамен	4297
4075	Экзамен	4298
4076	Экзамен	4299
4077	Дифф. зачет	4300
4078	Дифф. зачет	4301
4079	Дифф. зачет	4302
4080	Дифф. зачет	4303
4081	Экзамен	4304
4082	Экзамен	4305
4083	Экзамен	4306
4084	Зачет	4307
4085	Зачет	4308
4086	Зачет	4309
4087	Экзамен	4310
4088	Экзамен	4311
4089	Зачет	4312
4090	Экзамен	4313
4091	Зачет	4314
4092	Курсовая работа	4314
4093	Зачет	4315
4094	Экзамен	4316
4095	Экзамен	4317
4096	Курсовой проект	4317
4097	Экзамен	4318
4098	Экзамен	4319
4099	Экзамен	4320
4100	Зачет	4321
4101	Зачет	4322
4102	Зачет	4323
4103	Экзамен	4236
4104	Курсовая работа	4236
4105	Зачет	4324
4106	Экзамен	3507
4107	Дифф. зачет	4325
4108	Экзамен	4326
4109	Зачет	4327
4110	Экзамен	4328
4111	Экзамен	4329
4112	Зачет	4330
4113	Курсовой проект	4330
\.
COPY s335141.change_discp_module (id_change, id_discp_module) FROM stdin;
\.
COPY s335141.change_discp_starts (id_change, id_discp_start) FROM stdin;
\.
COPY s335141.change_rpd (id_change, id_rpd) FROM stdin;
\.
COPY s335141.change_section (id_change, id_section) FROM stdin;
\.
COPY s335141.changes (id, type, comment, id_memorandum) FROM stdin;
1023	delete	\N	106
1024	add	\N	106
1025	delete	\N	106
1026	add	\N	106
1027	delete	\N	106
1028	add	\N	106
1029	add	\N	106
1030	delete	\N	106
1031	delete	\N	106
1032	add	\N	106
1033	add	\N	106
1034	delete	\N	106
1035	add	\N	106
1036	delete	\N	106
1037	add	\N	106
1038	delete	\N	106
1039	delete	\N	106
1040	add	\N	106
1041	delete	\N	106
1042	add	\N	106
1043	add	\N	106
1044	add	\N	106
1045	add	\N	106
1046	add	\N	106
1047	delete	\N	106
1048	add	\N	106
1049	add	\N	106
1050	add	\N	106
84	delete	\N	42
85	add	\N	42
86	delete	\N	42
87	delete	\N	43
88	add	\N	43
89	delete	\N	43
90	delete	\N	44
91	add	\N	44
92	delete	\N	44
93	delete	\N	45
94	add	\N	45
95	delete	\N	45
96	delete	\N	46
97	add	\N	46
98	delete	\N	46
99	delete	\N	47
100	add	\N	47
101	delete	\N	47
102	delete	\N	48
103	add	\N	48
104	delete	\N	48
105	delete	\N	49
106	add	\N	49
107	delete	\N	49
108	delete	\N	50
109	add	\N	50
110	delete	\N	50
111	delete	\N	51
112	add	\N	51
113	delete	\N	51
114	delete	\N	52
115	add	\N	52
116	delete	\N	52
117	delete	\N	53
118	add	\N	53
119	delete	\N	53
120	delete	\N	54
121	add	\N	54
122	delete	\N	54
123	delete	\N	55
124	add	\N	55
125	delete	\N	55
126	delete	\N	56
127	add	\N	56
128	delete	\N	56
129	delete	\N	57
130	add	\N	57
131	delete	\N	57
132	delete	\N	58
133	add	\N	58
134	delete	\N	58
135	delete	\N	59
136	add	\N	59
137	delete	\N	59
138	delete	\N	60
139	add	\N	60
140	delete	\N	60
141	delete	\N	61
142	add	\N	61
143	delete	\N	61
144	delete	\N	62
145	add	\N	62
146	delete	\N	62
147	delete	\N	63
148	add	\N	63
149	delete	\N	63
150	delete	\N	64
151	add	\N	64
152	delete	\N	64
153	delete	\N	65
154	add	\N	65
155	delete	\N	65
156	add	\N	65
157	add	\N	65
158	add	\N	65
159	delete	\N	65
160	delete	\N	65
161	add	\N	65
162	delete	\N	66
163	add	\N	66
164	delete	\N	66
165	add	\N	66
166	add	\N	66
167	add	\N	66
168	delete	\N	66
169	delete	\N	66
170	add	\N	66
171	delete	\N	67
172	add	\N	67
173	delete	\N	67
174	add	\N	67
175	add	\N	67
176	add	\N	67
177	delete	\N	67
178	delete	\N	67
179	add	\N	67
180	delete	\N	68
181	add	\N	68
182	delete	\N	68
183	add	\N	68
184	add	\N	68
185	add	\N	68
186	delete	\N	68
187	delete	\N	68
188	add	\N	68
189	delete	\N	69
190	add	\N	69
191	delete	\N	69
192	add	\N	69
193	add	\N	69
194	add	\N	69
195	delete	\N	69
196	delete	\N	69
197	add	\N	69
198	delete	\N	69
199	delete	\N	69
200	add	\N	69
201	add	\N	69
202	delete	\N	69
203	add	\N	69
204	delete	\N	69
205	add	\N	69
206	delete	\N	69
207	add	\N	69
208	delete	\N	69
209	add	\N	69
210	delete	\N	70
211	add	\N	70
212	delete	\N	70
213	add	\N	70
214	add	\N	70
215	add	\N	70
216	delete	\N	70
217	delete	\N	70
218	add	\N	70
219	delete	\N	70
220	delete	\N	70
221	add	\N	70
222	add	\N	70
223	delete	\N	70
224	add	\N	70
225	delete	\N	70
226	add	\N	70
227	delete	\N	70
228	add	\N	70
229	delete	\N	70
230	add	\N	70
231	delete	\N	71
232	add	\N	71
233	delete	\N	71
234	add	\N	71
235	add	\N	71
236	add	\N	71
237	delete	\N	71
238	delete	\N	71
239	add	\N	71
240	delete	\N	71
241	delete	\N	71
242	add	\N	71
243	add	\N	71
244	delete	\N	71
245	add	\N	71
246	delete	\N	71
247	add	\N	71
248	delete	\N	71
249	add	\N	71
250	delete	\N	71
251	add	\N	71
252	delete	\N	72
253	add	\N	72
254	delete	\N	72
255	add	\N	72
256	add	\N	72
257	add	\N	72
258	delete	\N	72
259	delete	\N	72
260	add	\N	72
261	delete	\N	72
262	delete	\N	72
263	add	\N	72
264	add	\N	72
265	delete	\N	72
266	add	\N	72
267	delete	\N	72
268	add	\N	72
269	delete	\N	72
270	add	\N	72
271	delete	\N	72
272	add	\N	72
273	delete	\N	73
274	add	\N	73
275	delete	\N	73
276	add	\N	73
277	add	\N	73
278	add	\N	73
279	delete	\N	73
280	delete	\N	73
281	add	\N	73
282	delete	\N	73
283	delete	\N	73
284	add	\N	73
285	add	\N	73
286	delete	\N	73
287	add	\N	73
288	delete	\N	73
289	add	\N	73
290	delete	\N	73
291	add	\N	73
292	delete	\N	73
293	add	\N	73
294	delete	\N	74
295	add	\N	74
296	delete	\N	74
297	add	\N	74
298	add	\N	74
299	add	\N	74
300	delete	\N	74
301	delete	\N	74
302	add	\N	74
303	delete	\N	74
304	delete	\N	74
305	add	\N	74
306	add	\N	74
307	delete	\N	74
308	add	\N	74
309	delete	\N	74
310	add	\N	74
311	delete	\N	74
312	add	\N	74
313	delete	\N	74
314	add	\N	74
315	delete	\N	75
316	add	\N	75
317	delete	\N	75
318	add	\N	75
319	add	\N	75
320	add	\N	75
321	delete	\N	75
322	delete	\N	75
323	add	\N	75
324	delete	\N	75
325	delete	\N	75
326	add	\N	75
327	add	\N	75
328	delete	\N	75
329	add	\N	75
330	delete	\N	75
331	add	\N	75
332	delete	\N	75
333	add	\N	75
334	delete	\N	75
335	add	\N	75
336	delete	\N	76
337	add	\N	76
338	delete	\N	76
339	add	\N	76
340	add	\N	76
341	add	\N	76
342	delete	\N	76
343	delete	\N	76
344	add	\N	76
345	delete	\N	76
346	delete	\N	76
347	add	\N	76
348	add	\N	76
349	delete	\N	76
350	add	\N	76
351	delete	\N	76
352	add	\N	76
353	delete	\N	76
354	add	\N	76
355	delete	\N	76
356	add	\N	76
357	delete	\N	77
358	add	\N	77
359	delete	\N	77
360	add	\N	77
361	add	\N	77
362	add	\N	77
363	delete	\N	77
364	delete	\N	77
365	add	\N	77
366	delete	\N	77
367	delete	\N	77
368	add	\N	77
369	add	\N	77
370	delete	\N	77
371	add	\N	77
372	delete	\N	77
373	add	\N	77
374	delete	\N	77
375	add	\N	77
376	delete	\N	77
377	add	\N	77
378	delete	\N	78
379	add	\N	78
380	delete	\N	78
381	add	\N	78
382	add	\N	78
383	add	\N	78
384	delete	\N	78
385	delete	\N	78
386	add	\N	78
387	delete	\N	78
388	delete	\N	78
389	add	\N	78
390	add	\N	78
391	delete	\N	78
392	add	\N	78
393	delete	\N	78
394	add	\N	78
395	delete	\N	78
396	add	\N	78
397	delete	\N	78
398	add	\N	78
399	delete	\N	79
400	add	\N	79
401	delete	\N	79
402	add	\N	79
403	add	\N	79
404	add	\N	79
405	delete	\N	79
406	delete	\N	79
407	add	\N	79
408	delete	\N	79
409	delete	\N	79
410	add	\N	79
411	add	\N	79
412	delete	\N	79
413	add	\N	79
414	delete	\N	79
415	add	\N	79
416	delete	\N	79
417	add	\N	79
418	delete	\N	79
419	add	\N	79
420	delete	\N	80
421	add	\N	80
422	delete	\N	80
423	add	\N	80
424	add	\N	80
425	add	\N	80
426	delete	\N	80
427	delete	\N	80
428	add	\N	80
429	delete	\N	80
430	delete	\N	80
431	add	\N	80
432	add	\N	80
433	delete	\N	80
434	add	\N	80
435	delete	\N	80
436	add	\N	80
437	delete	\N	80
438	add	\N	80
439	delete	\N	80
440	add	\N	80
441	delete	\N	81
442	add	\N	81
443	delete	\N	81
444	add	\N	81
445	add	\N	81
446	add	\N	81
447	delete	\N	81
448	delete	\N	81
449	add	\N	81
450	delete	\N	81
451	delete	\N	81
452	add	\N	81
453	add	\N	81
454	delete	\N	81
455	add	\N	81
456	delete	\N	81
457	add	\N	81
458	delete	\N	81
459	add	\N	81
460	delete	\N	81
461	add	\N	81
462	delete	\N	82
463	add	\N	82
464	delete	\N	82
465	add	\N	82
466	add	\N	82
467	add	\N	82
468	delete	\N	82
469	delete	\N	82
470	add	\N	82
471	delete	\N	82
472	delete	\N	82
473	add	\N	82
474	add	\N	82
475	delete	\N	82
476	add	\N	82
477	delete	\N	82
478	add	\N	82
479	delete	\N	82
480	add	\N	82
481	delete	\N	82
482	add	\N	82
483	delete	\N	83
484	add	\N	83
485	delete	\N	83
486	add	\N	83
487	add	\N	83
488	add	\N	83
489	delete	\N	83
490	delete	\N	83
491	add	\N	83
492	delete	\N	83
493	delete	\N	83
494	add	\N	83
495	add	\N	83
496	delete	\N	83
497	add	\N	83
498	delete	\N	83
499	add	\N	83
500	delete	\N	83
501	add	\N	83
502	delete	\N	83
503	add	\N	83
504	delete	\N	84
505	add	\N	84
506	delete	\N	84
507	add	\N	84
508	add	\N	84
509	add	\N	84
510	delete	\N	84
511	delete	\N	84
512	add	\N	84
513	delete	\N	84
514	delete	\N	84
515	add	\N	84
516	add	\N	84
517	delete	\N	84
518	add	\N	84
519	delete	\N	84
520	add	\N	84
521	delete	\N	84
522	add	\N	84
523	delete	\N	84
524	add	\N	84
525	delete	\N	85
526	add	\N	85
527	delete	\N	85
528	add	\N	85
529	add	\N	85
530	add	\N	85
531	delete	\N	85
532	delete	\N	85
533	add	\N	85
534	delete	\N	85
535	delete	\N	85
536	add	\N	85
537	add	\N	85
538	delete	\N	85
539	add	\N	85
540	delete	\N	85
541	add	\N	85
542	delete	\N	85
543	add	\N	85
544	delete	\N	85
545	add	\N	85
546	delete	\N	86
547	add	\N	86
548	delete	\N	86
549	add	\N	86
550	add	\N	86
551	add	\N	86
552	delete	\N	86
553	delete	\N	86
554	add	\N	86
555	delete	\N	86
556	delete	\N	86
557	add	\N	86
558	add	\N	86
559	delete	\N	86
560	add	\N	86
561	delete	\N	86
562	add	\N	86
563	delete	\N	86
564	add	\N	86
565	delete	\N	86
566	add	\N	86
567	delete	\N	87
568	add	\N	87
569	delete	\N	87
570	add	\N	87
571	add	\N	87
572	add	\N	87
573	delete	\N	87
574	delete	\N	87
575	add	\N	87
576	delete	\N	87
577	delete	\N	87
578	add	\N	87
579	add	\N	87
580	delete	\N	87
581	add	\N	87
582	delete	\N	87
583	add	\N	87
584	delete	\N	87
585	add	\N	87
586	delete	\N	87
587	add	\N	87
588	delete	\N	88
589	add	\N	88
590	delete	\N	88
591	add	\N	88
592	add	\N	88
593	add	\N	88
594	delete	\N	88
595	delete	\N	88
596	add	\N	88
597	delete	\N	88
598	delete	\N	88
599	add	\N	88
600	add	\N	88
601	delete	\N	88
602	add	\N	88
603	delete	\N	88
604	add	\N	88
605	delete	\N	88
606	add	\N	88
607	delete	\N	88
608	add	\N	88
609	delete	\N	89
610	add	\N	89
611	delete	\N	89
612	add	\N	89
613	add	\N	89
614	add	\N	89
615	delete	\N	89
616	delete	\N	89
617	add	\N	89
618	delete	\N	89
619	delete	\N	89
620	add	\N	89
621	add	\N	89
622	delete	\N	89
623	add	\N	89
624	delete	\N	89
625	add	\N	89
626	delete	\N	89
627	add	\N	89
628	delete	\N	89
629	add	\N	89
630	delete	\N	90
631	add	\N	90
632	delete	\N	90
633	add	\N	90
634	add	\N	90
635	add	\N	90
636	delete	\N	90
637	delete	\N	90
638	add	\N	90
639	delete	\N	90
640	add	\N	90
641	delete	\N	90
642	add	\N	90
643	delete	\N	90
644	add	\N	90
645	delete	\N	90
646	add	\N	90
647	delete	\N	90
648	add	\N	90
649	add	\N	90
650	delete	\N	91
651	add	\N	91
652	delete	\N	91
653	add	\N	91
654	add	\N	91
655	add	\N	91
656	delete	\N	91
657	delete	\N	91
658	add	\N	91
659	delete	\N	91
660	add	\N	91
661	delete	\N	91
662	add	\N	91
663	delete	\N	91
664	add	\N	91
665	delete	\N	91
666	add	\N	91
667	delete	\N	91
668	add	\N	91
669	add	\N	91
670	delete	\N	92
671	add	\N	92
672	delete	\N	92
673	add	\N	92
674	add	\N	92
675	add	\N	92
676	delete	\N	92
677	delete	\N	92
678	add	\N	92
679	delete	\N	92
680	add	\N	92
681	delete	\N	92
682	add	\N	92
683	delete	\N	92
684	add	\N	92
685	delete	\N	92
686	add	\N	92
687	delete	\N	92
688	add	\N	92
689	add	\N	92
690	delete	\N	93
691	add	\N	93
692	delete	\N	93
693	add	\N	93
694	add	\N	93
695	add	\N	93
696	delete	\N	93
697	delete	\N	93
698	add	\N	93
699	delete	\N	93
700	add	\N	93
701	delete	\N	93
702	add	\N	93
703	delete	\N	93
704	add	\N	93
705	delete	\N	93
706	add	\N	93
707	delete	\N	93
708	add	\N	93
709	add	\N	93
710	delete	\N	94
711	add	\N	94
712	delete	\N	94
713	add	\N	94
714	add	\N	94
715	add	\N	94
716	delete	\N	94
717	delete	\N	94
718	add	\N	94
719	delete	\N	94
720	add	\N	94
721	delete	\N	94
722	add	\N	94
723	delete	\N	94
724	add	\N	94
725	delete	\N	94
726	add	\N	94
727	delete	\N	94
728	add	\N	94
729	add	\N	94
730	delete	\N	95
731	add	\N	95
732	delete	\N	95
733	add	\N	95
734	add	\N	95
735	add	\N	95
736	delete	\N	95
737	delete	\N	95
738	add	\N	95
739	delete	\N	95
740	add	\N	95
741	delete	\N	95
742	add	\N	95
743	delete	\N	95
744	add	\N	95
745	delete	\N	95
746	add	\N	95
747	delete	\N	95
748	add	\N	95
749	add	\N	95
750	delete	\N	96
751	add	\N	96
752	delete	\N	96
753	add	\N	96
754	add	\N	96
755	add	\N	96
756	delete	\N	96
757	delete	\N	96
758	add	\N	96
759	delete	\N	96
760	delete	\N	96
761	add	\N	96
762	add	\N	96
763	delete	\N	96
764	add	\N	96
765	delete	\N	96
766	add	\N	96
767	delete	\N	96
768	add	\N	96
769	delete	\N	96
770	add	\N	96
1211	delete	\N	122
1212	add	\N	122
1213	delete	\N	122
1214	add	\N	122
1215	delete	\N	122
1216	add	\N	122
1217	add	\N	122
1218	delete	\N	122
1219	delete	\N	122
1220	add	\N	122
1221	add	\N	122
1222	delete	\N	122
1223	add	\N	122
1224	delete	\N	122
1225	add	\N	122
1226	delete	\N	122
1227	delete	\N	122
1228	add	\N	122
1229	delete	\N	122
1230	add	\N	122
1231	add	\N	122
1232	add	\N	122
1233	add	\N	122
1234	add	\N	122
1235	delete	\N	122
1236	add	\N	122
1237	add	\N	122
1238	add	\N	122
\.
COPY s335141.curricula (id_isu, name, year, degree, head, status) FROM stdin;
-1110	(старый КТвД)	22	bachelor	Смолин Артем Александрович	f
-1618	(старый КТвД)	23	bachelor	Смолин Артем Александрович	f
-103344	(старый КТвД)	24	bachelor	Смолин Артем Александрович	f
-3344	(старый МТДиЮ)	25	master	Смолин Артем Александрович	f
112	КТвД (до СЗ)	23	bachelor	Смолин Артем Александрович	f
111	КТвД (до СЗ)	24	bachelor	Смолин Артем Александрович	f
10075	КТвД (до СЗ)	25	bachelor	Смолин Артем Александрович	f
18367	Компьютерные технологии в дизайне	2023	bachelor	Смолин Артем Александрович	t
200091	Компьютерные технологии в дизайне	2025	bachelor	Смолин Артем Александрович	t
42357	Компьютерные технологии в дизайне	2024	bachelor	Смолин Артем Александрович	t
200034	Мультимедиа-технологии, дизайн и юзабилити	2025	master	Смолин Артем Александрович	t
113	Компьютерные технологии в дизайне	2022	bachelor	Смолин Артем Александрович	t
3343	Мультимедиа-технологии, дизайн и юзабилити	2024	master	Смолин Артем Александрович	t
-10323	КТвД 26 (старый)	26	bachelor	Смолин Артем Александрович	t
-123	Компьюте удалить	26	bachelor	Смолин Артем Александрович	f
10323	Компьютерные технологии в дизайне	2026	bachelor	Смолин Артем Александрович	t
10322	Мультимедиа-технологии, дизайн и юзабилити	2026	master	Смолин Артем Александрович	t
-10322	СТАРОЕ убрать Мультимедиа-технологии, дизайн и юзабилити	26	master	Смолин Артем Александрович	f
\.
COPY s335141.disciplines (id, name, comment) FROM stdin;
6098	Количественные методы в экспериментальных исследованиях (1ый семестр)	\N
6150	Инженерная графика	\N
6154	Тестирование пользовательских интерфейсов	\N
6158	Основы работы с VFX	\N
6162	Основы работы с 3D-анимацией	\N
6166	Стандарты в мультимедиа-технологиях	\N
6170	История западноевропейской и русской культуры	\N
6119	История	\N
6171	Наука и техника в истории цивилизации	\N
6172	Проблемы истории Европы ХХ века	\N
6124	Стартапы	\N
6126	Практики	\N
6130	Проекционная геометрия	\N
6132	Математическая статистика	\N
6134	История искусств	\N
6136	Архитектурное проектирование	\N
6138	Разработка приложений виртуальной реальности	\N
6140	Полигональное моделирование	\N
6142	Функциональное программирование	\N
6144	Моделирование 3D-персонажей	\N
6173	Реформы и реформаторы в истории России	\N
6174	История становления Российской государственности	\N
6175	ITMOEnter	\N
6315	Математический анализ (продвинутый уровень)	\N
6348	Основы концептуального мышления	\N
6349	История и теория дизайна	\N
6350	Анимация трёхмерных персонажей	\N
6351	Трёхмерное моделирование компьютерных персонажей	\N
6196	Математический анализ (базовый уровень)	\N
6197	Педагогический дизайн	\N
6198	Разработка и анимация 3D-персонажей	\N
6199	Дизайн интерактивных приложений	\N
6200	Физика (базовый курс)	\N
6201	Системы верстки	\N
6202	Производственная, проектная практика	\N
6203	Преддипломная практика	\N
6204	Государственная итоговая аттестация	\N
6205	Общеуниверситетские факультативы (осень 2024)	\N
6206	Линейная алгебра (продвинутый уровень)	\N
6207	Психология социальной адаптации и психосаморегуляция	\N
6208	Общеуниверситетские факультативы	\N
6352	Дизайн интерактивных медиа	\N
6128	Физическая культура и спорт	\N
6383	Хранение и обработка данных	\N
6230	Машинное обучение	\N
6400	Инструментальные возможности ИИ	\N
6389	Генеративные технологии в дизайне	\N
6390	Анимация 3D-персонажей	\N
6391	Креативное макетирование интерфейсов	\N
6392	Инструменты ИИ в проектной деятельности\n	\N
6393	Теория вероятностей для UX-исследований	\N
6394	Микросервисная архитектура веб-приложений\n	\N
6397	Продуктовая логика для R&D	\N
6398	Проектный менеджмент: методологии и стандарты	\N
6399	Рыночные вызовы: реализация трансфера технологий	\N
6401	Данные как основа ИИ	\N
6402	Классические методы МО и основы нейронных сетей	\N
6403	Архитектуры современного ИИ и человек	\N
6404	ИИ как образ жизни: Агентные системы	\N
6405	ИИ как образ жизни: Агентные системы и компьютерное зрение	\N
6406	ИИ как образ жизни: Агентные системы и обработка естественного языка	\N
6407	Основы программирования	\N
6408	Основы компьютерной графики	\N
6409	Веб-разработка	\N
6410	Дополнительные разделы высшей математики\n	\N
6411	Основы графики	\N
6227	Производственная практика, проектная	\N
6155	Дизайн фирменного стиля	\N
6163	Общая психология	\N
5893	Безопасность жизнедеятельности	\N
6209	Россия в истории современных международных отношений	\N
6210	История России и мира в ХХ веке	\N
6211	Социальная история России	\N
6212	История российской науки и техники	\N
6213	История русской культуры в контексте мировой культуры	\N
6216	Автоматическая обработка текстов	\N
6217	Физика	\N
5909	Бизнес-модели основных секторов инновационной экономики	\N
5910	Коммуникации и командообразование	\N
5911	Техники публичных выступлений и презентаций	\N
5912	Защита и действия человека в условиях ЧС	\N
5913	Введение в специальность	\N
5914	Пропедевтика дизайна	\N
5915	История дизайна	\N
5916	Языки программирования (С#)	\N
5917	Программирование	\N
5918	Дискретная математика	\N
5919	Фотографические технологии	\N
5920	Типографика	\N
5921	Компьютерные сети	\N
5922	Информатика	\N
5923	Алгоритмы и структуры данных	\N
5924	Информационная безопасность	\N
5925	Аналитическая геометрия	\N
5926	Математический анализ	\N
5927	Теория массового обслуживания	\N
5928	Автоматическая обработка текста	\N
5929	Анализ социальных сетей	\N
5930	Обработка изображений	\N
5931	Методы искусственного интеллекта	\N
5932	Компьютерное зрение	\N
5933	Интернет вещей	\N
5934	Пластическая анатомия человека	\N
5935	Живопись и цветоведение	\N
5937	Основы композиции	\N
6218	Производственная, преддипломная практика	\N
5946	Дизайн структуры и освещения уровней	\N
5947	3D-моделирование объектов техники	\N
5949	3D-моделирование объектов окружения	\N
6316	Стартап-трек: энергетика	\N
6317	Стартап-трек: креативные технологии	\N
6318	Стартап-трек: IT и роботы	\N
6319	Стартап-трек: рынок AI	\N
6320	Стартап-трек: рынок Life Science	\N
5955	Проектирование интерактивных приложений	\N
5956	Интерактивные приложения в Unreal Engine	\N
6321	Стартап-трек: общий вектор	\N
6322	Рыночные вызовы: разработка бизнес-решений	\N
6323	Прототипирование и создание mvp	\N
6324	Лаборатория брендинга	\N
6325	Финансы проекта и организации	\N
6326	Введение в технологическое предпринимательство	\N
6327	Прикладная алгебра	\N
6328	Методы математического анализа	\N
6329	Генеративные технологии в цифровом дизайне	\N
6330	Информационные и компьютерные технологии	\N
6331	Академический рисунок	\N
6332	Объектно-ориентированное программирование (базовый уровень)	\N
5969	Проектирование и разработка 3D-персонажей	\N
5970	Анимация и захват движения	\N
6333	Моделирование физических процессов	\N
6334	3D-визуализация	\N
6335	Иллюстрация в коммуникационном дизайне	\N
5974	Архитектурная визуализация	\N
5975	Промышленный дизайн и эргономика	\N
6148	Дизайн объектов окружения	\N
6152	Проектная документация	\N
6156	Основы рисунка	\N
6160	Инженерная психология	\N
6164	Системы вёрстки	\N
6168	Пластическая анатомия животных	\N
6219	Языки программирования С#	\N
6336	Стилистика в коммуникационном дизайне	\N
6337	Инструменты ИИ в проектной деятельности	\N
5989	Основы проектирования дизайн-систем	\N
5990	Веб-проектирование	\N
5991	Motion-дизайн	\N
6220	Линейная алгебра	\N
6221	Методы криптографии	\N
6338	Микросервисная архитектура веб-приложений	\N
6228	Производственная практика, преддипломная	\N
6222	Компьютерная визуализация	\N
6223	Инструменты разработки пользовательского интерфейса	\N
6000	Веб-аналитика	\N
6224	Компьютерная алгебра	\N
6225	Дополнительные главы высшей математики	\N
6226	Теория функций комплексного переменного	\N
6008	Веб-технологии	\N
6013	Разработка графических веб-приложений	\N
6014	Методы оптимизации	\N
6015	Системы компьютерной обработки изображений	\N
6016	Методы обработки изображений	\N
6017	Представление данных	\N
6018	Основы программной инженерии	\N
6235	Элективные микромодули Soft Skills	\N
6236	Эмоциональный интеллект / Emotional Intelligence	\N
6237	Навыки критического мышления (продвинутый уровень) / Critical Thinking Skills (advanced)	\N
6025	Операционные системы	\N
6026	Системы искусственного интеллекта	\N
6027	Архитектура компьютера	\N
6238	Проектный менеджмент	\N
6029	Специальные разделы высшей математики	\N
6030	Дополнительные главы математического анализа	\N
6239	Креативные индустрии и инновационные технологии	\N
6240	Научное письмо на английском языке / Scientific writing	\N
6241	Навыки презентации на английском языке / Presentation skills	\N
6242	Хранение больших данных и Элементы статистики	\N
6036	Биометрия и нейротехнологии	\N
6243	Введение в МО (инструменты) и Методы ПИИ	\N
6244	Философия и научная методология в дизайне\n	\N
6245	Количественные методы в экспериментальных исследованиях	\N
6246	Качественные методы исследований\n	\N
6247	Проектирование доступных интерфейсов для пользователей с особыми потребностями	\N
6045	Тестирование программного обеспечения	\N
6046	Разработка мобильных приложений	\N
6048	Теория развития и обучения	\N
6049	Методика проектной работы	\N
6050	Проектирование и разработка компьютерных средств обучения	\N
6051	Инструменты компьютерного дизайна	\N
6248	Стилистика и визуальные образы в компьютерных средах	\N
6249	Психология человеко-компьютерного взаимодействия	\N
6250	Графический дизайн пользовательских интерфейсов	\N
6251	Техническая реализация дизайн-системы	\N
6252	Перспективные человеко-машинные интерфейсы	\N
6253	Моделирование и визуализация реалистичных 3D-ассетов	\N
6254	Технологии виртуальной реконструкции архитектурного наследия	\N
6255	Дизайн виртуальных интерьеров\n	\N
6256	Технологии захвата движений	\N
6257	Информационные технологии в современной визуальной культуре	\N
6258	Виртуальная, дополненная и смешанная реальность	\N
6259	Трёхмерное моделирование и анимация компьютерных персонажей	\N
6260	Научно-исследовательская работа	\N
6060	Визуализация учебной информации в игропедагогике	\N
6061	Методика профессионального обучения	\N
6062	Проектирование и дизайн web-сайтов	\N
6063	Трёхмерное моделирование и анимация	\N
6064	Виртуальные среды в образовании	\N
6065	Игровые технологии в образовании	\N
6066	Основы компьютерной анимации и иллюстративной графики	\N
6307	Разработка клиентской части веб-приложений	\N
6308	Разработка серверной части веб-приложений	\N
6149	Hardsurface-моделирование	\N
6309	Вычислительная математика и методы оптимизации	\N
6310	Анимация для интерфейсов	\N
6153	Дизайн визуальных эффектов	\N
6311	Скетчинг	\N
6074	Проектирование и реализация баз данных	\N
6075	Технологии программирования	\N
6076	Программное и аппаратное обеспечение компьютера и робототехника	\N
6077	Экспертные системы в образовании	\N
6078	Проектирование и разработка веб-сайтов	\N
6079	Нейронные сети в образовании	\N
6080	UI/UX для образовательных систем	\N
6157	Визуализация данных	\N
6312	Проектирование игрового опыта	\N
6165	Вычислительная математика	\N
6313	Нарративный дизайн	\N
6314	Технологии анимации и искусственный интеллект	\N
6339	Объектно-ориентированное программирование (продвинутый уровень)	\N
6090	Подготовка к защите и защита ВКР	\N
6340	Специальные разделы математического анализа	\N
6092	Качественные методы исследований	\N
6093	Проектирование и прототипирование пользовательских интерфейсов	\N
6094	Front-end для UI-дизайнеров	\N
6095	Анализ и оценка пользовательского опыта	\N
6096	Методы разработки 3D-моделей	\N
6097	Технологии моделирования и визуализации реалистичных 3D-моделей	\N
6341	Компьютерная геометрия	\N
6342	Развивающие виртуальные среды	\N
6343	Креативная анимация	\N
6344	Профессиональное развитие в области компьютерной графики 	\N
6345	Проектирование и разработка развивающих приложений	\N
6346	Дизайн и разработка развивающих игр	\N
6347	Теория развития	\N
6414	Создание и развитие технологического бизнеса	\N
6125	Философия	\N
6127	физика	\N
6131	Основы компьютерной 2D-анимации	\N
6133	Алгоритмы компьютерной графики	\N
6135	Теория вероятностей	\N
6137	Визуальная культура и визуальное восприятие	\N
6139	Введение в работу с игровыми движками	\N
6141	Твердотельное моделирование и 3D-печать	\N
6143	Дизайн окружения	\N
6145	Полиграфический дизайн	\N
6415	Scientific writing / Научное письмо на английском языке	\N
6382	Прикладная статистика	\N
6129	Иностранный язык	\N
6386	Предпринимательская культура	\N
6169	Базы данных для игровых приложений	test
6388	Разработка интерактивных приложений	\N
6395	Культура ИИ: Медиа и креативность	\N
6396	ИИ-мышление: Наука, технологии, агентность	\N
6412	Личная эффективность и управление временем	\N
6413	Критическое мышление (продвинутый уровень)	\N
\.
COPY s335141.disciplines_in_modules (id, implementer, "position", id_rpd, id_module, changable) FROM stdin;
8911	ЦСиГН	1	3951	-102	f
8912	ЦСиГН	2	33953	-102	f
8913	ЦСиГН	3	33954	-102	f
8914	ЦСиГН	4	33955	-102	f
8915	ЦСиГН	5	33956	-102	f
8916	ЦСиГН	6	33957	-102	f
8917	БЖД	1	5895	-103	f
8918	УФКС ССККБ	1	16560	-105	f
8919	УФКС ССККБ	1	16559	-106	f
8920	F	1	30498	-107	f
21741	ЦСиГН	1	35553	17470	f
21742	БЖД	1	5895	17468	f
21743	ОтдПВ	2	30184	17468	f
21744	ССККБ	1	16560	17446	f
21745	ССККБ	2	16559	17446	f
21746	F	1	35862	17466	f
21747	ЦИИЯ	1	36574	17455	f
21748	ЦИИЯ	2	36573	17455	f
21749	ЦИИЯ	3	36572	17455	f
21750	ЦИИЯ	4	36571	17455	f
21751	ЦИИЯ	5	36568	17455	f
21752	ЦИИЯ	6	36567	17455	f
8933	Пр Кул	1	30183	-109	f
8934	SS	1	9326	-110	f
8935	SS	2	21052	-110	f
8936	Реализатор	1	30184	-111	f
21753	ЦИИЯ	7	36566	17455	f
21754	ЦИИЯ	1	36642	17457	f
21755	ЦИИЯ	2	36641	17457	f
21756	ЦИИЯ	3	36640	17457	f
21757	ЦИИЯ	4	36639	17457	f
21758	ЦИИЯ	5	36575	17457	f
21759	ЦИИЯ	6	36574	17457	f
21760	ЦИИЯ	7	36573	17457	f
21761	ЦИИЯ	8	36572	17457	f
21762	ЦИИЯ	9	36571	17457	f
21763	ЦИИЯ	10	36570	17457	f
21764	ЦИИЯ	11	36569	17457	f
21765	ЦИИЯ	12	36568	17457	f
21766	ЦИИЯ	13	36567	17457	f
21302	ФТМИ	1	16544	5091	f
21303	ФТМИ	2	16543	5091	f
21304	ФТМИ	3	16542	5091	f
21305	ФТМИ	4	16540	5091	f
21306	ФТМИ	5	16539	5091	f
21307	БЖД	1	5895	5092	f
21308	БЖД	2	16550	5092	f
21309	ССККБ	1	16559	5093	f
21310	ССККБ	2	16560	5093	f
21311	F	1	16568	5094	f
21312	ЦИИЯ	1	29867	50434	f
21313	ЦИИЯ	1	29867	50435	f
21314	ЦИИЯ	1	29867	50436	f
21315	ЦИИЯ	1	29867	50437	f
21767	ЦИИЯ	14	36566	17457	f
21768	ЦИИЯ	1	36646	17461	f
21769	ЦИИЯ	2	36645	17461	f
21770	ЦИИЯ	3	36644	17461	f
21771	ЦИИЯ	4	36643	17461	f
21772	ЦИИЯ	5	36642	17461	f
21773	ЦИИЯ	6	36641	17461	f
21774	ЦИИЯ	7	36640	17461	f
21775	ЦИИЯ	8	36639	17461	f
21776	ЦИИЯ	9	36575	17461	f
21777	ЦИИЯ	10	36574	17461	f
21778	ЦИИЯ	11	36573	17461	f
21779	ЦИИЯ	12	36572	17461	f
21780	ЦИИЯ	13	36571	17461	f
21781	ЦИИЯ	14	36570	17461	f
21782	ЦИИЯ	15	36569	17461	f
21783	ЦИИЯ	16	36568	17461	f
21784	ЦИИЯ	17	36567	17461	f
21785	ЦИИЯ	18	36566	17461	f
21786	Пр Кул	1	33341	17451	f
21787	Пр Кул	2	31283	17451	f
21788	Пр Кул	3	30182	17451	f
21789	Пр Кул	4	30181	17451	f
21790	Пр Кул	5	30178	17451	f
21791	Пр Кул	6	30177	17451	f
21792	Пр Кул	7	2263	17451	f
21793	Пр Кул	1	51290	17450	f
21794	SS	1	35368	17464	f
21795	SS	2	35861	17464	f
21796	ФПИ и КТ	1	36196	17478	f
21797	ФПИ и КТ	2	18040	17478	f
21798	ФПИ и КТ	1	53682	17479	f
21799	ФПИ и КТ	2	36202	17479	f
21800	ФПИ и КТ	3	36201	17479	f
21801	ФПИ и КТ	4	36197	17479	f
21802	ФПИ и КТ	5	36199	17479	f
21803	ФПИ и КТ	6	36200	17479	f
21804	ФПИ и КТ	7	7799	17479	f
21805	ФПИ и КТ	8	36198	17479	f
21806	НОЦМ	1	37118	17475	f
21807	НОЦМ	2	35844	17475	f
21808	НОЦМ	3	35845	17475	f
21809	ВШ ЦК	1	21137	17477	f
21810	ВШ ЦК	2	21013	17477	f
21811	ВШ ЦК	3	19905	17477	f
21812	ВШ ЦК	4	19903	17477	f
21813	ВШ ЦК	5	19843	17477	f
21814	ВШ ЦК	6	19747	17477	f
21815	ВШ ЦК	7	19745	17477	f
21816	ВШ ЦК	8	19743	17477	f
21817	ВШ ЦК	9	19742	17477	f
21818	ФПИ и КТ	1	18042	17489	f
21819	ФПИ и КТ	2	36210	17489	f
21820	ФПИ и КТ	3	36211	17489	f
21821	ФПИ и КТ	1	36209	17488	f
21822	ФПИ и КТ	2	36206	17488	f
21823	ФПИ и КТ	3	36207	17488	f
21824	ФПИ и КТ	4	36208	17488	f
21825	ФПИ и КТ	1	36203	17487	f
21826	ФПИ и КТ	2	36204	17487	f
21827	ФПИ и КТ	3	36205	17487	f
21828	ФПИ и КТ	1	36212	17490	f
21829	ФПИ и КТ	2	36213	17490	f
21830	ВШ ЦК	1	16579	17484	f
21831	ВШ ЦК	2	16580	17484	f
21832	ВШ ЦК	1	16581	17486	f
21833	ВШ ЦК	2	16582	17486	f
21834	ВШ ЦК	1	16583	17485	f
21835	ВШ ЦК	2	16584	17485	f
21836	ФПИ и КТ	1	53683	17493	f
21837	ФПИ и КТ	2	36220	17493	f
21838	ФПИ и КТ	3	36219	17493	f
21839	ФПИ и КТ	4	36218	17493	f
21840	ФПИ и КТ	5	36217	17493	f
21841	ФПИ и КТ	6	36216	17493	f
21842	ФПИ и КТ	7	58000	17493	f
21843	ФПИ и КТ	8	36214	17493	f
21844	ФПИ и КТ	9	34378	17493	f
21845	ФПИ и КТ	10	57874	17493	f
21846	ФПИ и КТ	11	57875	17493	f
21847	ФПИ и КТ	12	18053	17493	f
21848	ФПИ и КТ	13	18032	17493	f
21849	ФПИ и КТ	14	2243	17493	f
21850	ФПИ и КТ	1	53684	17497	f
21851	ФПИ и КТ	2	53678	17497	f
21852	ФПИ и КТ	3	36224	17497	f
21853	ФПИ и КТ	4	36223	17497	f
21854	ФПИ и КТ	5	31765	17497	f
21855	ФПИ и КТ	1	36228	17498	t
21856	ФПИ и КТ	2	36227	17498	t
21857	ФПИ и КТ	3	36225	17498	t
21858	ФПИ и КТ	4	31762	17498	t
21859	ФПИ и КТ	5	18062	17498	t
21860	ФПИ и КТ	6	18061	17498	t
21861	ФПИ и КТ	7	7068	17498	t
21862	ФПИ и КТ	8	826	17498	t
21863	ФПИ и КТ	1	31766	17496	f
21864	ФПИ и КТ	2	36222	17496	f
21865	ФПИ и КТ	3	36221	17496	f
21866	ФПИ и КТ	1	36229	17501	f
21867	ФПИ и КТ	2	36230	17501	f
21868	ФПИ и КТ	3	18061	17501	f
21869	ФПИ и КТ	4	18072	17501	f
21870	ФПИ и КТ	5	18062	17501	f
21871	ФПИ и КТ	1	36227	17502	t
21872	ФПИ и КТ	2	36225	17502	t
21873	ФПИ и КТ	3	31765	17502	t
21874	ФПИ и КТ	4	31762	17502	t
21875	ФПИ и КТ	5	7068	17502	t
21876	ФПИ и КТ	1	31766	17500	f
21877	ФПИ и КТ	2	36222	17500	f
21878	ФПИ и КТ	1	57879	17505	f
21879	ФПИ и КТ	2	57877	17505	f
21880	ФПИ и КТ	3	53686	17505	f
21881	ФПИ и КТ	4	53685	17505	f
21882	ФПИ и КТ	5	37120	17505	f
21883	ФПИ и КТ	6	52375	17505	f
21884	ФПИ и КТ	7	52376	17505	f
21885	ФПИ и КТ	8	36228	17505	f
21886	ФПИ и КТ	9	36227	17505	f
21887	ФПИ и КТ	10	36225	17505	f
21888	ФПИ и КТ	11	36219	17505	f
21889	ФПИ и КТ	12	38205	17505	f
21890	ФПИ и КТ	13	31763	17505	f
21891	ФПИ и КТ	14	31762	17505	f
21892	ФПИ и КТ	15	18078	17505	f
21893	ИМ	1	58143	17504	f
21894	ФПИ и КТ	1	36217	17506	t
21895	ФПИ и КТ	2	36216	17506	t
21896	ФПИ и КТ	3	18079	17506	t
21897	ФПИ и КТ	4	18053	17506	t
21898	ФПИ и КТ	5	18032	17506	t
21899	ФПИ и КТ	6	7068	17506	t
21900	ФПИ и КТ	1	57877	17512	f
21901	ФПИ и КТ	2	53707	17512	f
21902	ФПИ и КТ	3	53687	17512	f
21903	ФПИ и КТ	4	53680	17512	f
21904	ФПИ и КТ	5	53679	17512	f
21905	ФПИ и КТ	6	53681	17512	f
21906	ФПИ и КТ	7	53677	17512	f
21907	ФПИ и КТ	8	37122	17512	f
21908	ФПИ и КТ	9	38324	17512	f
21909	ФПИ и КТ	10	36237	17512	f
21910	ФПИ и КТ	11	36234	17512	f
21911	ФПИ и КТ	12	36228	17512	f
21912	ФПИ и КТ	13	36227	17512	f
21913	ФПИ и КТ	14	36219	17512	f
21914	ФПИ и КТ	15	36217	17512	f
21915	ФПИ и КТ	16	21192	17512	f
21916	ФПИ и КТ	17	18090	17512	f
21917	ФПИ и КТ	18	18089	17512	f
21334	Пр Кул	1	7957	5096	f
21335	Пр Кул	2	7130	5096	f
21336	SS	1	21052	5097	f
21337	SS	2	9326	5097	f
21338	ОтдПВ	1	30184	7321	f
21339	ФСУ и Р	1	21447	5665	f
21340	ФПИ и КТ	2	20123	5665	f
21341	ФПИ и КТ	3	18040	5665	f
21342	ФПИ и КТ	4	18039	5665	f
21343	ФПИ и КТ	5	18037	5665	f
21344	ФПИ и КТ	6	18036	5665	f
21345	ФПИ и КТ	7	18035	5665	f
21346	ФПИ и КТ	8	18034	5665	f
21347	ФПИ и КТ	9	18033	5665	f
21348	ФПИ и КТ	10	18032	5665	f
21349	ФПИ и КТ	11	13675	5665	f
21350	ФПИ и КТ	12	7799	5665	f
21351	ФПИ и КТ	13	7118	5665	f
21352	ФПИ и КТ	14	5959	5665	f
21353	НОЦМ	1	21451	5492	f
21354	НОЦМ	2	21452	5492	f
21355	ВШ ЦК	1	21137	5126	f
21356	ВШ ЦК	2	21013	5126	f
21357	ВШ ЦК	3	19905	5126	f
21358	ВШ ЦК	4	19903	5126	f
21359	ВШ ЦК	5	19743	5126	f
21360	ВШ ЦК	1	16579	5495	f
21361	ВШ ЦК	2	16580	5495	f
21362	ВШ ЦК	1	16581	5496	f
21363	ВШ ЦК	2	16582	5496	f
21364	ВШ ЦК	1	16583	5497	f
21365	ВШ ЦК	2	16584	5497	f
21366	ФПИ и КТ	1	18046	5498	f
21367	ФПИ и КТ	2	18045	5498	f
21368	ФПИ и КТ	3	18044	5498	f
21369	ФПИ и КТ	4	18043	5498	f
21370	ФПИ и КТ	5	18042	5498	f
21371	ФПИ и КТ	6	5967	5498	f
21372	ФПИ и КТ	1	35212	5501	f
21373	ФПИ и КТ	2	35211	5501	f
21374	ФПИ и КТ	3	35210	5501	f
21375	ФПИ и КТ	4	34377	5501	f
21376	ФПИ и КТ	5	32187	5501	f
21377	ФПИ и КТ	6	18053	5501	f
21378	ФПИ и КТ	7	18048	5501	f
21379	ФПИ и КТ	8	2243	5501	f
21380	ФПИ и КТ	1	53697	5504	f
21381	ФПИ и КТ	2	34380	5504	f
21382	ФПИ и КТ	3	34379	5504	f
21918	ФПИ и КТ	19	18084	17512	f
21919	ФПИ и КТ	20	18053	17512	f
21920	ФПИ и КТ	21	53445	17512	f
21921	ФПИ и КТ	22	7841	17512	f
21922	ФПИ и КТ	23	5959	17512	f
21923	ФПИ и КТ	24	826	17512	f
21924	НОЦМ	1	37121	17510	f
21925	НОЦМ	2	36232	17510	f
21926	НОЦМ	3	35856	17510	f
21927	НОЦМ	1	35853	17508	f
21383	ФПИ и КТ	4	34378	5504	f
21384	ФПИ и КТ	5	31765	5504	f
21385	ФПИ и КТ	6	18058	5504	f
21386	ФПИ и КТ	1	31762	5505	t
21387	ФПИ и КТ	2	18065	5505	t
21388	ФПИ и КТ	3	18064	5505	t
21389	ФПИ и КТ	4	18063	5505	t
21390	ФПИ и КТ	5	53698	5505	t
21391	ФПИ и КТ	6	18061	5505	t
21392	ФПИ и КТ	7	18060	5505	t
21393	ФПИ и КТ	8	52349	5505	t
21394	ФПИ и КТ	9	826	5505	t
21395	ФПИ и КТ	1	36222	5507	f
21396	ФПИ и КТ	2	36221	5507	f
21397	ФПИ и КТ	3	29996	5507	f
21398	ФПИ и КТ	1	18072	5509	f
21399	ФПИ и КТ	2	18071	5509	f
21400	ФПИ и КТ	3	53992	5509	f
21401	ФПИ и КТ	4	18061	5509	f
21402	ФПИ и КТ	1	34378	5510	t
21403	ФПИ и КТ	2	31765	5510	t
21404	ФПИ и КТ	3	31762	5510	t
21405	ФПИ и КТ	4	18065	5510	t
21406	ФПИ и КТ	5	18058	5510	t
21407	ФПИ и КТ	6	52349	5510	t
21408	ФПИ и КТ	7	826	5510	t
21409	ФПИ и КТ	1	53694	5511	f
21410	ФПИ и КТ	2	36222	5511	f
21411	ФПИ и КТ	3	29996	5511	f
21412	ФПИ и КТ	1	53700	5513	f
21413	ФПИ и КТ	2	38205	5513	f
21414	ФПИ и КТ	3	38204	5513	f
21415	ФПИ и КТ	4	37120	5513	f
21416	НОЦМ	5	32911	5513	f
21417	ФПИ и КТ	6	31763	5513	f
21418	ФПИ и КТ	7	31762	5513	f
21419	ФПИ и КТ	8	18080	5513	f
21420	ФПИ и КТ	9	18078	5513	f
21421	ФПИ и КТ	10	18075	5513	f
21422	ФПИ и КТ	11	18073	5513	f
21928	НОЦМ	2	35855	17508	f
21929	ФизФ	1	35818	17509	f
21930	ФизФ	2	35819	17509	f
21931	ФПИ и КТ	1	37120	17511	t
21932	ФПИ и КТ	2	36233	17511	t
21933	ФПИ и КТ	3	36225	17511	t
21934	ФПИ и КТ	4	36220	17511	t
21935	ФПИ и КТ	5	36210	17511	t
21936	ФПИ и КТ	6	36211	17511	t
21937	ФПИ и КТ	7	18094	17511	t
21938	ФПИ и КТ	8	18079	17511	t
21939	ФПИ и КТ	9	18042	17511	t
21940	ФПИ и КТ	10	18032	17511	t
21423	ФПИ и КТ	12	18064	5513	f
21424	ФПИ и КТ	1	32187	5514	t
21425	ФПИ и КТ	2	18079	5514	t
21426	ФПИ и КТ	3	18065	5514	t
21427	ФПИ и КТ	4	18063	5514	t
21428	ФПИ и КТ	5	18060	5514	t
21429	ФПИ и КТ	6	18053	5514	t
21430	ФПИ и КТ	7	18048	5514	t
21431	ФПИ и КТ	8	52349	5514	t
21432	ФПИ и КТ	1	53696	5516	f
21433	НОЦМ	2	32911	5516	f
21434	ФСУ и Р	3	21455	5516	f
21435	НОЦМ	4	21453	5516	f
21436	ФПИ и КТ	5	21192	5516	f
21437	ФПИ и КТ	6	21190	5516	f
21438	ФПИ и КТ	7	19037	5516	f
21439	ФПИ и КТ	8	18091	5516	f
21440	ФПИ и КТ	9	18090	5516	f
21441	ФПИ и КТ	10	18089	5516	f
21442	ФПИ и КТ	11	18087	5516	f
21443	ФПИ и КТ	12	18086	5516	f
21444	ФПИ и КТ	13	18084	5516	f
21445	ФизФ	14	18082	5516	f
21446	ФПИ и КТ	15	18080	5516	f
21447	ФПИ и КТ	16	18075	5516	f
21448	ФПИ и КТ	17	18073	5516	f
21449	ФПИ и КТ	18	18064	5516	f
21450	ФПИ и КТ	19	18053	5516	f
21451	ФПИ и КТ	20	16291	5516	f
21452	ФПИ и КТ	21	7841	5516	f
21453	ФПИ и КТ	22	6121	5516	f
21454	ФПИ и КТ	23	5917	5516	f
21455	ФПИ и КТ	24	826	5516	f
21456	ФПИ и КТ	1	18063	5517	f
21457	ФПИ и КТ	2	18042	5517	f
21458	ФПИ и КТ	1	35210	5518	t
21459	ФПИ и КТ	2	32187	5518	t
21460	ФПИ и КТ	3	19045	5518	t
21461	ФПИ и КТ	4	18079	5518	t
21462	ФПИ и КТ	5	18048	5518	t
21463	ФПИ и КТ	6	52349	5518	t
21464	ФПИ и КТ	7	5967	5518	t
21465	ФПИ и КТ	8	2086	5518	t
9112	ФПИ и КТ	1	31769	-113	t
9113	ФПИ и КТ	1	31770	-114	t
9114	ФПИ и КТ	1	31771	-116	t
9115	ФПИ и КТ	1	31772	-120	f
9116	ФПИ и КТ	2	16977	-120	f
9117	ФПИ и КТ	3	16978	-120	f
9118	ФПИ и КТ	1	16649	-122	f
9119	ФПИ и КТ	2	10121	-122	f
9120	ФПИ и КТ	3	16984	-122	f
9121	ФПИ и КТ	1	31773	-123	f
9122	ФПИ и КТ	2	31775	-123	f
21466	ФПИ и КТ	1	18065	5519	t
21467	ФПИ и КТ	2	18060	5519	t
21468	ФПИ и КТ	3	5902	5519	t
21469	ФПИ и КТ	4	3312	5519	t
21470	ФПИ и КТ	5	2243	5519	t
21471	ВШ ЦК	1	16579	5522	f
21472	ВШ ЦК	2	16580	5522	f
21473	ВШ ЦК	1	16581	5523	f
21474	ВШ ЦК	2	16582	5523	f
21475	ВШ ЦК	1	16583	5524	f
21476	ВШ ЦК	2	16584	5524	f
21477	ФПИ и КТ	1	53701	5525	f
21478	ФПИ и КТ	2	20393	5525	f
21479	ФПИ и КТ	3	18102	5525	f
21480	ФПИ и КТ	4	18101	5525	f
21481	ФПИ и КТ	5	18100	5525	f
21482	ФПИ и КТ	6	18099	5525	f
21483	ФПИ и КТ	7	18098	5525	f
21484	ФПИ и КТ	8	18097	5525	f
21485	ФПИ и КТ	9	18096	5525	f
21486	ФПИ и КТ	10	18095	5525	f
21487	ФПИ и КТ	11	18076	5525	f
21488	ФПИ и КТ	12	18065	5525	f
21489	ФПИ и КТ	13	18063	5525	f
21490	ФПИ и КТ	1	5967	5862	f
21491	ФПИ и КТ	2	20127	5862	f
21492	ФПИ и КТ	1	18073	5526	t
21493	ФПИ и КТ	2	18060	5526	t
21494	ФПИ и КТ	3	18042	5526	t
21495	ФПИ и КТ	4	2243	5526	t
21496	ФПИ и КТ	1	18078	5527	t
21497	ФПИ и КТ	2	18064	5527	t
21498	ФПИ и КТ	3	18053	5527	t
21499	ФПИ и КТ	4	52349	5527	t
21500	ФПИ и КТ	1	29980	13161	f
21501	ФПИ и КТ	2	29433	13161	f
21502	ФПИ и КТ	1	29435	4794	f
21941	ФПИ и КТ	11	7068	17511	t
21942	ФПИ и КТ	12	5902	17511	t
21943	ФПИ и КТ	13	3312	17511	t
21944	ФПИ и КТ	14	2086	17511	t
21945	ФПИ и КТ	1	58001	17529	f
21946	ФПИ и КТ	2	52342	17529	f
21947	ФПИ и КТ	3	36259	17529	f
21948	ФПИ и КТ	4	36260	17529	f
21949	ФПИ и КТ	5	36257	17529	f
21950	ФПИ и КТ	6	36258	17529	f
21951	ФПИ и КТ	7	36219	17529	f
21952	ФПИ и КТ	8	18102	17529	f
21953	ФПИ и КТ	9	18095	17529	f
21954	ФПИ и КТ	10	18065	17529	f
21955	ФПИ и КТ	11	18032	17529	f
21956	ВШ ЦК	1	16579	17515	f
21957	ВШ ЦК	2	16580	17515	f
21958	ВШ ЦК	1	16581	17517	f
21959	ВШ ЦК	2	16582	17517	f
21960	ВШ ЦК	1	16583	17516	f
21961	ВШ ЦК	2	16584	17516	f
21962	ФПИ и КТ	1	36245	17520	f
21963	ФПИ и КТ	2	36246	17520	f
21964	ФПИ и КТ	3	36242	17520	f
21965	ФПИ и КТ	4	36244	17520	f
21966	ФПИ и КТ	5	36239	17520	f
21967	ФПИ и КТ	6	36243	17520	f
21968	ФПИ и КТ	7	36240	17520	f
21969	ФПИ и КТ	8	36241	17520	f
21970	ФПИ и КТ	9	35216	17520	f
21971	ФПИ и КТ	10	35214	17520	f
21972	ФПИ и КТ	11	18101	17520	f
21973	ФПИ и КТ	1	36227	17525	t
21974	ФПИ и КТ	2	36225	17525	t
21975	ФПИ и КТ	3	18078	17525	t
21976	ФПИ и КТ	4	18042	17525	t
21977	ФПИ и КТ	1	36210	17523	t
21978	ФПИ и КТ	2	36211	17523	t
21979	ФПИ и КТ	1	36248	17524	t
21980	ФПИ и КТ	2	36247	17524	t
21981	ФПИ и КТ	1	36255	17527	f
21982	ФПИ и КТ	2	36256	17527	f
21983	ФПИ и КТ	3	36252	17527	f
21984	ФПИ и КТ	4	36254	17527	f
21985	ФПИ и КТ	5	36249	17527	f
21986	ФПИ и КТ	6	36253	17527	f
21987	ФПИ и КТ	7	36250	17527	f
21988	ФПИ и КТ	8	36251	17527	f
21989	ФПИ и КТ	9	35222	17527	f
21990	ФПИ и КТ	10	35217	17527	f
21991	ФПИ и КТ	11	18096	17527	f
21992	ФПИ и КТ	12	18042	17527	f
21993	ФПИ и КТ	1	36217	17528	t
21994	ФПИ и КТ	2	21192	17528	t
21995	ФПИ и КТ	3	18075	17528	t
21996	ФПИ и КТ	4	18053	17528	t
21997	ФПИ и КТ	5	16291	17528	t
21998	ФПИ и КТ	6	2086	17528	t
21999	ФПИ и КТ	7	826	17528	t
22000	ФПИ и КТ	1	36262	17531	t
22001	ФПИ и КТ	1	36261	17530	t
22002	ФПИ и КТ	1	36263	17532	t
22003	ЦСиГН	1	52126	54531	f
22004	ЦСиГН	2	52328	54531	f
22005	ЦСиГН	1	52127	54530	f
22006	ЦСиГН	2	52327	54530	f
22007	ЦСиГН	1	52128	54529	f
22008	ЦСиГН	2	52326	54529	f
22009	ЦСиГН	1	52129	54528	f
22010	ЦСиГН	2	52325	54528	f
22011	ЦСиГН	1	52131	54527	f
22012	ЦСиГН	2	52324	54527	f
22013	ЦСиГН	1	52130	54526	f
22014	ЦСиГН	2	52323	54526	f
22015	ОтдПВ	1	30184	51854	f
22016	БЖД	2	5895	51854	f
22017	ССККБ	1	16560	51853	f
22018	ССККБ	2	16559	51853	f
22019	F	1	52215	51199	f
22020	ЦИИЯ	1	53919	56431	f
22021	ЦИИЯ	2	53918	56431	f
22022	ЦИИЯ	3	53917	56431	f
22023	ЦИИЯ	4	53916	56431	f
22024	ЦИИЯ	5	53915	56431	f
22025	ЦИИЯ	6	53914	56431	f
22026	ЦИИЯ	7	36567	56431	f
22027	ЦИИЯ	1	53920	56430	f
21503	ЦСиГН	1	33957	12242	f
21504	ЦСиГН	2	33956	12242	f
21505	ЦСиГН	3	33955	12242	f
21506	ЦСиГН	4	33954	12242	f
21507	ЦСиГН	5	33953	12242	f
21508	ЦСиГН	6	33951	12242	f
21509	БЖД	1	5895	12244	f
21510	ССККБ	1	16560	12235	f
21511	ССККБ	1	16559	12236	f
21512	F	1	30175	12240	f
21513	ЦИИЯ	1	29867	50438	f
21514	ЦИИЯ	1	29867	50439	f
21515	ЦИИЯ	1	36642	22604	f
21516	ЦИИЯ	2	36641	22604	f
21517	ЦИИЯ	3	36640	22604	f
21518	ЦИИЯ	4	36639	22604	f
21519	ЦИИЯ	5	36575	22604	f
21520	ЦИИЯ	6	36574	22604	f
21521	ЦИИЯ	7	36573	22604	f
21522	ЦИИЯ	8	36572	22604	f
22028	ЦИИЯ	2	53919	56430	f
21523	ЦИИЯ	9	36571	22604	f
21524	ЦИИЯ	10	36570	22604	f
21525	ЦИИЯ	11	36569	22604	f
21526	ЦИИЯ	12	36568	22604	f
21527	ЦИИЯ	13	36567	22604	f
21528	ЦИИЯ	14	36566	22604	f
21529	ЦИИЯ	1	36646	22603	f
21530	ЦИИЯ	2	36645	22603	f
21531	ЦИИЯ	3	36644	22603	f
21532	ЦИИЯ	4	36643	22603	f
21533	ЦИИЯ	5	36642	22603	f
21534	ЦИИЯ	6	36641	22603	f
21535	ЦИИЯ	7	36640	22603	f
21536	ЦИИЯ	8	36639	22603	f
21537	ЦИИЯ	9	36575	22603	f
21538	ЦИИЯ	10	36574	22603	f
21539	ЦИИЯ	11	36573	22603	f
21540	ЦИИЯ	12	36572	22603	f
21541	ЦИИЯ	13	36571	22603	f
21542	ЦИИЯ	14	36570	22603	f
21543	ЦИИЯ	15	36569	22603	f
21544	ЦИИЯ	16	36568	22603	f
21545	ЦИИЯ	17	36567	22603	f
21546	ЦИИЯ	18	36566	22603	f
21547	Пр Кул	1	33341	12238	f
21548	Пр Кул	2	30182	12238	f
21549	Пр Кул	3	30181	12238	f
21550	Пр Кул	4	30180	12238	f
21551	Пр Кул	5	30179	12238	f
21552	Пр Кул	6	30178	12238	f
21553	Пр Кул	7	30177	12238	f
21554	Пр Кул	8	30176	12238	f
21555	Пр Кул	1	30183	12239	f
21556	SS	1	9326	12243	f
21557	SS	2	21052	12243	f
21558	ОтдПВ	1	30184	12245	f
21559	ФПИ и КТ	1	53682	12341	f
21560	ФПИ и КТ	2	34617	12341	f
21561	ФПИ и КТ	3	20123	12341	f
21562	ФПИ и КТ	4	18040	12341	f
21563	ФПИ и КТ	5	18037	12341	f
21564	ФПИ и КТ	6	18036	12341	f
21565	ФПИ и КТ	7	18035	12341	f
21566	ФПИ и КТ	8	36202	12341	f
21567	ФПИ и КТ	9	18033	12341	f
21568	ФПИ и КТ	10	7799	12341	f
21569	ФПИ и КТ	11	7118	12341	f
21570	НОЦМ	1	31768	12338	f
21571	НОЦМ	2	30195	12338	f
21572	ВШ ЦК	1	21137	12344	f
21573	ВШ ЦК	2	21013	12344	f
21574	ВШ ЦК	3	19905	12344	f
21575	ВШ ЦК	4	19903	12344	f
21576	ВШ ЦК	5	19745	12344	f
21577	ВШ ЦК	6	19743	12344	f
21578	ВШ ЦК	7	19742	12344	f
21579	ФПИ и КТ	1	18046	12250	f
21580	ФПИ и КТ	2	18045	12250	f
21581	ФПИ и КТ	3	18044	12250	f
21582	ФПИ и КТ	4	18043	12250	f
21583	ФПИ и КТ	5	18042	12250	f
21584	ФПИ и КТ	6	5967	12250	f
21585	ВШ ЦК	1	16579	12252	f
22029	ЦИИЯ	3	53918	56430	f
22960	SS	1	38269	63222	f
22961	SS	1	36730	63223	f
22962	F	1	56142	63235	f
22963	ФТМИ	1	51234	63236	f
22964	креатив	1	21041	63234	f
22965	ЦИИЯ	1	36728	63232	f
22966	ЦИИЯ	1	36729	63231	f
22967	ВШ ЦК	1	56559	63229	f
22968	ВШ ЦК	1	56563	63228	f
22969	ФПИ и КТ	1	57386	62847	f
22970	ФПИ и КТ	2	52346	62847	f
22971	ФПИ и КТ	3	59496	62847	f
22972	ФПИ и КТ	4	35979	62847	f
22973	ФПИ и КТ	5	16978	62847	f
22974	ФПИ и КТ	1	52347	61846	f
22975	ФПИ и КТ	2	31776	61846	f
22976	ФПИ и КТ	3	16988	61846	f
22977	ФПИ и КТ	4	16984	61846	f
22978	ФПИ и КТ	5	16982	61846	f
22979	ФПИ и КТ	6	16649	61846	f
22980	ФПИ и КТ	7	10121	61846	f
22981	ФПИ и КТ	8	1001	61846	f
22982	ФПИ и КТ	1	52371	61845	f
22983	ФПИ и КТ	2	9189	61845	f
22984	ФПИ и КТ	1	57389	61841	f
22985	ФПИ и КТ	2	52332	61841	f
22986	ФПИ и КТ	3	52331	61841	f
22987	ФПИ и КТ	4	52330	61841	f
22988	ФПИ и КТ	5	52329	61841	f
22989	ФПИ и КТ	6	35980	61841	f
22990	ФПИ и КТ	7	16996	61841	f
22991	ФПИ и КТ	8	16995	61841	f
22992	ФПИ и КТ	9	16993	61841	f
22993	ФПИ и КТ	1	35986	52283	f
22994	ФПИ и КТ	2	35985	52283	f
22995	ФПИ и КТ	3	35984	52283	f
22996	ФПИ и КТ	1	35983	52282	f
22997	ФПИ и КТ	1	35982	52281	f
22998	ФПИ и КТ	1	35987	52280	f
20279	ВШ ЦК	1	30285	52840	f
20280	ВШ ЦК	1	16464	52841	f
21586	ВШ ЦК	2	16580	12252	f
21587	ВШ ЦК	1	16581	12253	f
21588	ВШ ЦК	2	16582	12253	f
21589	ВШ ЦК	1	16583	12254	f
21590	ВШ ЦК	2	16584	12254	f
21591	ФПИ и КТ	1	35212	12269	f
21592	ФПИ и КТ	2	53690	12269	f
21593	ФПИ и КТ	3	36220	12269	f
21594	ФПИ и КТ	4	34377	12269	f
21595	ФПИ и КТ	5	32187	12269	f
21596	ФПИ и КТ	6	18053	12269	f
21597	ФПИ и КТ	7	18048	12269	f
21598	ФПИ и КТ	8	18032	12269	f
21599	ФПИ и КТ	9	2243	12269	f
21600	ФПИ и КТ	1	53678	12274	f
21601	ФПИ и КТ	2	34380	12274	f
22030	ЦИИЯ	4	53917	56430	f
22031	ЦИИЯ	5	53916	56430	f
22032	ЦИИЯ	6	53915	56430	f
22033	ЦИИЯ	7	53914	56430	f
22034	ЦИИЯ	8	36567	56430	f
22035	ЦИИЯ	1	53921	56429	f
22036	ЦИИЯ	2	53920	56429	f
22037	ЦИИЯ	3	53919	56429	f
22038	ЦИИЯ	4	53918	56429	f
22039	ЦИИЯ	5	53917	56429	f
22040	ЦИИЯ	6	53916	56429	f
22041	ЦИИЯ	7	53915	56429	f
22042	ЦИИЯ	8	53914	56429	f
22043	ЦИИЯ	9	36567	56429	f
22044	ФТМИ	1	51300	51852	f
22045	ФТМИ	2	51299	51852	f
22046	ФТМИ	3	51298	51852	f
22047	ФТМИ	4	51297	51852	f
22048	ФТМИ	5	51296	51852	f
22049	ФТМИ	6	50667	51852	f
22050	ФТМИ	1	51301	51851	f
22051	ФТМИ	2	51292	51851	f
22052	ФТМИ	1	51302	51850	f
22053	ФТМИ	2	51295	51850	f
22054	ФТМИ	3	51294	51850	f
22055	ФТМИ	4	51293	51850	f
22056	Пр Кул	5	50666	51850	f
22057	ФТМИ	6	50664	51850	f
22058	ФТМИ	1	51290	51844	f
22059	SS	1	50277	55483	f
22060	SS	2	35368	55483	f
22061	ИМ	1	54491	54461	f
22062	ИМ	2	54487	54461	f
22063	ИМ	1	54488	54460	f
22064	ФПИ и КТ	1	53673	52694	f
22065	ФПИ и КТ	2	18040	52694	f
22066	ФПИ и КТ	1	53682	52689	f
22067	ФПИ и КТ	2	53674	52689	f
22068	ФПИ и КТ	3	36219	52689	f
22069	ФПИ и КТ	4	36202	52689	f
22070	ФПИ и КТ	5	36201	52689	f
22071	ФПИ и КТ	6	36199	52689	f
22072	ФПИ и КТ	7	36198	52689	f
22073	ФПИ и КТ	8	7799	52689	f
22074	ВШ ЦК	1	16579	56433	f
22075	ВШ ЦК	2	16580	56433	f
22076	ВШ ЦК	1	16581	56434	f
22077	ВШ ЦК	2	16582	56434	f
22078	ВШ ЦК	1	16583	56435	f
22079	ВШ ЦК	2	16584	56435	f
22080	ВШ ЦК	1	21137	52728	f
22081	ВШ ЦК	2	21013	52728	f
22082	ВШ ЦК	3	19905	52728	f
22083	ВШ ЦК	4	19903	52728	f
22084	ВШ ЦК	5	19843	52728	f
22085	ВШ ЦК	6	19745	52728	f
22086	ВШ ЦК	7	19743	52728	f
22087	ВШ ЦК	8	19742	52728	f
22088	ФПИ и КТ	1	36210	52740	f
22089	ФПИ и КТ	2	36211	52740	f
22090	ФПИ и КТ	1	52373	52739	f
22091	ФПИ и КТ	2	52374	52739	f
22092	ФПИ и КТ	3	36205	52739	f
22093	ФПИ и КТ	1	52352	52738	f
22094	ФПИ и КТ	2	52353	52738	f
22095	ФПИ и КТ	3	52354	52738	f
22096	ФПИ и КТ	4	36208	52738	f
22097	ФПИ и КТ	1	36212	52737	f
22098	ФПИ и КТ	2	36213	52737	f
22099	ФПИ и КТ	1	53690	52758	f
22100	ФПИ и КТ	2	53683	52758	f
22101	ФПИ и КТ	3	53991	52758	f
22102	ФПИ и КТ	4	52372	52758	f
22103	ФПИ и КТ	5	36220	52758	f
22104	ФПИ и КТ	6	36218	52758	f
22105	ФПИ и КТ	7	36217	52758	f
22106	ФПИ и КТ	8	36216	52758	f
22107	ФПИ и КТ	9	36214	52758	f
22108	ФПИ и КТ	10	34378	52758	f
22109	ФПИ и КТ	11	18065	52758	f
22110	ФПИ и КТ	12	18058	52758	f
22111	ФПИ и КТ	13	18053	52758	f
22112	ФПИ и КТ	14	18042	52758	f
22113	ФПИ и КТ	15	18032	52758	f
22114	ФПИ и КТ	1	53684	52757	f
22115	ФПИ и КТ	2	53678	52757	f
22116	ФПИ и КТ	3	36224	52757	f
22117	ФПИ и КТ	4	36223	52757	f
22118	ФПИ и КТ	5	31765	52757	f
22119	ФПИ и КТ	1	53698	52756	t
22120	ФПИ и КТ	2	52349	52756	t
22121	ФПИ и КТ	3	36228	52756	t
22122	ФПИ и КТ	4	36227	52756	t
22123	ФПИ и КТ	5	36225	52756	t
22124	ФПИ и КТ	6	31762	52756	t
22125	ФПИ и КТ	7	18061	52756	t
22126	ФПИ и КТ	8	826	52756	t
22127	ФПИ и КТ	1	36222	52755	f
22128	ФПИ и КТ	2	36221	52755	f
22129	ФПИ и КТ	3	31766	52755	f
22130	ФПИ и КТ	1	53698	52754	f
22131	ФПИ и КТ	2	36229	52754	f
22132	ФПИ и КТ	3	36230	52754	f
22133	ФПИ и КТ	4	18072	52754	f
22134	ФПИ и КТ	5	18061	52754	f
22135	ФПИ и КТ	1	52349	52753	t
22790	ФТМИ	2	51302	62905	f
22854	ФПИ и КТ	3	31766	62380	t
22136	ФПИ и КТ	2	36225	52753	t
22137	ФПИ и КТ	3	31765	52753	t
22138	ФПИ и КТ	4	31762	52753	t
22139	ФПИ и КТ	1	53694	52751	f
22140	ФПИ и КТ	2	36222	52751	f
22141	ФПИ и КТ	3	31766	52751	f
22142	ИМ	1	54500	52745	f
22143	ИМ	2	54474	52745	f
22144	ФПИ и КТ	3	53695	52745	f
22145	ФПИ и КТ	4	53691	52745	f
22146	ФПИ и КТ	5	53686	52745	f
22147	ФПИ и КТ	6	53685	52745	f
22148	ФПИ и КТ	7	31763	52745	f
22149	ФПИ и КТ	8	31762	52745	f
22150	ФПИ и КТ	9	52375	52745	f
22151	ФПИ и КТ	10	52376	52745	f
22152	ФПИ и КТ	11	38205	52745	f
22153	ФПИ и КТ	12	37120	52745	f
22154	ФПИ и КТ	13	36228	52745	f
22155	ФПИ и КТ	14	36227	52745	f
22156	ФПИ и КТ	15	36225	52745	f
22157	ФПИ и КТ	16	18078	52745	f
22158	ФПИ и КТ	17	18065	52745	f
22159	ФПИ и КТ	18	18042	52745	f
22160	ФПИ и КТ	1	52349	52744	t
22161	ФПИ и КТ	2	36216	52744	t
22162	ФПИ и КТ	3	18079	52744	t
22163	ФПИ и КТ	4	18053	52744	t
22164	ФПИ и КТ	5	18032	52744	t
22165	ФПИ и КТ	1	53695	52733	f
22166	ФПИ и КТ	2	53693	52733	f
22167	ФПИ и КТ	3	36234	52733	f
22168	ФПИ и КТ	4	53689	52733	f
22169	ФПИ и КТ	5	53687	52733	f
22170	ФПИ и КТ	6	53681	52733	f
22171	ФПИ и КТ	7	53680	52733	f
22172	ФПИ и КТ	8	53679	52733	f
22173	ФПИ и КТ	9	53677	52733	f
22174	ФПИ и КТ	10	53676	52733	f
22175	ФПИ и КТ	11	37122	52733	f
22176	ФПИ и КТ	12	36228	52733	f
22177	ФПИ и КТ	13	36227	52733	f
22178	ФПИ и КТ	14	36217	52733	f
22179	ФПИ и КТ	15	36197	52733	f
22180	ФПИ и КТ	16	21192	52733	f
22181	ФПИ и КТ	17	21190	52733	f
22182	ФПИ и КТ	18	18090	52733	f
22183	ФПИ и КТ	19	18089	52733	f
22184	ФПИ и КТ	20	18084	52733	f
22185	ФПИ и КТ	21	18065	52733	f
22186	ФПИ и КТ	22	18053	52733	f
22187	ФПИ и КТ	23	18042	52733	f
22188	ФПИ и КТ	24	7841	52733	f
22189	ФПИ и КТ	25	5917	52733	f
22190	ФПИ и КТ	26	826	52733	f
22191	ИМ	1	54859	52732	f
22192	ИМ	2	54499	52732	f
22193	ФизФ	1	35818	52731	f
22194	ФизФ	2	35819	52731	f
22195	ФПИ и КТ	1	52349	52730	t
22196	ФПИ и КТ	2	37120	52730	t
22197	ФПИ и КТ	3	36233	52730	t
22198	ФПИ и КТ	4	36225	52730	t
22199	ФПИ и КТ	5	36210	52730	t
22200	ФПИ и КТ	6	36211	52730	t
22201	ФПИ и КТ	7	18094	52730	t
22202	ФПИ и КТ	8	18079	52730	t
22203	ФПИ и КТ	9	18032	52730	t
22204	ФПИ и КТ	10	5902	52730	t
22205	ФПИ и КТ	11	3312	52730	t
22206	ФПИ и КТ	12	2086	52730	t
22207	ФПИ и КТ	1	53991	52726	f
22208	ФПИ и КТ	2	52344	52726	f
22209	ФПИ и КТ	3	52343	52726	f
22210	ФПИ и КТ	4	52342	52726	f
22211	ФПИ и КТ	5	52340	52726	f
22212	ФПИ и КТ	6	52341	52726	f
22213	ФПИ и КТ	7	52338	52726	f
22214	ФПИ и КТ	8	52339	52726	f
22215	ФПИ и КТ	9	52336	52726	f
22216	ФПИ и КТ	10	52337	52726	f
22217	ФПИ и КТ	11	52334	52726	f
22218	ФПИ и КТ	12	52335	52726	f
22219	ФПИ и КТ	13	36248	52726	f
22220	ФПИ и КТ	14	36247	52726	f
22221	ФПИ и КТ	15	36239	52726	f
22222	ФПИ и КТ	16	36243	52726	f
22223	ФПИ и КТ	17	36240	52726	f
22224	ФПИ и КТ	18	36241	52726	f
22225	ФПИ и КТ	19	18102	52726	f
22226	ФПИ и КТ	20	18095	52726	f
22227	ФПИ и КТ	21	18065	52726	f
22228	ФПИ и КТ	22	18042	52726	f
22229	ФПИ и КТ	23	18032	52726	f
22230	ФПИ и КТ	1	53678	52723	t
22231	ФПИ и КТ	2	36228	52723	t
22232	ФПИ и КТ	3	36227	52723	t
22233	ФПИ и КТ	4	36225	52723	t
22234	ФПИ и КТ	5	36210	52723	t
22235	ФПИ и КТ	6	36211	52723	t
22236	ФПИ и КТ	7	18078	52723	t
22237	ФПИ и КТ	1	36262	54514	t
22238	ФПИ и КТ	1	36261	54515	t
22239	ФПИ и КТ	1	36263	54520	t
22749	ЦСиГН	1	52130	62910	f
22750	ЦСиГН	2	52323	62910	f
18757	SS	1	38269	17462	f
18758	SS	1	36738	17460	f
18759	F	1	36822	17458	f
18760	Пр Кул	1	33340	17456	f
18761	Институт МР и П	1	34013	17453	f
18762	ЦИИЯ	1	36728	17447	f
18763	ЦИИЯ	1	36729	17449	f
18764	ВШ ЦК	1	30285	17407	f
18765	ВШ ЦК	1	16464	17408	f
18766	ФПИ и КТ	1	35979	17397	f
18767	ФПИ и КТ	2	35978	17397	f
18768	ФПИ и КТ	3	35977	17397	f
18769	ФПИ и КТ	4	16978	17397	f
18770	ФПИ и КТ	1	16988	17401	f
18771	ФПИ и КТ	2	16985	17401	f
18772	ФПИ и КТ	3	16984	17401	f
18773	ФПИ и КТ	4	16982	17401	f
18774	ФПИ и КТ	5	16649	17401	f
18775	ФПИ и КТ	6	10121	17401	f
18776	ФПИ и КТ	7	1001	17401	f
18777	ФПИ и КТ	1	31776	17400	f
18778	ФПИ и КТ	2	16768	17400	f
18779	ФПИ и КТ	3	9189	17400	f
18780	ФПИ и КТ	1	35981	17403	f
18781	ФПИ и КТ	2	35980	17403	f
18782	ФПИ и КТ	3	31773	17403	f
18783	ФПИ и КТ	4	16996	17403	f
18784	ФПИ и КТ	5	16995	17403	f
18785	ФПИ и КТ	6	16994	17403	f
18786	ФПИ и КТ	7	16993	17403	f
18787	ФПИ и КТ	8	16991	17403	f
18788	ФПИ и КТ	1	35986	17467	t
18789	ФПИ и КТ	2	35985	17467	t
18790	ФПИ и КТ	3	35984	17467	t
18791	ФПИ и КТ	1	35983	17465	t
18792	ФПИ и КТ	1	35982	17463	t
18793	ФПИ и КТ	1	35987	17469	t
22739	ЦСиГН	1	52126	62916	f
22740	ЦСиГН	2	52328	62916	f
22741	ЦСиГН	1	52127	62915	f
22742	ЦСиГН	2	52327	62915	f
22743	ЦСиГН	1	52128	62914	f
22744	ЦСиГН	2	52326	62914	f
22745	ЦСиГН	1	52129	62913	f
22746	ЦСиГН	2	52325	62913	f
22747	ЦСиГН	1	52131	62912	f
22748	ЦСиГН	2	52324	62912	f
22751	ОтдПВ	1	30184	62901	f
22752	БЖД	2	5895	62901	f
22753	ССККБ	1	16560	62902	f
22754	ССККБ	2	16559	62902	f
22755	F	1	56219	62909	f
22756	ЦИИЯ	1	53919	62886	f
22757	ЦИИЯ	2	53918	62886	f
22758	ЦИИЯ	3	53917	62886	f
22759	ЦИИЯ	4	53916	62886	f
22760	ЦИИЯ	5	53915	62886	f
22761	ЦИИЯ	6	53914	62886	f
22762	ЦИИЯ	7	36567	62886	f
22763	ЦИИЯ	1	55851	62885	f
22764	ЦИИЯ	2	53920	62885	f
22765	ЦИИЯ	3	53919	62885	f
22766	ЦИИЯ	4	53918	62885	f
22767	ЦИИЯ	5	53917	62885	f
22768	ЦИИЯ	6	53916	62885	f
22769	ЦИИЯ	7	53915	62885	f
22770	ЦИИЯ	8	53914	62885	f
22771	ЦИИЯ	1	55852	62884	f
22772	ЦИИЯ	2	53921	62884	f
22773	ЦИИЯ	3	53920	62884	f
22774	ЦИИЯ	4	53919	62884	f
22775	ЦИИЯ	5	53918	62884	f
22776	ЦИИЯ	6	53917	62884	f
22777	ЦИИЯ	7	53916	62884	f
22279	SS	1	38269	56422	f
22280	SS	1	36738	56423	f
22281	F	1	52211	55989	f
22282	ФТМИ	1	51303	55987	f
22283	креатив	1	21041	55988	f
22284	ЦИИЯ	1	36728	50586	f
22285	ЦИИЯ	1	36729	50585	f
22288	ФПИ и КТ	1	52346	52275	f
22289	ФПИ и КТ	2	52345	52275	f
22290	ФПИ и КТ	3	52333	52275	f
22291	ФПИ и КТ	4	35979	52275	f
22292	ФПИ и КТ	5	16978	52275	f
22293	ФПИ и КТ	1	52347	52279	f
22294	ФПИ и КТ	2	31776	52279	f
22295	ФПИ и КТ	3	16988	52279	f
22296	ФПИ и КТ	4	16984	52279	f
22297	ФПИ и КТ	5	16982	52279	f
22298	ФПИ и КТ	6	16649	52279	f
22299	ФПИ и КТ	7	10121	52279	f
22300	ФПИ и КТ	8	1001	52279	f
22301	ФПИ и КТ	1	52371	52278	f
22302	ФПИ и КТ	2	9189	52278	f
22303	ФПИ и КТ	1	52332	52276	f
22304	ФПИ и КТ	2	52331	52276	f
22305	ФПИ и КТ	3	52330	52276	f
22306	ФПИ и КТ	4	52329	52276	f
22307	ФПИ и КТ	5	35980	52276	f
22308	ФПИ и КТ	6	31773	52276	f
22309	ФПИ и КТ	7	16996	52276	f
22310	ФПИ и КТ	8	16995	52276	f
22311	ФПИ и КТ	9	16993	52276	f
21602	ФПИ и КТ	3	57873	12274	f
21603	ФПИ и КТ	4	34378	12274	f
21604	ФПИ и КТ	5	31765	12274	f
21605	ФПИ и КТ	6	57874	12274	f
21606	ФПИ и КТ	1	31762	14925	t
21607	ФПИ и КТ	2	18065	14925	t
21608	ФПИ и КТ	3	36228	14925	t
21609	ФПИ и КТ	4	53698	14925	t
21610	ФПИ и КТ	5	18061	14925	t
21611	ФПИ и КТ	6	18060	14925	t
21612	ФПИ и КТ	7	52349	14925	t
21613	ФПИ и КТ	8	826	14925	t
21614	ФПИ и КТ	1	36222	12285	f
21615	ФПИ и КТ	2	36221	12285	f
21616	ФПИ и КТ	3	31766	12285	f
21617	ФПИ и КТ	1	18072	12291	f
21618	ФПИ и КТ	2	18071	12291	f
21619	ФПИ и КТ	3	53698	12291	f
21620	ФПИ и КТ	4	18061	12291	f
21621	ФПИ и КТ	1	34378	12294	t
21622	ФПИ и КТ	2	31765	12294	t
21623	ФПИ и КТ	3	31762	12294	t
21624	ФПИ и КТ	4	18065	12294	t
21625	ФПИ и КТ	5	18058	12294	t
21626	ФПИ и КТ	6	52349	12294	t
21627	ФПИ и КТ	7	826	12294	t
21628	ФПИ и КТ	1	53694	12296	f
21629	ФПИ и КТ	2	36222	12296	f
21630	ФПИ и КТ	3	31766	12296	f
21631	ФПИ и КТ	1	53686	12257	f
21632	ФПИ и КТ	2	53685	12257	f
21633	ФПИ и КТ	3	38205	12257	f
21634	ФПИ и КТ	4	38204	12257	f
21635	ФПИ и КТ	5	31763	12257	f
21636	ФПИ и КТ	6	31762	12257	f
21637	НОЦМ	7	30185	12257	f
21638	ФПИ и КТ	8	53695	12257	f
21639	ФПИ и КТ	9	18078	12257	f
21640	ФПИ и КТ	10	18075	12257	f
21641	ФПИ и КТ	11	18073	12257	f
21642	ФПИ и КТ	12	36228	12257	f
21643	ФПИ и КТ	13	18060	12257	f
21644	ФПИ и КТ	14	37120	12257	f
21645	ФПИ и КТ	1	32187	12263	t
21646	ФПИ и КТ	2	18079	12263	t
21647	ФПИ и КТ	3	18065	12263	t
21648	ФПИ и КТ	4	18053	12263	t
21649	ФПИ и КТ	5	18048	12263	t
21650	ФПИ и КТ	6	18032	12263	t
21651	ФПИ и КТ	7	52349	12263	t
21652	ФПИ и КТ	1	53687	12301	f
21653	ФПИ и КТ	2	53679	12301	f
21654	ФПИ и КТ	3	53689	12301	f
21655	ФПИ и КТ	4	53445	12301	f
21656	ФПИ и КТ	5	37122	12301	f
21657	ФПИ и КТ	6	53719	12301	f
21658	ФПИ и КТ	7	36234	12301	f
21659	ФПИ и КТ	8	29227	12301	f
21660	ФПИ и КТ	9	21192	12301	f
21661	ФПИ и КТ	10	21190	12301	f
21662	ФПИ и КТ	11	19037	12301	f
21663	ФПИ и КТ	12	18090	12301	f
21664	ФПИ и КТ	13	18089	12301	f
21665	ФПИ и КТ	14	36235	12301	f
21666	ФПИ и КТ	15	18084	12301	f
21667	ФПИ и КТ	16	53695	12301	f
21668	ФПИ и КТ	17	18075	12301	f
21669	ФПИ и КТ	18	18073	12301	f
21670	ФПИ и КТ	19	36228	12301	f
21671	ФПИ и КТ	20	18053	12301	f
21672	ФПИ и КТ	21	18048	12301	f
21673	ФПИ и КТ	22	7841	12301	f
21674	ФПИ и КТ	23	5917	12301	f
21675	ФПИ и КТ	24	826	12301	f
21676	ФПИ и КТ	25	5959	12301	f
21677	НОЦМ	1	31767	12304	f
21678	НОЦМ	2	30209	12304	f
21679	НОЦМ	3	30185	12304	f
21680	ФизФ	1	35818	12309	f
21681	ФизФ	2	35819	12309	f
21682	ФПИ и КТ	1	32187	12312	t
21683	ФПИ и КТ	2	18094	12312	t
21684	ФПИ и КТ	3	18079	12312	t
21685	ФПИ и КТ	4	18032	12312	t
21686	ФПИ и КТ	5	52349	12312	t
21687	ФПИ и КТ	6	5967	12312	t
21688	ФПИ и КТ	7	2086	12312	t
21689	ФПИ и КТ	1	18065	12314	t
21690	ФПИ и КТ	2	18060	12314	t
21691	ФПИ и КТ	3	18042	12314	t
21692	ФПИ и КТ	4	5902	12314	t
21693	ФПИ и КТ	5	3312	12314	t
21694	ФПИ и КТ	6	2243	12314	t
21695	ФПИ и КТ	1	53723	12355	f
21696	ФПИ и КТ	2	20393	12355	f
21697	ФПИ и КТ	3	18099	12355	f
21698	ФПИ и КТ	4	18102	12355	f
21699	ФПИ и КТ	5	18095	12355	f
21700	ФПИ и КТ	6	18065	12355	f
21701	ФПИ и КТ	7	18032	12355	f
21702	ВШ ЦК	1	16579	12350	f
21703	ВШ ЦК	2	16580	12350	f
21704	ВШ ЦК	1	16581	12352	f
21705	ВШ ЦК	2	16582	12352	f
21706	ВШ ЦК	1	16583	12353	f
21707	ВШ ЦК	2	16584	12353	f
21708	ФПИ и КТ	1	35216	15885	f
21709	ФПИ и КТ	2	18100	15885	f
21710	ФПИ и КТ	3	35214	15885	f
21711	ФПИ и КТ	4	35213	15885	f
21712	ФПИ и КТ	5	18101	15885	f
21713	ФПИ и КТ	6	18098	15885	f
21714	ФПИ и КТ	7	18076	15885	f
21715	ФПИ и КТ	1	18078	12345	t
21716	ФПИ и КТ	2	18073	12345	t
21717	ФПИ и КТ	3	18060	12345	t
21718	ФПИ и КТ	4	36228	12345	t
21719	ФПИ и КТ	5	52349	12345	t
21720	ФПИ и КТ	6	18042	12345	t
21721	ФПИ и КТ	1	20127	12346	f
21722	ФПИ и КТ	2	5967	12346	f
21723	ФПИ и КТ	1	35221	15884	f
21724	ФПИ и КТ	2	35220	15884	f
21725	ФПИ и КТ	3	35219	15884	f
21726	ФПИ и КТ	4	35218	15884	f
21727	ФПИ и КТ	5	35222	15884	f
21728	ФПИ и КТ	6	35217	15884	f
21729	ФПИ и КТ	7	18096	15884	f
21730	ФПИ и КТ	8	18042	15884	f
21731	ФПИ и КТ	1	21192	12348	t
21732	ФПИ и КТ	2	18075	12348	t
21733	ФПИ и КТ	3	18053	12348	t
21734	ФПИ и КТ	4	16291	12348	t
21735	ФПИ и КТ	5	18048	12348	t
21736	ФПИ и КТ	6	2086	12348	t
21737	ФПИ и КТ	7	826	12348	t
21738	ФПИ и КТ	1	31769	12347	t
21739	ФПИ и КТ	1	31770	12351	t
21740	ФПИ и КТ	1	36263	12354	t
22778	ЦИИЯ	8	53915	62884	f
22779	ЦИИЯ	9	53914	62884	f
22780	ФТМИ	1	51300	62908	f
22781	ФТМИ	2	51299	62908	f
22782	ФТМИ	3	51298	62908	f
22783	ФТМИ	4	51297	62908	f
22784	ФТМИ	5	51296	62908	f
22785	ФТМИ	6	50667	62908	f
22786	ФТМИ	1	56123	62907	f
22787	ФТМИ	2	56122	62907	f
22788	ФТМИ	3	56116	62907	f
22789	Пр Кул	1	52517	62906	f
22791	ФТМИ	3	51295	62906	f
22792	ФТМИ	4	51294	62906	f
22793	ФТМИ	5	51293	62906	f
22794	ФТМИ	6	50664	62906	f
22795	ФТМИ	1	51290	62904	f
22796	SS	1	50277	62879	f
22797	SS	2	35368	62879	f
22798	SS	1	56547	62882	f
22799	SS	2	56548	62882	f
22800	ИМ	1	54491	62871	f
22801	ИМ	2	54488	62871	f
22802	ИМ	3	54487	62871	f
22803	ФПИ и КТ	1	58772	62355	f
22804	ФПИ и КТ	2	58768	62355	f
22805	ФПИ и КТ	3	57871	62355	f
22806	ФПИ и КТ	4	57870	62355	f
22807	ФПИ и КТ	5	57869	62355	f
22808	ФПИ и КТ	6	57868	62355	f
22809	ФПИ и КТ	7	36219	62355	f
22810	ФПИ и КТ	8	36211	62355	f
22811	ФПИ и КТ	9	36210	62355	f
22812	ФПИ и КТ	10	36202	62355	f
22813	ФПИ и КТ	11	36201	62355	f
22814	ФПИ и КТ	12	36198	62355	f
22815	ФПИ и КТ	1	52374	62372	f
22816	ФПИ и КТ	2	52373	62372	f
22817	ФПИ и КТ	3	36205	62372	f
22818	ФПИ и КТ	1	52354	62371	f
22819	ФПИ и КТ	2	52353	62371	f
22820	ФПИ и КТ	3	52352	62371	f
22821	ФПИ и КТ	4	36208	62371	f
22822	ФПИ и КТ	1	36213	62315	f
22823	ФПИ и КТ	2	36212	62315	f
22824	ФПИ и КТ	1	57876	62383	f
22825	ФПИ и КТ	2	57875	62383	f
22826	ФПИ и КТ	3	57874	62383	f
22827	ФПИ и КТ	4	53991	62383	f
22828	ФПИ и КТ	5	53683	62383	f
22829	ФПИ и КТ	6	52372	62383	f
22830	ФПИ и КТ	7	36220	62383	f
22831	ФПИ и КТ	8	36218	62383	f
22832	ФПИ и КТ	9	36217	62383	f
22833	ФПИ и КТ	10	36216	62383	f
22834	ФПИ и КТ	11	36214	62383	f
22835	ФПИ и КТ	12	34378	62383	f
22836	ФПИ и КТ	13	18065	62383	f
22837	ФПИ и КТ	14	18053	62383	f
22838	ФПИ и КТ	15	18032	62383	f
22839	ФПИ и КТ	1	57873	62382	f
22840	ФПИ и КТ	2	53684	62382	f
22841	ФПИ и КТ	3	53678	62382	f
22842	ФПИ и КТ	4	36223	62382	f
22843	ФПИ и КТ	5	31765	62382	f
22844	ФПИ и КТ	1	57872	62381	t
22845	ФПИ и КТ	2	53698	62381	t
22846	ФПИ и КТ	3	52349	62381	t
22847	ФПИ и КТ	4	36228	62381	t
22848	ФПИ и КТ	5	36227	62381	t
22849	ФПИ и КТ	6	36225	62381	t
22850	ФПИ и КТ	7	31762	62381	t
22851	ФПИ и КТ	8	18061	62381	t
22855	ФПИ и КТ	1	53698	62378	f
22856	ФПИ и КТ	2	36230	62378	f
22857	ФПИ и КТ	3	36229	62378	f
22858	ФПИ и КТ	4	18072	62378	f
22859	ФПИ и КТ	5	18061	62378	f
22860	ФПИ и КТ	1	57872	62377	t
22861	ФПИ и КТ	2	52349	62377	t
22862	ФПИ и КТ	3	36225	62377	t
22863	ФПИ и КТ	4	31765	62377	t
22864	ФПИ и КТ	5	31762	62377	t
22867	ФПИ и КТ	3	31766	62376	f
22868	ИМ	1	58143	62301	f
22869	ФПИ и КТ	2	57883	62301	f
22870	ФПИ и КТ	3	57882	62301	f
22871	ФПИ и КТ	4	57879	62301	f
22872	ФПИ и КТ	5	57877	62301	f
22873	ФПИ и КТ	6	57872	62301	f
22874	ФПИ и КТ	7	53691	62301	f
22875	ФПИ и КТ	8	53686	62301	f
22876	ФПИ и КТ	9	52376	62301	f
22877	ФПИ и КТ	10	52375	62301	f
22878	ФПИ и КТ	11	38205	62301	f
22879	ФПИ и КТ	12	37120	62301	f
22880	ФПИ и КТ	13	36228	62301	f
22881	ФПИ и КТ	14	36227	62301	f
22882	ФПИ и КТ	15	36225	62301	f
22883	ФПИ и КТ	16	31762	62301	f
22884	ФПИ и КТ	17	18078	62301	f
22885	ФПИ и КТ	18	18065	62301	f
22886	ФПИ и КТ	1	52349	62300	t
22887	ФПИ и КТ	2	36216	62300	t
22888	ФПИ и КТ	3	18079	62300	t
22889	ФПИ и КТ	4	18053	62300	t
22890	ФПИ и КТ	5	18032	62300	t
22891	ФПИ и КТ	1	57880	62286	f
22892	ФПИ и КТ	2	57877	62286	f
22893	ФПИ и КТ	3	57872	62286	f
22894	ФПИ и КТ	4	53693	62286	f
22895	ФПИ и КТ	5	36234	62286	f
22896	ФПИ и КТ	6	53687	62286	f
22897	ФПИ и КТ	7	53681	62286	f
22898	ФПИ и КТ	8	53680	62286	f
22899	ФПИ и КТ	9	53679	62286	f
22900	ФПИ и КТ	10	53677	62286	f
22852	ФПИ и КТ	1	36222	62380	t
22853	ФПИ и КТ	2	36221	62380	f
22865	ФПИ и КТ	1	53694	62376	t
22866	ФПИ и КТ	2	36222	62376	t
22901	ФПИ и КТ	11	53676	62286	f
22902	ФПИ и КТ	12	37122	62286	f
22903	ФПИ и КТ	13	36228	62286	f
22904	ФПИ и КТ	14	36227	62286	f
22905	ФПИ и КТ	15	36217	62286	f
22906	ФПИ и КТ	16	36197	62286	f
22907	ФПИ и КТ	17	21192	62286	f
22908	ФПИ и КТ	18	18090	62286	f
22909	ФПИ и КТ	19	18089	62286	f
22910	ФПИ и КТ	20	18084	62286	f
22911	ФПИ и КТ	21	18065	62286	f
22912	ФПИ и КТ	22	18053	62286	f
22913	ФПИ и КТ	23	7841	62286	f
22914	ФПИ и КТ	24	5917	62286	f
22915	ФПИ и КТ	25	826	62286	f
22916	ИМ	1	54859	62283	f
22917	ИМ	2	54764	62283	f
22918	ФизФ	1	56178	62282	f
22919	ФизФ	2	56176	62282	f
22920	ФПИ и КТ	1	52349	62281	t
22921	ФПИ и КТ	2	37120	62281	t
22922	ФПИ и КТ	3	36233	62281	t
22923	ФПИ и КТ	4	36225	62281	t
22924	ФПИ и КТ	5	18094	62281	t
22925	ФПИ и КТ	6	18079	62281	t
22926	ФПИ и КТ	7	18032	62281	t
22927	ФПИ и КТ	8	5902	62281	t
22928	ФПИ и КТ	9	3312	62281	t
22929	ФПИ и КТ	1	57886	62279	f
22930	ФПИ и КТ	2	57884	62279	f
22931	ФПИ и КТ	3	57881	62279	f
22932	ФПИ и КТ	4	57872	62279	f
22933	ФПИ и КТ	5	53991	62279	f
22934	ФПИ и КТ	6	52344	62279	f
22935	ФПИ и КТ	7	52343	62279	f
22936	ФПИ и КТ	8	52342	62279	f
22937	ФПИ и КТ	9	52341	62279	f
22938	ФПИ и КТ	10	52340	62279	f
22939	ФПИ и КТ	11	52339	62279	f
22940	ФПИ и КТ	12	52338	62279	f
22941	ФПИ и КТ	13	57885	62279	f
22942	ФПИ и КТ	14	52337	62279	f
22943	ФПИ и КТ	15	52335	62279	f
22944	ФПИ и КТ	16	52334	62279	f
22945	ФПИ и КТ	17	36243	62279	f
22946	ФПИ и КТ	18	36239	62279	f
22947	ФПИ и КТ	19	36241	62279	f
22948	ФПИ и КТ	20	36240	62279	f
22949	ФПИ и КТ	21	18102	62279	f
22950	ФПИ и КТ	22	18065	62279	f
22951	ФПИ и КТ	23	18032	62279	f
22952	ФПИ и КТ	1	53678	62277	t
22953	ФПИ и КТ	2	36228	62277	t
22954	ФПИ и КТ	3	36227	62277	t
22955	ФПИ и КТ	4	36225	62277	t
22956	ФПИ и КТ	5	18078	62277	t
22957	ФПИ и КТ	1	59495	62384	f
22958	ФПИ и КТ	1	36261	62385	f
22959	ФПИ и КТ	1	36263	62386	f
\.
COPY s335141.discp_starts (id, id_discp_module, sem) FROM stdin;
16260	18757	1
16261	18757	2
16262	18757	3
16263	18758	1
16264	18759	1
16265	18760	1
16266	18761	1
16267	18762	1
16268	18763	2
16269	18764	1
16270	18765	2
16271	18766	1
16272	18767	3
16273	18768	2
16274	18769	1
16275	18770	3
16276	18771	3
16277	18772	2
16278	18773	2
16279	18774	1
16280	18774	2
16281	18775	2
16282	18776	2
16283	18777	3
16284	18778	3
16285	18779	3
16286	18780	2
16287	18781	2
16288	18782	1
16289	18783	3
16290	18784	3
16291	18785	3
16292	18786	3
16293	18787	2
16294	18788	2
16295	18789	1
16296	18790	3
16297	18791	4
16298	18792	4
16299	18793	4
18906	21302	1
18907	21303	1
18908	21304	1
18909	21305	1
18910	21306	1
18911	21307	3
18912	21308	1
18913	21309	1
18914	21310	1
18915	21311	1
18916	21312	1
18917	21313	2
18918	21314	3
18919	21315	4
19393	21741	3
19394	21742	3
19395	21743	7
19396	21744	1
19397	21745	1
19398	21746	6
19399	21747	1
19400	21748	1
19401	21749	1
19402	21750	1
19403	21751	1
19404	21752	1
19405	21753	1
19406	21754	3
19407	21755	3
19408	21756	3
19409	21757	3
19410	21758	3
19411	21759	3
19412	21760	3
19413	21761	3
19414	21762	3
19415	21763	3
19416	21764	3
19417	21765	3
19418	21766	3
19419	21767	3
19420	21768	5
19421	21769	5
19422	21770	5
19423	21771	5
19424	21772	5
19425	21773	5
19426	21774	5
19427	21775	5
19428	21776	5
19429	21777	5
19430	21778	5
19431	21779	5
19432	21780	5
19433	21781	5
19434	21782	5
19435	21783	5
19436	21784	5
18938	21334	3
18939	21335	4
18940	21336	4
18941	21337	2
18942	21338	8
18943	21339	1
18944	21340	2
18945	21341	2
18946	21342	1
18947	21343	3
18948	21344	1
18949	21345	1
19437	21785	5
19438	21786	6
19439	21787	6
19440	21788	6
19441	21789	6
19442	21790	6
19443	21791	6
19444	21792	6
19445	21793	3
19446	21794	2
19447	21795	3
19448	21796	1
19449	21797	2
19450	21798	5
19451	21799	5
19452	21800	1
19453	21801	2
19454	21802	1
19455	21803	2
19456	21804	1
19457	21805	1
19458	21806	1
19459	21807	1
19460	21808	2
19461	21809	5
19462	21809	6
19463	21810	5
19464	21810	6
19465	21811	5
19466	21811	6
19467	21812	5
19468	21812	6
19469	21813	5
19470	21813	6
19471	21814	5
19472	21814	6
19473	21815	5
19474	21815	6
19475	21816	5
19476	21816	6
19477	21817	5
19478	21817	6
19479	21818	2
19480	21819	3
19481	21820	4
19482	21821	2
19483	21822	3
19484	21823	4
19485	21824	5
19486	21825	3
19487	21826	4
19488	21827	5
19489	21828	4
19490	21829	5
19491	21830	2
19492	21831	2
19493	21832	3
19494	21833	3
19495	21834	4
19496	21835	4
19497	21836	4
19498	21837	7
19499	21838	4
19500	21839	5
19501	21840	5
19502	21841	3
19503	21842	6
19504	21843	4
19505	21844	6
19506	21845	7
19507	21846	7
19508	21847	7
19509	21848	2
19510	21849	3
19511	21850	6
7200	8911	1
7201	8912	1
7202	8913	1
7203	8914	1
7204	8915	1
7205	8916	1
7206	8917	1
7207	8918	1
7208	8919	2
7209	8920	2
19512	21851	5
19513	21852	7
19514	21853	6
19515	21854	5
19516	21855	7
19517	21856	6
19518	21857	7
19519	21858	4
19520	21859	7
19521	21860	6
19522	21861	7
19523	21862	7
7222	8933	3
7223	8934	2
7224	8935	3
7225	8936	8
19524	21863	8
18950	21346	5
18951	21347	3
18952	21348	3
18953	21349	6
18954	21350	1
18955	21351	4
18956	21352	7
18957	21353	1
18958	21354	1
18959	21355	5
18960	21355	6
18961	21356	5
18962	21356	6
18963	21357	5
18964	21357	6
18965	21358	5
18966	21358	6
18967	21359	5
18968	21359	6
18969	21360	2
18970	21361	2
18971	21362	3
18972	21363	3
18973	21364	4
18974	21365	4
18975	21366	5
18976	21367	4
18977	21368	3
18978	21369	3
18979	21370	2
18980	21371	3
18981	21372	6
18982	21373	6
18983	21374	7
18984	21375	5
18985	21376	5
18986	21377	7
18987	21378	5
18988	21379	4
18989	21380	7
18990	21381	5
18991	21382	6
18992	21383	6
18993	21384	6
18994	21385	7
18995	21386	5
18996	21387	3
18997	21387	4
18998	21388	7
18999	21389	2
19000	21389	5
19001	21390	7
19002	21391	6
19003	21392	4
19004	21392	6
19005	21393	7
19006	21394	7
19007	21395	8
19008	21396	8
19009	21397	8
19010	21398	7
19011	21399	6
19012	21400	7
19013	21401	6
19014	21402	6
19015	21403	6
19016	21404	5
19017	21405	4
19018	21406	7
19019	21407	7
19020	21408	5
19021	21408	7
19022	21409	8
19023	21410	8
19024	21411	8
19025	21412	7
19026	21413	5
19027	21414	6
19028	21415	7
19029	21416	6
19030	21417	6
19031	21418	5
19032	21419	8
19033	21420	7
19034	21421	5
19035	21422	4
19036	21423	7
19037	21424	5
19038	21424	7
19039	21425	7
19040	21426	4
19041	21427	2
19042	21427	5
19043	21428	6
19044	21429	7
19045	21430	5
19046	21430	7
19047	21431	7
19048	21432	7
19049	21433	4
19050	21434	2
19051	21435	3
19052	21436	7
19053	21437	6
19054	21438	4
19525	21864	8
19526	21865	8
19527	21866	6
19528	21867	7
19529	21868	6
19530	21869	7
19531	21870	7
19532	21871	6
19533	21872	7
19534	21873	5
19535	21874	4
19536	21875	7
19055	21439	6
19056	21440	7
19057	21441	6
19058	21442	5
19059	21443	5
19060	21444	4
19061	21445	3
19062	21446	8
19063	21447	3
19064	21448	4
19065	21449	7
19066	21450	7
19067	21451	4
19068	21452	5
19069	21453	5
19070	21454	4
19071	21455	7
19072	21456	2
19537	21876	8
19538	21877	8
19539	21878	6
19540	21879	8
19541	21880	5
19542	21881	6
19543	21882	7
19073	21456	5
19074	21457	2
19075	21457	4
19076	21457	6
19077	21458	7
19078	21459	5
19079	21460	5
19080	21461	5
19544	21883	6
19545	21884	7
19546	21885	7
19547	21886	3
19548	21887	6
19549	21888	2
19550	21889	5
19551	21890	7
19081	21461	7
19082	21462	5
19083	21462	6
19084	21463	7
19085	21464	5
19086	21465	7
19087	21466	4
19088	21467	6
19089	21468	6
19090	21469	6
19091	21470	4
19092	21470	6
19093	21471	4
19094	21472	4
19095	21473	5
19096	21474	5
19097	21475	6
19098	21476	6
19099	21477	7
19100	21478	4
19101	21479	8
19102	21480	7
19103	21481	6
19104	21482	6
19105	21483	5
19106	21484	4
19107	21485	5
19108	21486	2
19109	21487	3
19110	21488	3
19111	21489	2
19112	21490	3
19113	21491	3
19114	21492	4
19115	21492	6
19116	21493	4
19117	21493	6
19118	21494	2
19119	21494	4
19120	21494	6
19121	21495	4
19122	21495	6
19123	21496	7
19124	21497	7
19125	21498	7
19126	21499	7
19127	21500	8
19128	21501	8
19129	21502	8
19370	21719	7
19371	21720	4
19372	21720	6
19373	21721	3
19374	21722	3
19375	21723	6
19376	21724	5
19377	21725	4
19378	21726	3
19379	21727	7
19380	21728	5
19381	21729	6
19382	21730	4
19383	21731	7
19384	21732	3
19385	21733	7
19386	21734	4
19387	21735	5
19388	21736	5
19389	21737	7
19390	21738	8
19391	21739	8
19392	21740	8
19552	21891	4
19553	21892	7
19554	21893	6
19555	21894	5
19556	21894	7
19557	21895	3
19558	21896	7
7419	9112	8
7420	9113	8
7421	9114	8
7422	9115	8
7423	9116	7
7424	9117	7
7425	9118	7
7426	9119	8
7427	9120	8
7428	9121	7
7429	9122	8
19672	22003	3
19673	22004	4
19674	22005	3
19675	22006	4
19676	22007	3
19677	22008	4
19678	22009	3
19679	22010	4
19680	22011	3
19681	22012	4
19682	22013	3
19559	21897	7
19560	21898	4
19561	21899	7
19562	21900	8
19563	21901	4
19564	21902	5
19565	21903	4
19566	21904	4
19567	21905	4
19568	21906	3
19569	21907	5
19570	21908	6
19571	21909	6
19572	21910	7
19573	21911	7
19574	21912	3
19575	21913	2
19576	21914	4
19577	21915	7
19578	21916	7
19579	21917	6
19580	21918	4
19581	21919	7
19582	21920	6
19583	21921	5
19584	21922	7
19585	21923	5
19586	21924	2
19587	21925	3
19588	21926	3
19589	21927	3
19590	21928	4
19591	21929	5
19592	21930	6
19593	21931	7
19594	21932	5
19595	21933	7
19596	21934	7
19597	21935	5
19598	21936	6
19599	21937	5
19600	21938	5
19601	21938	7
19602	21939	2
19603	21939	4
19604	21939	6
19605	21940	2
19606	21940	4
19607	21941	7
19608	21942	6
19609	21943	6
19610	21944	7
19611	21944	5
19612	21945	7
19613	21946	7
19614	21947	3
19615	21948	4
19616	21949	5
19617	21950	6
19618	21951	4
19619	21952	8
19620	21953	2
19621	21954	2
19622	21955	2
19623	21956	2
19624	21957	2
19625	21958	3
19626	21959	3
19627	21960	4
19628	21961	4
19629	21962	6
19683	22014	4
19684	22015	7
19685	22016	3
19686	22017	1
19687	22018	1
19688	22019	6
19689	22020	1
19690	22021	1
19691	22022	1
19692	22023	1
19693	22024	1
19694	22025	1
19695	22026	1
19130	21503	1
19131	21504	1
19132	21505	1
19133	21506	1
19134	21507	1
19135	21508	1
19136	21509	1
19137	21510	1
19138	21511	1
19139	21512	2
19140	21513	1
19141	21514	2
19142	21515	3
19143	21516	3
19144	21517	3
19145	21518	3
19146	21519	3
19147	21520	3
19148	21521	3
19149	21522	3
19150	21523	3
19151	21524	3
19152	21525	3
19153	21526	3
19154	21527	3
19155	21528	3
19156	21529	5
19157	21530	5
19158	21531	5
19159	21532	5
19160	21533	5
19161	21534	5
19162	21535	5
19163	21536	5
19164	21537	5
19165	21538	5
19166	21539	5
19167	21540	5
19168	21541	5
19169	21542	5
19170	21543	5
19171	21544	5
19172	21545	5
19173	21546	5
19174	21547	4
19175	21548	4
19176	21549	4
19177	21550	4
19178	21551	4
19179	21552	4
19180	21553	4
19181	21554	4
19182	21555	3
19183	21556	2
19184	21557	4
19185	21558	8
19186	21559	5
19187	21560	1
19188	21561	2
19189	21562	2
19190	21563	3
19191	21564	1
19192	21565	1
19193	21566	5
19194	21567	3
19195	21568	1
19196	21569	4
19197	21570	1
19198	21571	1
19199	21572	5
19200	21572	6
19201	21572	7
19202	21573	5
19203	21573	6
19204	21573	7
19205	21574	5
19206	21574	6
19207	21574	7
19208	21575	5
19209	21575	6
19210	21575	7
19211	21576	5
19212	21576	6
19213	21576	7
19214	21577	5
19215	21577	6
19216	21577	7
19217	21578	5
19218	21578	6
19219	21578	7
19220	21579	5
19221	21580	4
19222	21581	3
19223	21582	3
19224	21583	2
19225	21584	3
19226	21585	2
19227	21586	2
19228	21587	3
19696	22027	3
19697	22028	3
19698	22029	3
19699	22030	3
19700	22031	3
19701	22032	3
19702	22033	3
19703	22034	3
19704	22035	5
19705	22036	5
19706	22037	5
19707	22038	5
19708	22039	5
19709	22040	5
19710	22041	5
19711	22042	5
19712	22043	5
19713	22044	6
19714	22045	6
19715	22046	6
19716	22047	6
19717	22048	6
19718	22049	6
19719	22050	6
19720	22051	6
19721	22052	6
19722	22053	6
19723	22054	6
19724	22055	6
19725	22056	6
19726	22057	6
19727	22058	3
19728	22059	3
19729	22060	2
19730	22061	1
19731	22062	1
19732	22063	2
19733	22064	1
19734	22065	2
19735	22066	5
19736	22067	2
19737	22068	1
19738	22069	5
19739	22070	1
19740	22071	1
19741	22072	1
19742	22073	1
19743	22074	2
19744	22075	2
19745	22076	3
19746	22077	3
19747	22078	4
19748	22079	4
19749	22080	5
19750	22080	6
19751	22081	5
19752	22081	6
19753	22082	5
19754	22082	6
19755	22083	5
19756	22083	6
19757	22084	5
19758	22084	6
19759	22085	5
19760	22085	6
19761	22086	5
19762	22086	6
19763	22087	5
19764	22087	6
19765	22088	3
19766	22089	4
19767	22090	2
19768	22091	3
19769	22092	4
19770	22093	2
19771	22094	3
19772	22095	4
19773	22096	5
19774	22097	4
19775	22098	5
19776	22099	6
19777	22100	5
19778	22101	2
19779	22102	3
19780	22103	7
19781	22104	5
19229	21588	3
19230	21589	4
19231	21590	4
19232	21591	6
19233	21592	6
19234	21593	7
19235	21594	5
19236	21595	4
19237	21596	7
19238	21597	5
19239	21598	3
19240	21599	4
19241	21600	5
19242	21601	6
19630	21963	7
19631	21964	5
19632	21965	6
19633	21966	3
19634	21967	4
19635	21968	4
19636	21969	5
19637	21970	7
19638	21971	7
19639	21972	7
19640	21973	6
19641	21974	7
19642	21975	7
19643	21976	4
19644	21976	6
19645	21977	3
19646	21978	4
19647	21979	4
19648	21980	5
19649	21981	6
19650	21982	7
19651	21983	5
19652	21984	6
19653	21985	4
19654	21986	5
19655	21987	3
19656	21988	4
19657	21989	7
19658	21990	5
19659	21991	6
19660	21992	4
19661	21992	6
19662	21993	5
20641	22960	1
20642	22960	2
20643	22960	3
20644	22961	1
20645	22962	3
20646	22963	3
20647	22964	3
20648	22965	1
20649	22966	2
17836	20279	3
17837	20280	4
20650	22967	3
20651	22968	4
20652	22969	1
20653	22970	3
20654	22971	2
20655	22972	1
20656	22973	1
20657	22974	2
20658	22975	3
20659	22976	3
20660	22977	2
20661	22978	2
20662	22979	1
20663	22980	2
20664	22981	1
20665	22982	3
20666	22983	3
20667	22984	1
20668	22985	2
20669	22986	2
20670	22987	1
20671	22988	3
20672	22989	2
20673	22990	2
20674	22991	3
20675	22992	3
20676	22993	2
20677	22994	1
20678	22995	3
20679	22996	4
19663	21994	7
19664	21995	3
19665	21996	7
19666	21997	4
19667	21998	5
19668	21999	7
19669	22000	8
19670	22001	8
19671	22002	8
19782	22105	4
19783	22106	4
19784	22107	5
19785	22108	6
19786	22109	3
19787	22110	7
19788	22111	7
19789	22112	6
19790	22113	2
19791	22114	5
19792	22115	4
19793	22116	6
19794	22117	6
19795	22118	6
19796	22119	7
19797	22120	7
19798	22121	7
19799	22122	4
19800	22123	6
19801	22124	5
19802	22125	6
19803	22126	7
19804	22127	8
19805	22128	8
19806	22129	8
19807	22130	7
19808	22131	6
19809	22132	7
19810	22133	7
19811	22134	6
19812	22135	7
19813	22136	6
19814	22137	6
19815	22138	5
19816	22139	8
19817	22140	8
19818	22141	8
19819	22142	5
19820	22143	6
19821	22144	8
19822	22145	5
19823	22146	4
19824	22147	6
19825	22148	6
19826	22149	5
19827	22150	6
19828	22151	7
19829	22152	5
19830	22153	7
19831	22154	7
19832	22155	2
19833	22156	6
19834	22157	7
19835	22158	2
19836	22159	4
19837	22160	7
19838	22161	4
19839	22162	7
19840	22163	7
19841	22164	2
19842	22165	8
19843	22166	6
19844	22167	7
19845	22168	6
19846	22169	5
19847	22170	4
19848	22171	4
19849	22172	7
19850	22173	3
19851	22174	2
19852	22175	5
19853	22176	7
19854	22177	4
19855	22178	4
19856	22179	2
19857	22180	7
19858	22181	6
19859	22182	7
19860	22183	6
19861	22184	4
19862	22185	3
19863	22186	7
19864	22187	4
19865	22188	3
19866	22189	2
19867	22190	5
19868	22191	2
19869	22192	3
20680	22997	4
20681	22998	4
20437	22756	1
20438	22757	1
20439	22758	1
20440	22759	1
20441	22760	1
20442	22761	1
20443	22762	1
20444	22763	3
20445	22764	3
20446	22765	3
20447	22766	3
20448	22767	3
20449	22768	3
20450	22769	3
20451	22770	3
20452	22771	5
20453	22772	5
20454	22773	5
20455	22774	5
20456	22775	5
20457	22776	5
19870	22193	5
19871	22194	6
19872	22195	7
19873	22196	7
19874	22197	5
19875	22198	6
19876	22199	3
19877	22200	4
19878	22201	5
19879	22202	7
19880	22203	4
19881	22204	6
19882	22205	6
19883	22206	7
19884	22207	2
19885	22208	7
19886	22209	7
19887	22210	7
19888	22211	6
19889	22212	7
19890	22213	5
19891	22214	6
19892	22215	5
19893	22216	6
19894	22217	3
19895	22218	4
19896	22219	2
19897	22220	3
19898	22221	3
19899	22222	4
19900	22223	5
19901	22224	6
19902	22225	8
19903	22226	2
19904	22227	2
19905	22228	4
19906	22229	2
19907	22230	4
19908	22231	7
19909	22232	4
19910	22233	6
19911	22234	5
19912	22235	6
19913	22236	7
19914	22237	8
19915	22238	8
19916	22239	8
20458	22777	5
20459	22778	5
20460	22779	5
20461	22780	6
20462	22781	6
20463	22782	6
20464	22783	6
20465	22784	6
20466	22785	6
20467	22786	6
20468	22787	6
20469	22788	6
20470	22789	6
20471	22790	6
20472	22791	6
20473	22792	6
20474	22793	6
20475	22794	6
20476	22795	3
20477	22796	3
20478	22797	2
20479	22798	1
20480	22799	2
20481	22800	1
20482	22801	2
20483	22802	1
20484	22803	1
20485	22804	6
20486	22805	4
20487	22806	2
20488	22807	1
20489	22808	1
20490	22809	3
20491	22810	3
20492	22811	2
20493	22812	5
20494	22813	1
20495	22814	1
20496	22815	3
20497	22816	2
20498	22817	4
20499	22818	4
20500	22819	3
20501	22820	2
20502	22821	5
20503	22822	5
20504	22823	4
20505	22824	6
20506	22825	7
20507	22826	7
20508	22827	2
20509	22828	5
20510	22829	3
20511	22830	7
20512	22831	6
20513	22832	5
20514	22833	4
20515	22834	5
20516	22835	6
20517	22836	5
20518	22837	7
20519	22838	2
20520	22839	7
20521	22840	6
20522	22841	4
20523	22842	6
20524	22843	6
20525	22844	6
20526	22845	7
20527	22846	7
20528	22847	7
20529	22848	4
20530	22849	6
20531	22850	5
20532	22851	6
20533	22852	8
20534	22853	8
20535	22854	8
20536	22855	7
20537	22856	7
20538	22857	6
20539	22858	7
20540	22859	6
20541	22860	6
20542	22861	7
20543	22862	6
20544	22863	6
20545	22864	5
20546	22865	8
20547	22866	8
20548	22867	8
19958	22279	1
19959	22279	2
19960	22279	3
19961	22280	1
19962	22281	3
19963	22282	3
19964	22283	3
19965	22284	1
19966	22285	2
19969	22288	3
19970	22289	2
19971	22290	1
19972	22291	1
19973	22292	1
19974	22293	2
19975	22294	3
19976	22295	3
19977	22296	2
19978	22297	2
19979	22298	1
19980	22299	2
19981	22300	1
19982	22301	3
19983	22302	3
19984	22303	2
19985	22304	2
19986	22305	1
19987	22306	3
19988	22307	2
19989	22308	1
19990	22309	2
19991	22310	3
19992	22311	3
20420	22739	3
20421	22740	4
20422	22741	3
20423	22742	4
20424	22743	3
20425	22744	4
20426	22745	3
20427	22746	4
20428	22747	3
20429	22748	4
20430	22749	3
20431	22750	4
20432	22751	7
20433	22752	3
20434	22753	1
20435	22754	1
20436	22755	5
19243	21602	7
19244	21603	6
19245	21604	6
19246	21605	7
19247	21606	4
19248	21607	4
19249	21608	7
19250	21609	7
19251	21610	6
19252	21611	4
19253	21611	6
19254	21612	7
19255	21613	7
19256	21614	8
19257	21615	8
19258	21616	8
19259	21617	7
19260	21618	6
19261	21619	7
19262	21620	6
19263	21621	6
19264	21622	6
19265	21623	4
19266	21624	4
19267	21625	7
19268	21626	7
19269	21627	5
19270	21627	7
19271	21628	8
19272	21629	8
19273	21630	8
19274	21631	7
19275	21632	5
19276	21633	5
19277	21634	6
19278	21635	6
19279	21636	4
19280	21637	6
19281	21638	8
19282	21639	7
19283	21640	5
19284	21641	4
19285	21642	7
19286	21643	6
19287	21644	7
19288	21645	5
19289	21645	7
19290	21646	7
19291	21647	4
19292	21648	7
19293	21649	5
19294	21649	7
19295	21650	3
19296	21651	7
19297	21652	6
19298	21653	7
19299	21654	6
19300	21655	6
19301	21656	5
19302	21657	6
19303	21658	7
19304	21659	4
19305	21660	7
19306	21661	6
19307	21662	4
19308	21663	7
19309	21664	6
19310	21665	5
19311	21666	4
19312	21667	8
19313	21668	3
19314	21669	4
19315	21670	7
19316	21671	7
19317	21672	4
19318	21673	5
19319	21674	4
19320	21675	5
19321	21676	7
19322	21677	2
19323	21678	3
19324	21679	4
19325	21680	5
19326	21681	6
19327	21682	5
19328	21683	5
19329	21684	5
19330	21684	7
19331	21685	3
19332	21686	7
19333	21687	5
19334	21688	7
19335	21689	4
19336	21690	6
19337	21691	4
19338	21691	6
19339	21692	6
19340	21693	6
19341	21694	4
19342	21694	6
19343	21695	7
19344	21696	3
19345	21697	5
19346	21698	8
19347	21699	2
19348	21700	2
19349	21701	3
19350	21702	4
19351	21703	4
19352	21704	5
19353	21705	5
19354	21706	6
19355	21707	6
19356	21708	7
19357	21709	6
19358	21710	7
19359	21711	4
19360	21712	7
19361	21713	5
19362	21714	3
19363	21715	5
19364	21715	7
19365	21716	4
19366	21716	6
19367	21717	4
19368	21717	6
19369	21718	7
20549	22868	6
20550	22869	6
20551	22870	7
20552	22871	6
20553	22872	8
20554	22873	3
20555	22874	5
20556	22875	4
20557	22876	7
20558	22877	6
20559	22878	5
20560	22879	7
20561	22880	7
20562	22881	4
20563	22882	6
20564	22883	5
20565	22884	7
20566	22885	2
20567	22886	7
20568	22887	4
20569	22888	7
20570	22889	7
20571	22890	2
20572	22891	6
20573	22892	8
20574	22893	7
20575	22894	6
20576	22895	7
20577	22896	5
20578	22897	4
20579	22898	4
20580	22899	7
20581	22900	3
20582	22901	2
20583	22902	5
20584	22903	7
20585	22904	4
20586	22905	4
20587	22906	2
20588	22907	6
20589	22908	7
20590	22909	6
20591	22910	4
20592	22911	5
20593	22912	7
20594	22913	3
20595	22914	4
20596	22915	5
20597	22916	2
20598	22917	3
20599	22918	6
20600	22919	5
20601	22920	7
20602	22921	7
20603	22922	5
20604	22923	6
20605	22924	5
20606	22925	7
20607	22926	4
20608	22927	6
20609	22928	6
20610	22929	3
20611	22930	2
20612	22931	2
20613	22932	4
20614	22933	2
20615	22934	7
20616	22935	7
20617	22936	7
20618	22937	7
20619	22938	6
20620	22939	6
20621	22940	5
20622	22941	5
20623	22942	6
20624	22943	4
20625	22944	3
20626	22945	4
20627	22946	3
20628	22947	6
20629	22948	5
20630	22949	8
20631	22950	2
20632	22951	4
20633	22952	4
20634	22953	7
20635	22954	4
20636	22955	6
20637	22956	7
20638	22957	8
20639	22958	8
20640	22959	8
\.
COPY s335141.groups (id) FROM stdin;
\.
COPY s335141.memorandums (id, date, link) FROM stdin;
1	2025-04-03	2025-04-03
2	2025-04-03	link
42	0222-02-22	22
43	0333-03-31	33
44	0222-02-22	222
45	0444-04-04	4
46	0333-03-31	3
47	4444-04-04	4
48	4444-04-04	4
49	4444-04-04	4
50	4444-04-04	4
51	4444-04-04	4
52	4444-04-04	4
53	4444-04-04	4
54	4444-04-04	4
55	4444-04-04	4
56	4444-04-04	4
57	4444-04-04	4
58	4444-04-04	4
59	4444-04-04	4
60	4444-04-04	4
61	4444-04-04	4
62	4444-04-04	4
63	4444-04-04	4
64	4444-04-04	4
65	4444-04-04	4
66	0333-03-31	333
67	0333-03-31	333
68	5555-05-05	55
69	0444-04-04	4
70	5555-05-05	5
71	0444-04-04	4
72	0055-05-05	55
73	0055-05-05	55
74	0444-04-04	4
75	0555-05-05	55
76	0055-05-05	55
77	0055-05-05	555
78	0005-05-05	5
79	0666-06-06	6
80	0044-04-04	44
81	0066-06-06	66
82	4444-04-04	4
83	0055-05-05	5
84	0066-06-06	66
85	0055-05-05	55
86	6666-06-06	6
87	0666-06-06	66
88	2025-02-22	testlink
89	0111-11-11	1
90	0003-03-31	33
91	0033-03-31	3
92	0033-03-31	33
93	0444-04-04	44
94	0044-04-04	4
95	0055-05-05	55
96	3003-03-30	link
97	2025-05-24	null
98	2025-05-24	link
99	2025-05-24	link
100	0033-03-31	3
101	2025-05-24	null
102	2025-05-24	
103	0011-11-11	1
104	0001-11-11	1
105	0444-04-04	444
106	2025-05-24	l
122	0444-04-04	
\.
COPY s335141.modules (id_isu, name, choose_count, type_choose) FROM stdin;
22605	Иностранный язык 1-2 семестр	\N	все
22602	Иностранный язык	\N	все
22604	Иностранный язык 3-4 семестр	1	кол-во
12248	Специализация 1: Дизайн	\N	все
14925	Блок заменяемых дисциплин на выбор (Трек 1)	6	з.е.
12298	Специализация 2: Разработка графических и веб-приложений	\N	все
12345	Выбор на один семестр	12	з.е.
12256	Траектория UX/UI: Трек 3. Дизайн Графических интерфейсов	\N	все
12263	Блок заменяемых дисциплин на выбор (Трек 3) КТвД 23	6	з.е.
12301	Профессиональная подготовка (Трек 4) КТвД 23	\N	все
12312	Выбор дисциплин в осеннем семестре (Трек 4) КТвД 23	6	з.е.
12314	Выбор дисциплин в весеннем семестре (Трек 4) КТвД 23	6	з.е.
-100	Блок 1. Модули (дисциплины)	\N	все
-101	Универсальная (надпрофессиональная) подготовка	\N	все
-102	История России (1 сем.)	4	з.е.
-103	Культура безопасности жизнедеятельности	\N	все
-104	Физическая культура и спорт	\N	все
-105	Физическая культура и спорт (элективная)	\N	все
-106	Физическая культура и спорт (базовая)	\N	все
-107	Философия+Мышление	\N	все
50438	Иностранный язык (1 сем)	\N	все
50439	Иностранный язык (2 сем)	\N	все
22603	Иностранный язык (5-6 семестр)	1	кол-во
-108	Модуль "Предпринимательская культура"(бак. реализуется в 3 и 4 семестре)	2	кол-во
-109	Обязательная дисциплина "Предпринимательская культура  3 сем. бакалавриат "	\N	все
-110	Soft Skills бакалавриат (ТПВ в 3 семестре)	\N	все
-111	Защита и действия человека в условиях ЧС	\N	все
12246	Индивидуальная профессиональная подготовка	\N	все
12337	Обязательные дисциплины профессиональной подготовки	\N	все
12341	Общая профессиональная подготовка	\N	все
12338	Математический модуль	\N	все
12344	Цифровая культура в профессиональной деятельности	2	кол-во
12247	Выбор траектории	1	кол-во
12249	Обязательные дисциплины специализации Дизайн	\N	все
12250	Профессиональная подготовка по дизайну	\N	все
12251	Цифровая культура	\N	все
12252	Хранение и обработка данных	1	кол-во
12253	Прикладная статистика	1	кол-во
12254	Машинное обучение	1	кол-во
12255	Выбор траектории в специализации Дизайн	1	кол-во
12267	Траектории по 3D-моделированию: Треки 1 и 2	\N	все
12269	Обязательные дисциплины (Трек 1 и Трек 2)	\N	все
12271	Выбор траектории по 3D	1	кол-во
12273	Трек 1. Разработка компьютерных игр	\N	все
12274	Обязательные дисциплины (Трек 1)	\N	все
12285	Выбор предмета для подготовки финального проекта-портфолио (8 семестр)	1	кол-во
12289	Трек 2. 3D-визуализация	\N	все
12291	Обязательные дисциплины (Трек 2)	\N	все
12296	Выбор предмета для подготовки финального проекта-портфолио (8 семестр)	1	кол-во
12257	Обязательные дисциплины (Трек 3)	\N	все
12299	Обязательные дисциплины (трек 4)	\N	все
12304	Математика	\N	все
12309	Физика	\N	все
12310	Блок заменяемых дисциплин на выбор	\N	все
12340	Специализация 3: Компьютерная графика и мультимедиа в образовании (для направления подготовки 44.03.04)	\N	все
12355	Обязательные дисциплины по специализации 3	\N	все
12349	Цифровая культура	\N	все
12350	Хранение и обработка данных	1	кол-во
12352	Прикладная статистика	1	кол-во
12353	Машинное обучение	1	кол-во
15881	Выбор траектории в специализации Компьютерная графика и мультимедиа в образовании	1	кол-во
15882	Трек 5. Компьютерные игры в образовании	\N	все
15885	Обязательные дисциплины (Трек 5)	\N	все
12342	Блок заменяемых дисциплин на выбор (трек 5)	\N	все
12346	Выбор на два семестра	6	з.е.
15883	Трек 6. Искусственный интеллект в образовании	\N	все
15884	Обязательные дисциплины (Трек 6)	\N	все
-113	Производственная практика	\N	все
-114	Преддипломная практика	\N	все
-116	Государственная итоговая аттестация	\N	все
-118	Факультативные дисциплины ОП КТвД	\N	все
-119	Магистратура ОП Мультимедиа-технологии, дизайн и юзабилити	\N	все
-120	Обязательные дисциплины профессиональной подготовки ОП МТДиЮ	\N	все
-121	Выбор траектории ОП МТДиЮ	1	кол-во
-122	Дизайн человеко-компьютерных систем	\N	все
-123	Технологии трёхмерного моделирования и расширенной реальности	\N	все
5862	Пул дисциплин на выбор	1	кол-во
1	Module AB	10	все
-112	Блок 2. Практика	\N	все
-115	Блок 3. ГИА	\N	все
-117	Блок 4. Факультативные модули (дисциплины)	0	кол-во
5526	Выбор заменяемых дисциплин в весеннем семестре	2	кол-во
5527	Выбор заменяемых дисциплин в осеннем семестре	6	з.е.
4788	Блок 2. Практика	\N	все
13161	Практика (обязательная)	\N	все
12233	Универсальная (надпрофессиональная) подготовка	\N	все
4782	Блок 1. Модули (дисциплины)	\N	все
4761	Универсальная (надпрофессиональная) подготовка	\N	все
5091	История	1	кол-во
5092	Культура безопасности жизнедеятельности	\N	все
5093	Физическая культура и спорт	\N	все
5094	Мышление	\N	все
22601	Иностранный язык (1-4 семестр)	\N	все
50434	Иностранный язык (1 сем)	\N	все
50435	Иностранный язык (2 сем)	\N	все
50436	Иностранный язык (3 сем)	\N	все
50437	Иностранный язык (4 сем)	\N	все
5096	Технологическое предпринимательство	\N	все
5097	Soft Skills	\N	все
7321	Защита и действия человека в условиях ЧС	\N	все
5099	Профессиональная подготовка	\N	все
5665	Общая профессиональная подготовка	\N	все
5492	Математический модуль	1	кол-во
5126	Цифровая культура в профессиональной деятельности	2	кол-во
5127	Модуль специализации	1	кол-во
5493	Специализация 1: Дизайн	\N	все
5494	Цифровая культура	\N	все
5495	Вариант 1	1	кол-во
5496	Вариант 2	1	кол-во
5497	Вариант 3	1	кол-во
5498	Профессиональная подготовка по дизайну	\N	все
5499	Выбор траектории в специализации Дизайн	1	кол-во
5500	Траектории по 3D-моделированию: Трек 1 и 2	\N	все
5501	Обязательные дисциплины (Трек 1 и Трек 2)	\N	все
5502	Выбор траектории по 3D	1	кол-во
5503	Трек 1. Разработка компьютерных игр	\N	все
5504	Обязательные дисциплины (Трек 1)	\N	все
5505	Блок заменяемых дисциплин на выбор (Трек 1)	6	з.е.
5507	Выбор предмета для подготовки финального проекта-портфолио (8 семестр)	1	кол-во
5508	Трек 2. 3D-визулизация	\N	все
5509	Обязательные дисциплины (Трек 2)	\N	все
5510	Блок заменяемых дисциплин на выбор (Трек 2)	2	кол-во
5511	Выбор предмета для подготовки финального проекта-портфолио (8 семестр)	1	кол-во
5512	Траектория UX/UI: Трек 3. Дизайн графических интерфейсов	\N	все
5513	Обязательные дисциплины (Трек 3)	\N	все
5514	Блок заменяемых дисциплин на выбор	2	кол-во
5515	Специализация 2: Разработка графических и веб-приложений	\N	все
5516	Обязательные дисциплины (Трек 4)	\N	все
5517	Дисциплина по выбору	1	кол-во
5519	Пул дополнительных дисциплин в весеннем семестре	1	кол-во
5520	Специализация 3: Компьютерная графика и мультимедиа в образовании	\N	все
5521	Цифровая культура	\N	все
5522	Вариант 1	1	кол-во
5523	Вариант 2	1	кол-во
5524	Вариант 3	1	кол-во
5525	Обязательные дисциплины специализации	\N	все
4793	Блок 3. ГИА	\N	все
4795	Блок 4. Факультативные модули (дисциплины)	\N	любое
5518	Выбор заменяемых дисциплин в осеннем семестре	6	з.е.
12242	История России (1 сем.)	1	кол-во
12244	Культура безопасности жизнедеятельности	\N	все
12234	Физическая культура и спорт	\N	все
12235	Физическая культура и спорт (элективная)	\N	все
12236	Физическая культура и спорт (базовая)	\N	все
12240	Философия+Мышление	\N	все
12348	Блок заменяемых дисциплин на выбор (трек 6)	15	з.е.
12237	Модуль "Предпринимательская культура"(бак. реализуется в 3 и 4 семестре)	2	кол-во
12238	Дисциплина на выбор "Предпринимательская культура 4 сем. бакалавриат"	1	кол-во
12239	Обязательная дисциплина "Предпринимательская культура 3 сем. бакалавриат "	\N	все
12243	Soft Skills бакалавриат (ТПВ в 3 семестре)	\N	все
12245	Защита и действия человека в условиях ЧС	\N	все
12347	Производственная практика	\N	все
12351	Преддипломная практика	\N	все
12354	Государственная итоговая аттестация	\N	все
17444	Универсальный модуль (бак 2024/2025). ОП 09.03.04 Компьютерные технологии в дизайне	\N	все
17470	История России для 3 и 4 семестра (Компьютерные технологии в дизайне) 2024/2025 бакалавриат	\N	все
17468	Культура безопасности жизнедеятельности (бак 2024/2025). Дисциплина БЖД на 3 семестр и Защита и действия человека в условиях ЧС в 7 семестре	\N	все
17446	Физическая культура и спорт (бак 2024/2025). Базовая упаковка	\N	все
17466	Философия	\N	все
17454	Иностранный язык (бак 2024/2025)	\N	все
17455	Иностранный язык 1-2 семестр	1	кол-во
17461	Иностранный язык (5-6 семестр)	1	кол-во
17448	Предпринимательская культура (бак 24/25)	\N	все
17451	Предпринимательская культура (бак 2024/2025) дисциплины по выбору	1	кол-во
17450	Бизнес-модели основных секторов инновационной экономики	\N	все
17464	Soft Skills (бак 2024/2025). 2-3 семестр	\N	все
17472	Индивидуальная профессиональная подготовка КТвД 24	\N	все
17473	Обязательные дисциплины профессиональной подготовки КТвД 24	\N	все
17478	Введение в профессиональную подготовку КТвД 24	\N	все
17479	Общая профессиональная подготовка КТвД 24	\N	все
17475	Математика	\N	все
17477	Цифровая культура в профессиональной деятельности	2	кол-во
17480	Выбор траектории КТвД 24	1	кол-во
17481	Специализация 1: Дизайн ОП КТвД 24	\N	все
17482	Обязательные дисциплины специализации Дизайн КТвД 24	\N	все
17489	Профессиональная подготовка по дизайну КТвД 24	\N	все
17488	Модуль по рисунку и пластической анатомии КТвД 24	\N	все
17487	Модуль по композиции КТвД 24	\N	все
17490	Модуль по живописи КТвД 24	\N	все
17483	Цифровая культура	\N	все
17484	Хранение и обработка данных	1	кол-во
17486	Прикладная статистика	1	кол-во
17485	Машинное обучение	1	кол-во
17491	Выбор траектории в специализации Дизайн КТвД 24	1	кол-во
17492	Траектории по 3D-моделированию: Треки 1 и 2 КТвД 24	\N	все
17493	Обязательные дисциплины (Трек 1 и Трек 2) КТвД 24	\N	все
17494	Выбор траектории по 3D КТвД 24	1	кол-во
17495	Трек 1. Разработка компьютерных игр КТвД 24	\N	все
17497	Обязательные дисциплины (Трек 1) КТвД 24	\N	все
17496	Выбор предмета для подготовки финального проекта-портфолио (8 семестр) КТвД 24	1	кол-во
17499	Трек 2. 3D-визуализация КТвД 24	\N	все
17501	Обязательные дисциплины (Трек 2) КТвД 24	\N	все
17500	Выбор предмета для подготовки финального проекта-портфолио (8 семестр) КТвД 24	1	кол-во
17503	Траектория UX/UI: Трек 3. Дизайн Графических интерфейсов КТвД 24	\N	все
17505	Обязательные дисциплины (Трек 3) КТвД 24	\N	все
17504	Вероятность и статистика	\N	все
17506	Блок заменяемых дисциплин на выбор (Трек 3) КТвД 24	6	з.е.
17507	Специализация 2: Разработка графических и веб-приложений ОП КТвД 24	\N	все
17512	Обязательные дисциплины (трек 4) КТвД 24	\N	все
17510	Математический модуль от НОЦМ КТвД 24	\N	все
17508	Вероятность и статистика	\N	все
17509	Физика	\N	все
17513	Специализация 3: Компьютерная графика и мультимедиа в образовании ОП КТвД 24	\N	все
17529	Обязательные дисциплины специализации 3 КТвД 24	\N	все
17514	Цифровая культура	\N	все
17515	Хранение и обработка данных	1	кол-во
17517	Прикладная статистика	1	кол-во
17516	Машинное обучение	1	кол-во
17518	Выбор траектории в специализации Компьютерная графика и мультимедиа в образовании ОП КТвД 24	1	кол-во
12294	Блок заменяемых дисциплин на выбор (Трек 2)	9	з.е.
17511	Блок заменяемых дисциплин на выбор (Трек 4) КТвД 24	15	з.е.
17519	Трек 5. Компьютерные игры в образовании КТвД 24	\N	все
17520	Обязательные дисциплины (Трек 5) КТвД 24	\N	все
17521	Блок заменяемых дисциплин на выбор (трек 5) КТвД 24	\N	все
17525	Выбор на 1 семестр (Трек 5) КТвД 24	9	з.е.
17522	Выбор дисциплины на два семестра (трек 5) КТвД 24	1	кол-во
17523	История искусств КТвД 24	6	з.е.
17524	Основы рисунка (Трек 5) 2 семестра КТвД 24	6	з.е.
17526	Трек 6. Искусственный интеллект в образовании КТвД 24	\N	все
17527	Обязательные дисциплины (Трек 6) КТвД 24	\N	все
17528	Блок заменяемых дисциплин на выбор (трек 6) КТвД 24	12	з.е.
17531	Производственная практика	\N	все
17530	Преддипломная практика	\N	все
17532	Государственная итоговая аттестация	\N	все
17457	Иностранный язык 3-4 семестр	1	кол-во
54529	История России и мира в ХХ веке	\N	все
54528	Социальная история России	\N	все
54527	История российской науки и техники	\N	все
54526	История русской культуры в контексте мировой культуры	\N	все
51854	Культура безопасности жизнедеятельности	\N	все
51853	Физическая культура и спорт	\N	все
51199	Философия	\N	все
56428	Иностранный язык (бакалавриат)	\N	все
56431	Иностранный язык 1-2 семестр	6	з.е.
56430	Иностранный язык 3-4 семестр	6	з.е.
56429	Иностранный язык (5-6 семестр)	6	з.е.
51847	Предпринимательская культура	\N	все
51849	Дисциплина на выбор "Предпринимательская культура 6 сем. бакалавриат"	1	кол-во
17404	Универсальный модуль (маг 2024/2025) для ОП ПИиКТ	\N	все
17459	Soft Skills для всех ОП факультета ПИиКТ (маг 2024/2025)	1	кол-во
17462	Soft Skills для всех ОП факультета ПИиКТ микромодули	3	з.е.
17460	Soft Skills для всех ОП факультета ПИиКТ без микромодулей	1	кол-во
17452	Мировоззренческий модуль	1	кол-во
17458	Мышление	3	з.е.
17456	Предпринимательская культура (маг 2024/2025) RU/ENG. Кастомная упаковка	1	кол-во
17453	Креативные технологии (маг 2024/2025). Базовая упаковка	1	кол-во
17445	Иностранный язык (маг 2024/2025)	\N	все
17447	Иностранный язык (маг 2024/2025). 1 семестр	1	кол-во
17449	Иностранный язык (маг 2024/2025). 2 семестр	1	кол-во
17405	Прикладной искусственный интеллект	1	кол-во
17406	Прикладной ИИ (Базовый трек 1)	\N	все
17407	Прикладной ИИ (Базовый трек 1, семестр 1)	1	кол-во
17408	Прикладной ИИ (Базовый трек 1, семестр 2)	1	кол-во
17396	Индивидуальная профессиональная подготовка МТДиЮ 24	\N	все
17397	Обязательные дисциплины профессиональной подготовки МТДиЮ 24	\N	все
17398	Выбор траектории МТДиЮ 24	1	кол-во
17399	Дизайн человеко-компьютерных систем МТДиЮ 24	\N	все
17401	Обязательные дисциплины ДЧКС МТДиЮ 24	\N	все
17400	Дисциплины по выбору для ДЧКС МТДиЮ 24	2	кол-во
17403	Технологии трёхмерного моделирования и расширенной реальности МТДиЮ 24	\N	все
17467	Научно-исследовательская работа	\N	все
17465	Производственная практика	\N	все
17463	Преддипломная практика	\N	все
17469	Государственная итоговая аттестация	\N	все
17502	Блок заменяемых дисциплин на выбор (Трек 2) КТвД 24	6	з.е.
4794	Государственная итоговая аттестация	\N	все
6161	Универсальная (надпрофессиональная) подготовка	\N	все
54525	История России	1	кол-во
54531	Реформы и реформаторы в истории России	\N	все
54530	Россия в истории современных международных отношений	\N	все
51852	Стартап-трек	1	кол-во
51851	Проектный трек	1	кол-во
51850	Функциональный трек	1	кол-во
51844	Обязательная дисциплина "Предпринимательская культура 3 сем. бакалавриат "	\N	все
55483	Soft Skills (бак 2025). 2-3 семестр	\N	все
8051	Профессиональная подготовка	\N	все
50177	Физико-математический модуль	\N	все
54459	Математика	\N	все
54461	Математика (1 семестр)	\N	все
54460	Математика (2 семестр)	\N	все
50228	Профессиональный модуль	\N	все
52680	Обязательные дисциплины профессиональной подготовки КТвД 25	\N	все
52694	Введение в профессиональную подготовку КТвД 25	\N	все
52689	Общая профессиональная подготовка КТвД 25	\N	все
56432	Цифровая культура КТвД 25	\N	все
56433	Хранение и обработка данных. ЦК КТвД 25	1	кол-во
56434	Прикладная статистика. ЦК КТвД 25	1	кол-во
56435	Машинное обучение. ЦК КТвД 25	1	кол-во
52728	Цифровая культура в профессиональной деятельности КТвД 25	2	кол-во
52679	Выбор траектории КТвД 25	1	кол-во
52734	Специализация 1: Дизайн (Треки 1, 2, 3) КТвД 25	\N	все
52736	Обязательные дисциплины специализации Дизайн КТвД 25	\N	все
52740	Базовая подготовка по дизайну КТвД 25	\N	все
52739	Модуль по композиции КТвД 25	\N	все
52738	Модуль по рисунку и пластической анатомии КТвД 25	\N	все
52737	Модуль по живописи КТвД 25	\N	все
52735	Выбор траектории в специализации Дизайн КТвД 25	1	кол-во
52747	Траектории по 3D-моделированию: Треки 1 и 2. КТвД 25	\N	все
52758	Обязательные дисциплины (Трек 1 и Трек 2) КТвД 25	\N	все
52748	Выбор траектории по 3D КТвД 25	1	кол-во
52750	Трек 1. Дизайн компьютерных игр КТвД 25	\N	все
52757	Обязательные дисциплины (Трек 1) КТвД 25	\N	все
52756	Блок заменяемых дисциплин на выбор (Трек 1) КТвД 25	6	з.е.
52755	Выбор предмета для подготовки финального проекта-портфолио КТвД 25	1	кол-во
52749	Трек 2. 3D-визуализация КТвД 25	\N	все
52754	Обязательные дисциплины (Трек 2) КТвД 25	\N	все
52753	Блок заменяемых дисциплин на выбор (Трек 2) КТвД 25	6	з.е.
52751	Выбор предмета для подготовки финального проекта-портфолио КТвД 25	1	кол-во
52743	Траектория по UX/UI: Трек 3. Дизайн графических интерфейсов КТвД 25	\N	все
52745	Обязательные дисциплины (Трек 3) КТвД 25	\N	все
52744	Блок заменяемых дисциплин на выбор (Трек 3) КТвД 25	9	з.е.
52729	Специализация 2: Разработка графических и веб-приложений (Трек 4) КТвД 25	\N	все
52733	Обязательные дисциплины специализации 2 (Трек 4) КТвД 25	\N	все
52732	Математический модуль (Трек 4) КТвД 25	\N	все
52731	Физика (Трек 4) КТвД 25	\N	все
52722	Специализация 3: Анимация и развивающие приложения (Трек 5) КТвД 25	\N	все
52726	Обязательные дисциплины специализации 3 (Трек 5) КТвД 25	\N	все
52723	Блок заменяемых дисциплин на выбор (Трек 5) КТвД 25	18	з.е.
54514	Производственная практика КТвД 25	\N	все
54515	Преддипломная практика КТвД 25	\N	все
54520	Государственная итоговая аттестация КТвД 25	\N	все
56421	Soft Skills МТДиЮ 2025	3	з.е.
56422	Soft Skills микромодули	3	з.е.
56423	Soft Skills: 1, 2 семестры - только микромодули, 3 семестр - все курсы	3	з.е.
55986	Мировоззренческий модуль	1	кол-во
55989	Мышление	1	кол-во
55987	Предпринимательская культура	1	кол-во
55988	Креативные технологии	1	кол-во
50584	Иностранный язык (базовый, маг 2025/2026)	\N	все
50586	Иностранный язык (маг 2025/2026). 1 семестр	3	з.е.
50585	Иностранный язык (маг 2025/2026). 2 семестр	3	з.е
52838	Прикладной искусственный интеллект (МТвД, 3-4 семестр)	1	кол-во
52839	Прикладной ИИ (Базовый трек 1)	\N	все
52840	Прикладной ИИ (Базовый трек 1, семестр 3)\n	1	кол-во
52841	Прикладной ИИ (Базовый трек 1, семестр 4)	1	кол-во
4781	Индивидуальная профессиональная подготовка (по профессиональным областям, по профессиональным ролям, по уровню сложности и др.)	\N	все
52275	Обязательные дисциплины профессиональной подготовки МТДиЮ 25	\N	все
52274	Выбор траектории МТДиЮ 25	1	кол-во
52277	Дизайн человеко-компьютерных систем МТДиЮ 25	\N	все
52279	Обязательные дисциплины ДЧКС МТДиЮ 25	\N	все
52278	Дисциплины по выбору для ДЧКС МТДиЮ 25	3	з.е.
52276	Технологии трёхмерного моделирования и расширенной реальности МТДиЮ 25	\N	все
52283	Научно-исследовательская работа	\N	все
52282	Производственная практика	\N	все
52281	Преддипломная практика	\N	все
52280	Государственная итоговая аттестация	\N	все
17498	Блок заменяемых дисциплин на выбор (Трек 1) КТвД 24	6	з.е.
52730	Блок заменяемых дисциплин на выбор (Трек 4) КТвД 25	15	з.е.
63225	Прикладной искусственный интеллект	1	кол-во
63277	Базовая траектория	\N	все
63229	Выборной семестр\n	1	кол-во
63228	Обязательный семестр	1	кол-во
62847	Обязательные дисциплины профессиональной подготовки МТДиЮ 26	\N	все
61839	Выбор траектории МТДиЮ 26	1	кол-во
61842	Дизайн человеко-компьютерных систем МТДиЮ 26	\N	все
61846	Обязательные дисциплины ДЧКС МТДиЮ 26	\N	все
61845	Дисциплины по выбору для ДЧКС МТДиЮ 26	3	з.е.
61841	Технологии трёхмерного моделирования и расширенной реальности МТДиЮ 26	\N	все
62910	История России	1	кол-во
62916	Реформы и реформаторы в истории России	\N	все
62915	Россия в истории современных международных отношений	\N	все
62914	История России и мира в ХХ веке	\N	все
62913	Социальная история России	\N	все
62912	История российской науки и техники	\N	все
62911	История русской культуры в контексте мировой культуры	\N	все
62901	Культура безопасности жизнедеятельности	\N	все
62902	Физическая культура и спорт	\N	все
62909	Философия	\N	все
62883	Иностранный язык (бакалавриат)	\N	все
62886	Иностранный язык (1-2 семестр)	6	з.е.
62885	Иностранный язык (3-4 семестр)	6	з.е.
62884	Иностранный язык (5-6 семестр)	6	з.е.
62903	Предпринимательская культура	\N	все
62905	Дисциплина на выбор "Предпринимательская культура 6 сем. бакалавриат"	1	кол-во
62908	Стартап-трек	1	кол-во
62907	Проектный трек	1	кол-во
62906	Функциональный трек	1	кол-во
62904	Обязательная дисциплина "Предпринимательская культура 3 сем. бакалавриат "	\N	все
62879	Soft Skills (бак 2025). 2-3 семестр	\N	все
62880	Цифровые технологии и искусственный интеллект	\N	все
62882	Обязательная часть	\N	все
62881	Вариативная часть	1	кол-во
62869	Математика	\N	все
62871	Фундаментальная математическая подготовка	\N	все
62355	Общая профессиональная подготовка КТвД 26	\N	все
62273	Выбор траектории КТвД 26	1	кол-во
62289	Специализация Дизайн (Треки 1, 2, 3) КТвД 26	\N	все
62298	Обязательные дисциплины специализации Дизайн КТвД 26	\N	все
62372	Модуль по композиции КТвД 26	\N	все
62371	Модуль по рисунку и пластической анатомии КТвД 26	\N	все
62315	Модуль по живописи КТвД 26	\N	все
62290	Выбор траектории в специализации Дизайн КТвД 26	1	кол-во
62373	Траектории по 3D-моделированию: Треки 1 и 2. КТвД 26	\N	все
62383	Обязательные дисциплины (Трек 1 и Трек 2) КТвД 26	\N	все
62374	Выбор траектории по 3D КТвД 26	1	кол-во
62379	Трек 1. Дизайн компьютерных игр КТвД 26	\N	все
62382	Обязательные дисциплины (Трек 1) КТвД 26	\N	все
62381	Блок заменяемых дисциплин на выбор (Трек 1) КТвД 26	6	з.е.
62380	Выбор предмета для подготовки финального проекта-портфолио КТвД 26	1	кол-во
62375	Трек 2. 3D-визуализация КТвД 26	\N	все
62378	Обязательные дисциплины (Трек 2) КТвД 26	\N	все
62377	Блок заменяемых дисциплин на выбор (Трек 2) КТвД 26	6	з.е.
62376	Выбор предмета для подготовки финального проекта-портфолио КТвД 26	1	кол-во
62299	Траектория по UX/UI: Трек 3. Дизайн графических интерфейсов КТвД 26	\N	все
62301	Обязательные дисциплины (Трек 3) КТвД 26	\N	все
62300	Блок заменяемых дисциплин на выбор (Трек 3) КТвД 26	6	з.е.
62280	Специализация Разработка графических и веб-приложений (Трек 4) КТвД 26	\N	все
62286	Обязательные дисциплины Трек 4. Разработка графических и веб-приложений КТвД 26	\N	все
62283	Математический модуль (Трек 4) КТвД 26	\N	все
62282	Физика (Трек 4) КТвД 26	\N	все
62281	Блок заменяемых дисциплин на выбор (Трек 4) КТвД 26	9	з.е.
62275	Специализация Анимация и развивающие приложения (Трек 5) КТвД 26	\N	все
62279	Обязательные дисциплины Трек 5. Анимация и развивающие приложения КТвД 26	\N	все
62277	Блок заменяемых дисциплин на выбор (Трек 5) КТвД 26	12	з.е.
62384	Производственная практика КТвД 26	\N	все
62385	Преддипломная практика КТвД 26	\N	все
62386	Государственная итоговая аттестация КТвД 26	\N	все
63221	Soft Skills: 1, 2 семестры - только микромодули, 3 семестр - все курсы	3	з.е.
63222	Soft Skills микромодули	3	з.е.
63223	Soft Skills большие курсы	3	з.е.
63233	Мировоззренческий модуль	1	кол-во
63235	Мышление	1	кол-во
63236	Предпринимательская культура (3 семестр)	1	кол-во
63234	Креативные технологии	1	кол-во
63230	Иностранный язык (Магистратура)	\N	все
63232	Иностранный язык (маг 2026/2027) 1 семестр	3	з.е.
63231	Иностранный язык (маг 2026/2027) 2 семестр	3	з.е
\.
COPY s335141.rpd (id_isu, name, comment, id_discipline, status, study_format) FROM stdin;
18034	Фотографические технологии	\N	5919	одобрена	оф
13675	Компьютерные сети	\N	5921	одобрена	оф
35211	3D-моделирование объектов техники	\N	5947	на подписи	микс
53697	Проектирование игрового опыта	\N	6312	в работе	оф
53992	Твердотельное моделирование и 3D-печать	\N	6141	в работе	оф
53700	Стилистика в коммуникационном дизайне	\N	6336	в работе	оф
53696	Разработка клиентской части веб-приложений	\N	6307	в работе	оф
53701	Креативная анимация	\N	6343	в работе	оф
33957	Реформы и реформаторы в истории России	\N	6173	одобрена	микс
33956	Россия в истории современных международных отношений	\N	6209	одобрена	микс
33955	История России и мира в ХХ веке	\N	6210	одобрена	микс
33954	Социальная история России	\N	6211	одобрена	микс
5895	Безопасность жизнедеятельности	\N	5893	одобрена	оф
16560	Физическая культура и спорт (элективная)	\N	6128	одобрена	оф
52517	Социальное предпринимательство	\N	6386	одобрена	микс
30498	Философия	\N	6125	одобрена	\N
10121	Front-end для UI-дизайнеров	\N	6094	одобрена	оф
36566	Английский язык B2	\N	6129	одобрена	оф
53920	Английский язык C2	\N	6129	одобрена	оф
53918	Английский язык B2	\N	6129	одобрена	оф
53915	Английский язык A2	\N	6129	одобрена	оф
18086	Представление данных	\N	6017	одобрена	оф
18080	Проектная документация	\N	6152	в работе	оф
36237	Базы данных для игровых приложений	\N	6169	в работе	оф
31769	Производственная, проектная практика	\N	6202	в работе	оф
31770	Производственная, преддипломная практика	\N	6218	в работе	оф
7068	Визуальная культура и визуальное восприятие	\N	6137	одобрена	оф
18101	Виртуальные среды в образовании	\N	6064	в работе	оф
35222	UI/UX для образовательных систем	\N	6080	в работе	оф
35217	Проектирование и реализация баз данных	\N	6074	в работе	оф
18096	Проектирование и разработка веб-сайтов	\N	6078	одобрена	оф
16291	Вычислительная математика	\N	6165	одобрена	оф
53914	Английский язык A1	\N	6129	одобрена	оф
57874	Моделирование 3D-персонажей	\N	6144	в работе	оф
57873	Разработка интерактивных приложений	\N	6388	в работе	оф
35213	Трёхмерное моделирование и анимация	\N	6063	на подписи	оф
18098	Игровые технологии в образовании	\N	6065	одобрена	оф
18076	Основы компьютерной анимации и иллюстративной графики	\N	6066	одобрена	оф
18072	Архитектурная визуализация	\N	5974	одобрена	оф
35221	Нейронные сети в образовании	\N	6079	на подписи	оф
35220	Экспертные системы в образовании	\N	6077	в работе	оф
35219	Программное и аппаратное обеспечение компьютера и робототехника	\N	6076	одобрена	оф
35218	Технологии программирования	\N	6075	одобрена	оф
31766	Дизайн окружения	\N	6143	в работе	оф
36730	Личная эффективность и управление временем	\N	6412	одобрена	микс
56142	Критическое мышление (продвинутый уровень)	\N	6413	одобрена	он
36645	Немецкий язык B1	\N	6129	одобрена	оф
36640	Немецкий язык A2	\N	6129	одобрена	оф
36575	Немецкий язык A1	\N	6129	одобрена	оф
31773	Методы разработки 3D-моделей	\N	6096	одобрена	оф
36573	Английский язык B1.2	\N	6129	одобрена	оф
18069	Дизайн объектов окружения	\N	6148	в работе	оф
36572	Английский язык B1.1	\N	6129	одобрена	оф
36571	Английский язык A2	\N	6129	одобрена	оф
35215	Методика профессионального обучения	\N	6061	в работе	оф
36568	Английский язык A1	\N	6129	одобрена	оф
51234	Создание и развитие технологического бизнеса	\N	6414	на подписи	микс
59496	Количественные методы в экспериментальных исследованиях	\N	6245	в работе	оф
16978	Качественные методы исследований\n	\N	6246	на подписи	оф
16984	Анализ и оценка пользовательского опыта	\N	6095	одобрена	оф
18068	Hardsurface-моделирование	\N	6149	в работе	оф
31771	Подготовка к защите и защита ВКР	\N	6090	одобрена	\N
18067	Анимация и захват движения	\N	5970	в работе	оф
31775	Технологии моделирования и визуализации реалистичных 3D-моделей	\N	6097	одобрена	\N
1	Mathematics	\N	6125	одобрена	\N
18066	Проектирование и разработка 3D-персонажей	\N	5969	в работе	оф
18070	Дизайн визуальных эффектов	\N	6153	в работе	оф
16977	Философия и научная методология в дизайне	\N	6125	одобрена	\N
21447	Аналитическая геометрия	\N	5925	одобрена	оф
18039	Введение в специальность	\N	5913	одобрена	оф
21451	Математический анализ (базовый уровень)	\N	6196	одобрена	оф
57875	Анимация 3D-персонажей	\N	6390	в работе	оф
35861	Техники публичных выступлений и презентаций	\N	5911	одобрена	микс
29996	Дизайн окружения	\N	6143	в работе	оф
36196	Введение в специальность	\N	5913	одобрена	оф
58143	Теория вероятностей для UX-исследований	\N	6393	в работе	оф
33953	История российской науки и техники	\N	6212	одобрена	микс
57879	Креативное макетирование интерфейсов	\N	6391	в работе	оф
33951	История русской культуры в контексте мировой культуры	\N	6213	одобрена	микс
30175	Философия	\N	6125	одобрена	оф
58001	Креативная анимация	\N	6343	в работе	оф
18100	Методика профессионального обучения	\N	6061	на подписи	оф
20127	Основы рисунка	\N	6156	одобрена	оф
35862	Философия	\N	6125	на подписи	оф
32911	Математическая статистика	\N	6132	одобрена	оф
31283	Основы интеллектуальной собственности	\N	6386	одобрена	микс
2263	Инновационная экономика и технологическое предпринимательство	\N	6386	одобрена	оф
57877	Инструменты ИИ в проектной деятельности	\N	6337	в работе	оф
21455	Специальные разделы высшей математики	\N	6029	одобрена	оф
36197	Дискретная математика	\N	5918	на подписи	микс
36200	Программирование	\N	5917	на подписи	оф
21453	Дополнительные главы математического анализа	\N	6030	одобрена	оф
31772	Количественные методы в экспериментальных исследованиях (1ый семестр)	\N	6098	одобрена	\N
7130	Инновационная экономика и технологическое предпринимательство	\N	6386	одобрена	оф
37118	Линейная алгебра	\N	6220	на подписи	оф
35844	Математический анализ	\N	5926	на подписи	оф
16544	История западноевропейской и русской культуры	\N	6170	одобрена	оф
16543	Наука и техника в истории цивилизации	\N	6171	одобрена	оф
3951	История русской культуры в контексте мировой культуры	\N	6119	одобрена	\N
35214	Проектирование и дизайн web-сайтов	\N	6062	в работе	оф
18091	Базы данных для игровых приложений	\N	6169	на подписи	оф
35845	Математический анализ	\N	5926	на подписи	оф
37120	Веб-аналитика	\N	6000	на подписи	оф
18087	Веб-технологии	\N	6008	одобрена	оф
58000	3D-моделирование объектов техники	\N	5947	в работе	оф
16542	Проблемы истории Европы ХХ века	\N	6172	одобрена	оф
16540	Реформы и реформаторы в истории России	\N	6173	одобрена	оф
16539	История становления Российской государственности	\N	6174	одобрена	оф
18082	Физика (базовый курс)	\N	6200	одобрена	оф
16550	ITMOEnter	\N	6175	одобрена	оф
16568	Философия	\N	6125	одобрена	оф
7957	Бизнес-модели основных секторов инновационной экономики	\N	5909	одобрена	оф
36199	Программирование	\N	5917	одобрена	оф
36263	Подготовка к защите и защита ВКР	\N	6090	в работе	
18062	Твердотельное моделирование и 3D-печать	\N	6141	в работе	оф
18097	Трёхмерное моделирование и анимация	\N	6063	одобрена	оф
18063	Педагогический дизайн	\N	6197	одобрена	оф
16649	Проектирование и прототипирование пользовательских интерфейсов	\N	6093	на подписи	оф
35368	Коммуникации и командообразование	\N	5910	одобрена	микс
36201	Дискретная математика	\N	5918	на подписи	микс
36198	Пропедевтика дизайна	\N	5914	одобрена	микс
53680	Алгоритмы и структуры данных	\N	5923	одобрена	оф
36220	Основы работы с VFX	\N	6158	в работе	оф
36214	3D-моделирование объектов окружения	\N	5949	в работе	оф
36217	Введение в работу с игровыми движками	\N	6139	одобрена	оф
53707	Архитектура компьютера	\N	6027	в работе	оф
54491	Прикладная алгебра	\N	6327	в работе	оф
54487	Методы математического анализа	\N	6328	на подписи	оф
36239	Основы компьютерной анимации и иллюстративной графики	\N	6066	одобрена	оф
54859	Компьютерная геометрия	\N	6341	на подписи	оф
36241	Трёхмерное моделирование и анимация	\N	6063	в работе	оф
54500	Теория вероятностей	\N	6135	на подписи	оф
36203	Основы композиции	\N	5937	в работе	оф
36251	Технологии программирования	\N	6075	на подписи	оф
36257	Проектирование и разработка компьютерных средств обучения	\N	6050	в работе	оф
36218	Дизайн структуры и освещения уровней	\N	5946	в работе	оф
36227	Системы вёрстки	\N	6164	на подписи	оф
36242	Игровые технологии в образовании	\N	6065	в работе	оф
36255	Нейронные сети в образовании	\N	6079	в работе	оф
36233	Полигональное моделирование	\N	6140	одобрена	оф
36253	Программное и аппаратное обеспечение компьютера и робототехника	\N	6076	в работе	оф
36230	Промышленный дизайн и эргономика	\N	5975	в работе	оф
36231	Веб-проектирование	\N	5990	в работе	оф
19843	Методы криптографии	\N	6221	одобрена	он
36256	Нейронные сети в образовании	\N	6079	в работе	оф
37121	Компьютерная алгебра	\N	6224	одобрена	оф
36258	Проектирование и разработка компьютерных средств обучения	\N	6050	на подписи	оф
19747	Компьютерная визуализация	\N	6222	одобрена	он
36248	Основы рисунка	\N	6156	в работе	оф
36225	Полиграфический дизайн	\N	6145	в работе	оф
36236	Представление данных	\N	6017	в работе	оф
38324	Разработка графических веб-приложений	\N	6013	в работе	оф
36259	Теория развития и обучения	\N	6048	на подписи	микс
36212	Живопись и цветоведение	\N	5935	в работе	оф
36208	Пластическая анатомия человека	\N	5934	в работе	оф
35853	Теория вероятностей	\N	6135	в работе	оф
36244	Игровые технологии в образовании	\N	6065	в работе	оф
36247	Основы рисунка	\N	6156	в работе	оф
36254	Экспертные системы в образовании	\N	6077	в работе	оф
36260	Теория развития и обучения	\N	6048	на подписи	микс
36232	Дополнительные главы высшей математики	\N	6225	на экспертизе	оф
36574	Английский язык C1	\N	6129	одобрена	оф
36215	3D-моделирование объектов техники	\N	5947	в работе	оф
36209	Основы рисунка	\N	6156	на подписи	оф
37119	Веб-проектирование	\N	5990	в работе	оф
36206	Основы рисунка	\N	6156	в работе	оф
36207	Основы рисунка	\N	6156	в работе	оф
36245	Методика профессионального обучения	\N	6061	в работе	оф
35855	Математическая статистика	\N	6132	в работе	оф
36246	Методика профессионального обучения	\N	6061	в работе	оф
36249	Программное и аппаратное обеспечение компьютера и робототехника	\N	6076	на подписи	оф
31764	Инструменты разработки пользовательского интерфейса	\N	6223	одобрена	оф
36204	Основы композиции	\N	5937	в работе	оф
36213	Живопись и цветоведение	\N	5935	в работе	оф
36243	Основы компьютерной анимации и иллюстративной графики	\N	6066	одобрена	оф
36229	Промышленный дизайн и эргономика	\N	5975	в работе	оф
36250	Технологии программирования	\N	6075	на подписи	оф
54488	Методы математического анализа	\N	6328	на подписи	оф
36261	Производственная, преддипломная	\N	6228	в работе	
36224	Интерактивные приложения в Unreal Engine	\N	5956	в работе	оф
35856	Теория функций комплексного переменного	\N	6226	в работе	оф
36252	Экспертные системы в образовании	\N	6077	в работе	оф
36240	Трёхмерное моделирование и анимация	\N	6063	одобрена	оф
36223	Проектирование интерактивных приложений	\N	5955	в работе	оф
36228	Тестирование пользовательских интерфейсов	\N	6154	в работе	оф
36205	Основы композиции	\N	5937	в работе	оф
54474	Математическая статистика	\N	6132	на подписи	оф
36216	Полигональное моделирование	\N	6140	на подписи	оф
54499	Специальные разделы математического анализа	\N	6340	в работе	оф
36262	Производственная, проектная	\N	6227	в работе	
36219	Типографика	\N	5920	одобрена	оф
36211	История искусств	\N	6134	в работе	оф
36210	История искусств	\N	6134	на подписи	оф
31776	Техническая реализация дизайн-системы	\N	6251	одобрена	оф
16988	Проектирование доступных интерфейсов для пользователей с особыми потребностями	\N	6247	на подписи	оф
36822	Навыки критического мышления (продвинутый уровень) / Critical Thinking Skills (advanced)	\N	6237	одобрена	оф
33340	Проектный менеджмент	\N	6238	одобрена	микс
34013	Креативные индустрии и инновационные технологии	\N	6239	одобрена	микс
35978	Количественные методы в экспериментальных исследованиях	\N	6245	в работе	оф
35977	Количественные методы в экспериментальных исследованиях	\N	6245	на подписи	оф
16985	Стилистика и визуальные образы в компьютерных средах	\N	6248	одобрена	оф
35981	Моделирование и визуализация реалистичных 3D-ассетов	\N	6253	одобрена	оф
16994	Информационные технологии в современной визуальной культуре	\N	6257	одобрена	оф
16991	Трёхмерное моделирование и анимация компьютерных персонажей	\N	6259	одобрена	оф
16982	Психология человеко-компьютерного взаимодействия	\N	6249	одобрена	оф
1001	Графический дизайн пользовательских интерфейсов	\N	6250	на подписи	оф
9189	Перспективные человеко-машинные интерфейсы	\N	6252	одобрена	оф
57389	Методы разработки 3D-моделей	\N	6096	в работе	оф
35980	Технологии виртуальной реконструкции архитектурного наследия	\N	6254	одобрена	оф
16996	Дизайн виртуальных интерьеров\n	\N	6255	одобрена	оф
16995	Технологии захвата движений	\N	6256	на подписи	оф
16993	Виртуальная, дополненная и смешанная реальность	\N	6258	одобрена	оф
35986	Научно-исследовательская работа	\N	6260	в работе	оф
35985	Научно-исследовательская работа	\N	6260	в работе	оф
35984	Научно-исследовательская работа	\N	6260	в работе	оф
35983	Производственная, проектная	\N	6227	в работе	оф
35982	Производственная, преддипломная	\N	6228	в работе	оф
35987	Подготовка к защите и защита ВКР	\N	6090	одобрена	оф
36738	Эмоциональный интеллект / Emotional Intelligence	\N	6236	одобрена	микс
30285	Хранение больших данных и Элементы статистики	\N	6242	одобрена	он
16464	Введение в МО (инструменты) и Методы ПИИ	\N	6243	одобрена	он
36728	Scientific writing / Научное письмо на английском языке	\N	6415	на доработке	микс
36729	Навыки презентации на английском языке / Presentation skills	\N	6241	на доработке	микс
56559	Культура ИИ: Медиа и креативность	\N	6395	в работе	он
56563	ИИ-мышление: Наука, технологии, агентность	\N	6396	одобрена	он
57386	История и теория дизайна	\N	6349	в работе	оф
35979	Философия и научная методология в дизайне\n	\N	6244	одобрена	оф
52126	Реформы и реформаторы в истории России	\N	6173	одобрена	микс
19045	Биометрия и нейротехнологии	\N	6036	одобрена	микс
51298	Стартап-трек: IT и роботы	\N	6318	одобрена	микс
51297	Стартап-трек: рынок AI	\N	6319	одобрена	микс
51296	Стартап-трек: рынок Life Science	\N	6320	одобрена	микс
21452	Математический анализ (продвинутый уровень)	\N	6315	одобрена	оф
29980	Производственная, проектная практика	\N	6202	в работе	
29433	Преддипломная практика	\N	6203	в работе	
29435	Подготовка к защите и защита ВКР	\N	6090	в работе	
50277	Техники публичных выступлений и презентаций	\N	5911	на подписи	оф
51841	Методы математического анализа	\N	6328	на подписи	оф
51843	Методы математического анализа	\N	6328	на экспертизе	оф
53691	Иллюстрация в коммуникационном дизайне	\N	6335	в работе	оф
50664	Правовые особенности функционирования стартапов	\N	6386	одобрена	микс
53684	Нарративный дизайн	\N	6313	в работе	оф
51295	Прототипирование и создание mvp	\N	6323	одобрена	микс
53681	Вычислительная математика и методы оптимизации	\N	6309	на подписи	оф
51887	Прикладная алгебра	\N	6327	в работе	оф
52376	Веб-проектирование	\N	5990	в работе	оф
52127	Россия в истории современных международных отношений	\N	6209	одобрена	микс
35553	История русской культуры в контексте мировой культуры	\N	6213	одобрена	микс
53673	Введение в специальность	\N	5913	в работе	микс
52352	Академический рисунок	\N	6331	в работе	оф
52342	Технологии анимации и искусственный интеллект	\N	6314	в работе	оф
53677	Разработка серверной части веб-приложений	\N	6308	одобрена	оф
52128	История России и мира в ХХ веке	\N	6210	одобрена	микс
52326	История России и мира в ХХ веке	\N	6210	на подписи	микс
52129	Социальная история России	\N	6211	на подписи	микс
52325	Социальная история России	\N	6211	на подписи	микс
52131	История российской науки и техники	\N	6212	на подписи	микс
52324	История российской науки и техники	\N	6212	на подписи	микс
52130	История русской культуры в контексте мировой культуры	\N	6213	на подписи	микс
51920	Моделирование физических процессов	\N	6333	в работе	оф
52328	Реформы и реформаторы в истории России	\N	6173	на подписи	микс
52323	История русской культуры в контексте мировой культуры	\N	6213	на подписи	микс
56219	Философия	\N	6125	в работе	оф
53916	Английский язык B1.1	\N	6129	одобрена	оф
53917	Английский язык B1.2	\N	6129	одобрена	оф
52215	Философия	\N	6125	в работе	оф
53921	Английский язык в профессиональной деятельности	\N	6129	одобрена	оф
51299	Стартап-трек: креативные технологии	\N	6317	одобрена	микс
56122	Проектный менеджмент: методологии и стандарты	\N	6398	в работе	микс
50667	Стартап-трек: общий вектор	\N	6321	одобрена	микс
56123	Продуктовая логика для R&D	\N	6397	в работе	микс
51301	Практикум по проектному менеджменту	\N	6386	на подписи	микс
51292	Рыночные вызовы: разработка бизнес-решений	\N	6322	на подписи	микс
51294	Лаборатория брендинга	\N	6324	одобрена	микс
51293	Финансы проекта и организации	\N	6325	одобрена	микс
50666	Социальное предпринимательство	\N	6386	в работе	микс
51290	Введение в технологическое предпринимательство	\N	6326	одобрена	микс
53682	Генеративные технологии в цифровом дизайне	\N	6329	в работе	оф
53674	Информационные и компьютерные технологии	\N	6330	в работе	оф
52353	Академический рисунок	\N	6331	в работе	оф
52375	Веб-проектирование	\N	5990	в работе	оф
52372	Инженерная графика	\N	6150	в работе	оф
53683	Скетчинг	\N	6311	в работе	оф
53690	3D-моделирование объектов техники	\N	5947	в работе	оф
53678	Проектирование игрового опыта	\N	6312	на подписи	оф
52327	Россия в истории современных международных отношений	\N	6209	на подписи	микс
55851	Русский язык как иностранный	\N	6129	одобрена	микс
51300	Стартап-трек: энергетика	\N	6316	одобрена	микс
56548	Данные как основа ИИ	\N	6401	в работе	микс
56551	Классические методы МО и основы нейронных сетей	\N	6402	в работе	микс
55852	Русский язык как иностранный	\N	6129	на подписи	микс
53919	Английский язык C1	\N	6129	одобрена	оф
56116	Рыночные вызовы: реализация трансфера технологий	\N	6399	в работе	микс
51302	Основы интеллектуальной собственности	\N	6386	одобрена	микс
56547	Инструментальные возможности ИИ	\N	6400	в работе	микс
52373	Основы композиции	\N	5937	на подписи	оф
52354	Академический рисунок	\N	6331	в работе	оф
51900	Математическая статистика	\N	6132	на подписи	оф
51899	Теория вероятностей	\N	6135	на подписи	оф
30179	Инновационная экономика и технологическое предпринимательство	\N	6386	одобрена	микс
56552	ИИ как образ жизни: Агентные системы	\N	6404	в работе	микс
52337	Дизайн и разработка развивающих игр	\N	6346	в работе	оф
51923	Специальные разделы математического анализа	\N	6340	в работе	оф
51918	Компьютерная геометрия	\N	6341	на подписи	оф
52338	Проектирование и разработка развивающих приложений	\N	6345	в работе	оф
30176	Создание ценности инновационного продукта	\N	6386	одобрена	микс
33341	Социальное предпринимательство	\N	6386	одобрена	микс
34617	Введение в специальность	\N	5913	одобрена	оф
20123	Пропедевтика дизайна	\N	5914	одобрена	микс
52334	Теория развития	\N	6347	в работе	микс
56554	ИИ как образ жизни: Агентные системы и компьютерное зрение	\N	6405	в работе	микс
36646	Китайский язык B1	\N	6129	одобрена	оф
29867	Иностранный язык	\N	6129	одобрена	оф
18040	История дизайна	\N	5915	одобрена	оф
52335	Теория развития	\N	6347	в работе	микс
30183	Бизнес-модели основных секторов инновационной экономики	\N	5909	одобрена	микс
9326	Коммуникации и командообразование	\N	5910	одобрена	оф
21052	Техники публичных выступлений и презентаций	\N	5911	одобрена	оф
30182	Правовые особенности функционирования стартапов	\N	6386	одобрена	микс
30181	Реализация стартап-проектов на рынке Foodtech. От идеи до MVP	\N	6386	одобрена	микс
30178	Практикум по проектному менеджменту	\N	6386	одобрена	микс
36644	Испанский язык B1	\N	6129	одобрена	оф
36643	Английский язык в профессиональной деятельности	\N	6129	одобрена	оф
36642	Китайский язык A2	\N	6129	одобрена	оф
36641	Китайский язык A1	\N	6129	на подписи	оф
30177	Стартап с нуля: от идеи до выхода на рынок	\N	6386	на подписи	микс
52336	Дизайн и разработка развивающих игр	\N	6346	в работе	оф
36639	Английский язык C2	\N	6129	одобрена	оф
53991	Объектно-ориентированное программирование (базовый уровень)	\N	6332	одобрена	оф
52341	Профессиональное развитие в области компьютерной графики 	\N	6344	в работе	оф
52340	Профессиональное развитие в области компьютерной графики 	\N	6344	в работе	оф
30180	Основы интеллектуальной собственности	\N	6386	одобрена	микс
56555	ИИ как образ жизни: Агентные системы и обработка естественного языка	\N	6406	в работе	микс
36570	Испанский язык A1	\N	6129	одобрена	оф
52339	Проектирование и разработка развивающих приложений	\N	6345	в работе	оф
38269	Элективные микромодули Soft Skills	\N	6235	в работе	микс
16559	Физическая культура и спорт (базовая)	\N	6128	одобрена	оф
36569	Испанский язык A2	\N	6129	одобрена	оф
30184	Защита и действия человека в условиях ЧС	\N	5912	одобрена	оф
51303	Проектный менеджмент	\N	6238	на подписи	микс
52346	Количественные методы в экспериментальных исследованиях	\N	6245	в работе	оф
52330	Трёхмерное моделирование компьютерных персонажей	\N	6351	одобрена	оф
52329	Дизайн интерактивных медиа	\N	6352	в работе	оф
36567	Русский язык как иностранный	\N	6129	одобрена	микс
58772	Основы программирования	\N	6407	в работе	оф
58768	Генеративные технологии в цифровом дизайне	\N	6329	в работе	оф
56553	Архитектуры современного ИИ и человек	\N	6403	в работе	микс
21041	Основы концептуального мышления	\N	6348	одобрена	он
52211	Навыки критического мышления (продвинутый уровень) / Critical Thinking Skills (advanced)	\N	6237	одобрена	он
52347	Стилистика и визуальные образы в компьютерных средах	\N	6248	на подписи	оф
52345	Количественные методы в экспериментальных исследованиях	\N	6245	в работе	оф
52333	История и теория дизайна	\N	6349	на подписи	оф
52371	Веб-аналитика	\N	6000	одобрена	оф
52332	Анимация трёхмерных персонажей	\N	6350	в работе	оф
52331	Моделирование и визуализация реалистичных 3D-ассетов	\N	6253	в работе	оф
53693	Базы данных для игровых приложений	\N	6169	в работе	оф
57871	История дизайна	\N	5915	в работе	оф
57870	Информационные и компьютерные технологии	\N	6330	в работе	оф
57869	Информатика	\N	5922	в работе	оф
57868	Основы компьютерной графики	\N	6408	в работе	оф
52374	Основы композиции	\N	5937	в работе	оф
57876	3D-моделирование объектов техники	\N	5947	в работе	оф
52344	Развивающие виртуальные среды	\N	6342	в работе	оф
52343	Креативная анимация	\N	6343	в работе	оф
34377	3D-моделирование объектов окружения	\N	5949	на подписи	микс
36202	Фотографические технологии	\N	5919	на подписи	оф
34378	Пластическая анатомия животных	\N	6168	одобрена	оф
53686	Стилистика в коммуникационном дизайне	\N	6336	в работе	оф
38205	Основы проектирования дизайн-систем	\N	5989	одобрена	оф
34380	Проектирование интерактивных приложений	\N	5955	одобрена	микс
18037	Языки программирования (С#)	\N	5916	одобрена	оф
18036	Программирование	\N	5917	одобрена	оф
18035	Дискретная математика	\N	5918	одобрена	оф
18033	Типографика	\N	5920	одобрена	оф
7118	Алгоритмы и структуры данных	\N	5923	одобрена	оф
31768	Аналитическая геометрия	\N	5925	одобрена	оф
31762	Основы компьютерной 2D-анимации	\N	6131	на подписи	оф
30195	Математический анализ	\N	5926	на доработке	оф
53685	Анимация для интерфейсов	\N	6310	на подписи	оф
18071	Промышленный дизайн и эргономика	\N	5975	на подписи	оф
57880	Веб-разработка	\N	6409	в работе	оф
16768	Веб-аналитика	\N	6000	одобрена	оф
31763	Motion-дизайн	\N	5991	одобрена	оф
7799	Информатика	\N	5922	одобрена	оф
21137	Теория массового обслуживания	\N	5927	одобрена	он
21013	Автоматическая обработка текста	\N	5928	одобрена	он
53676	Объектно-ориентированное программирование (продвинутый уровень)	\N	6339	на подписи	оф
54764	Дополнительные разделы высшей математики\n	\N	6410	одобрена	оф
56178	Физика	\N	6217	в работе	оф
19905	Анализ социальных сетей	\N	5929	одобрена	он
56176	Физика	\N	6217	в работе	оф
57886	Основы графики	\N	6411	в работе	оф
57884	Основы графики	\N	6411	в работе	оф
57881	Инструменты компьютерного дизайна	\N	6051	в работе	оф
57872	Инженерная психология	\N	6160	в работе	оф
38204	Веб-проектирование	\N	5990	на подписи	оф
19903	Обработка изображений	\N	5930	одобрена	он
19745	Методы искусственного интеллекта	\N	5931	одобрена	он
34379	Интерактивные приложения в Unreal Engine	\N	5956	на подписи	микс
19743	Компьютерное зрение	\N	5932	одобрена	он
19742	Интернет вещей	\N	5933	одобрена	он
36221	Дизайн интерактивных приложений	\N	6199	в работе	микс
53698	Твердотельное моделирование и 3D-печать	\N	6141	на подписи	оф
18046	Пластическая анатомия человека	\N	5934	одобрена	оф
18045	Живопись и цветоведение	\N	5935	одобрена	оф
18044	Основы рисунка	\N	6156	одобрена	оф
18043	Основы композиции	\N	5937	одобрена	оф
35212	Дизайн структуры и освещения уровней	\N	5946	на подписи	оф
57885	Дизайн и разработка развивающих игр	\N	6346	в работе	оф
18078	Дизайн фирменного стиля	\N	6155	одобрена	оф
18058	Моделирование 3D-персонажей	\N	6144	в работе	оф
18061	Архитектурное проектирование	\N	6136	одобрена	оф
31765	Основы работы с 3D-анимацией	\N	6162	одобрена	оф
53694	3D-визуализация	\N	6334	в работе	оф
36222	Разработка и анимация 3D-персонажей	\N	6198	в работе	оф
57883	Анимация для интерфейсов	\N	6310	в работе	оф
57882	Motion-дизайн	\N	5991	в работе	оф
53679	Разработка клиентской части веб-приложений	\N	6307	на подписи	оф
59495	Производственная, проектная	\N	6227	в работе	
826	Алгоритмы компьютерной графики	\N	6133	одобрена	оф
37122	Веб-технологии	\N	6008	на подписи	оф
21192	Стандарты в мультимедиа-технологиях	\N	6166	на подписи	оф
18090	Системы компьютерной обработки изображений	\N	6015	одобрена	оф
52349	Визуальная культура и визуальное восприятие	\N	6137	на подписи	оф
18094	Биометрия и нейротехнологии	\N	6036	одобрена	микс
18073	Системы вёрстки	\N	6164	одобрена	оф
2243	Инженерная графика	\N	6150	одобрена	оф
53695	Проектная документация	\N	6152	в работе	оф
18064	Тестирование пользовательских интерфейсов	\N	6154	одобрена	оф
18079	Визуализация данных	\N	6157	одобрена	оф
16579	Хранение и обработка данных (базовый уровень)	\N	6383	одобрена	он
31767	Специальные разделы высшей математики	\N	6029	одобрена	оф
30209	Дополнительные главы математического анализа	\N	6030	одобрена	оф
53445	Компьютерные сети	\N	5921	одобрена	оф
19037	Методы оптимизации	\N	6014	одобрена	оф
18060	Полиграфический дизайн	\N	6145	одобрена	оф
35216	Визуализация учебной информации в игропедагогике	\N	6060	в работе	оф
18089	Методы обработки изображений	\N	6016	одобрена	оф
53689	Инструменты ИИ в проектной деятельности	\N	6337	в работе	оф
30185	Математическая статистика	\N	6132	одобрена	оф
16580	Хранение и обработка данных (продвинутый уровень)	\N	6383	одобрена	он
5902	Тестирование программного обеспечения	\N	6045	одобрена	оф
6121	Системы искусственного интеллекта	\N	6026	одобрена	оф
5967	История искусств	\N	6134	одобрена	оф
3312	Разработка мобильных приложений	\N	6046	одобрена	микс
18102	Методика проектной работы	\N	6049	на подписи	оф
2086	Функциональное программирование	\N	6142	одобрена	оф
32187	Полигональное моделирование	\N	6140	на подписи	оф
5959	Информационная безопасность	\N	5924	одобрена	оф
36234	Базы данных для игровых приложений	\N	6169	в работе	оф
53719	Базы данных для игровых приложений	\N	6169	в работе	оф
35210	Основы работы с VFX	\N	6158	в работе	микс
16581	Прикладная статистика (базовый уровень)	\N	6382	одобрена	он
35818	Физика	\N	6217	в работе	оф
53687	Микросервисная архитектура веб-приложений	\N	6338	на подписи	оф
29227	Вычислительная математика	\N	6165	одобрена	оф
18075	Теория вероятностей	\N	6135	одобрена	оф
35819	Физика	\N	6217	на экспертизе	оф
18095	Инструменты компьютерного дизайна	\N	6051	одобрена	оф
16582	Прикладная статистика (продвинутый уровень)	\N	6382	одобрена	он
18084	Основы программной инженерии	\N	6018	на доработке	оф
18042	Инженерная психология	\N	6160	одобрена	оф
36235	Представление данных	\N	6017	в работе	оф
18053	Разработка приложений виртуальной реальности	\N	6138	одобрена	оф
18065	Общая психология	\N	6163	одобрена	оф
16583	Машинное обучение (базовый уровень)	\N	6230	одобрена	он
16584	Машинное обучение (продвинутый уровень)	\N	6230	одобрена	он
21190	Разработка графических веб-приложений	\N	6013	одобрена	оф
7841	Операционные системы	\N	6025	одобрена	оф
18032	Проекционная геометрия	\N	6130	на подписи	оф
18048	Введение в работу с игровыми движками	\N	6139	одобрена	оф
5917	Архитектура компьютера	\N	6027	одобрена	оф
53723	Креативная анимация	\N	6343	в работе	оф
20393	Теория развития и обучения	\N	6048	одобрена	оф
18099	Проектирование и разработка компьютерных средств обучения	\N	6050	одобрена	оф
\.
COPY s335141.sections (id, "position", id_curricula, id_module, id_parent_section) FROM stdin;
7877	1	111	4782	\N
7878	1	111	17444	7877
7879	1	111	17470	7878
7880	2	111	17468	7878
7881	3	111	17446	7878
7882	4	111	17466	7878
7883	5	111	17454	7878
7884	1	111	17455	7883
7885	2	111	17457	7883
7886	3	111	17461	7883
7887	6	111	17448	7878
7888	3	111	17451	7887
7889	4	111	17450	7887
7890	7	111	17464	7878
7891	2	111	17472	7877
7892	7	111	17473	7891
7893	4	111	17478	7892
7894	5	111	17479	7892
7895	6	111	17475	7892
7896	7	111	17477	7892
7897	8	111	17480	7891
7898	7	111	17481	7897
7899	1	111	17482	7898
7900	1	111	17489	7899
7901	2	111	17488	7899
7902	3	111	17487	7899
7903	4	111	17490	7899
7904	5	111	17483	7899
7905	1	111	17484	7904
7906	2	111	17486	7904
7907	3	111	17485	7904
7908	2	111	17491	7898
7909	5	111	17492	7908
7910	3	111	17493	7909
7911	4	111	17494	7909
7912	1	111	17495	7911
7913	1	111	17497	7912
7914	2	111	17498	7912
7915	3	111	17496	7912
7916	2	111	17499	7911
7917	3	111	17501	7916
7918	4	111	17502	7916
7919	5	111	17500	7916
7920	6	111	17503	7908
7921	4	111	17505	7920
7922	5	111	17504	7920
7923	6	111	17506	7920
7924	8	111	17507	7897
7925	2	111	17512	7924
7926	3	111	17510	7924
7927	4	111	17508	7924
7928	5	111	17509	7924
7929	6	111	17511	7924
7930	9	111	17513	7897
7931	6	111	17529	7930
7932	7	111	17514	7930
7933	6	111	17515	7932
7934	7	111	17517	7932
7935	8	111	17516	7932
7936	8	111	17518	7930
7937	8	111	17519	7936
7938	6	111	17520	7937
7939	7	111	17521	7937
7940	2	111	17525	7939
7941	3	111	17522	7939
7942	5	111	17523	7941
7943	6	111	17524	7941
7944	9	111	17526	7936
7945	7	111	17527	7944
7946	8	111	17528	7944
7947	2	111	4788	\N
7948	2	111	17531	7947
7949	3	111	17530	7947
7950	3	111	4793	\N
7951	3	111	17532	7950
8088	1	113	4782	\N
8089	1	113	4761	8088
8090	1	113	5091	8089
8091	2	113	5092	8089
8092	3	113	5093	8089
8093	4	113	5094	8089
8094	5	113	22602	8089
7802	1	-103344	4782	\N
7803	1	-103344	17444	7802
7804	1	-103344	17470	7803
7805	2	-103344	17468	7803
7806	3	-103344	17446	7803
7807	4	-103344	17466	7803
7808	5	-103344	17454	7803
7809	1	-103344	17455	7808
7810	2	-103344	17457	7808
7811	3	-103344	17461	7808
7812	6	-103344	17448	7803
7813	3	-103344	17451	7812
7814	4	-103344	17450	7812
7815	7	-103344	17464	7803
8560	1	10323	4782	\N
8561	1	10323	6161	8560
8562	1	10323	62910	8561
8563	1	10323	62916	8562
8564	2	10323	62915	8562
8565	3	10323	62914	8562
8566	4	10323	62913	8562
8567	5	10323	62912	8562
8568	6	10323	62911	8562
8569	2	10323	62901	8561
8570	3	10323	62902	8561
8571	4	10323	62909	8561
8572	5	10323	62883	8561
8573	6	10323	62886	8572
8574	7	10323	62885	8572
8575	8	10323	62884	8572
8576	6	10323	62903	8561
8577	8	10323	62905	8576
8578	1	10323	62908	8577
8579	2	10323	62907	8577
8580	3	10323	62906	8577
8581	9	10323	62904	8576
8582	7	10323	62879	8561
8583	8	10323	62880	8561
8584	9	10323	62882	8583
8585	10	10323	62881	8583
8586	2	10323	8051	8560
8587	8	10323	50177	8586
8588	10	10323	62869	8587
8589	3	10323	62871	8588
8590	9	10323	50228	8586
8591	10	10323	62355	8590
8592	11	10323	62273	8590
8593	3	10323	62289	8592
8594	1	10323	62298	8593
8595	1	10323	62372	8594
8596	2	10323	62371	8594
8597	3	10323	62315	8594
8598	2	10323	62290	8593
8599	3	10323	62373	8598
8600	1	10323	62383	8599
8601	2	10323	62374	8599
8602	1	10323	62379	8601
8603	1	10323	62382	8602
8604	2	10323	62381	8602
8605	3	10323	62380	8602
7816	2	-103344	17472	7802
8606	2	10323	62375	8601
8607	3	10323	62378	8606
8608	4	10323	62377	8606
8609	5	10323	62376	8606
8610	4	10323	62299	8598
8611	2	10323	62301	8610
8612	3	10323	62300	8610
8613	4	10323	62280	8592
8614	2	10323	62286	8613
8615	3	10323	62283	8613
8616	4	10323	62282	8613
8617	5	10323	62281	8613
8618	5	10323	62275	8592
7817	7	-103344	17473	7816
7818	4	-103344	17478	7817
7819	5	-103344	17479	7817
7820	6	-103344	17475	7817
7821	7	-103344	17477	7817
7822	8	-103344	17480	7816
7823	7	-103344	17481	7822
7824	1	-103344	17482	7823
7825	1	-103344	17489	7824
7826	2	-103344	17488	7824
7827	3	-103344	17487	7824
7828	4	-103344	17490	7824
7829	5	-103344	17483	7824
7830	1	-103344	17484	7829
7831	2	-103344	17486	7829
7832	3	-103344	17485	7829
7833	2	-103344	17491	7823
7834	5	-103344	17492	7833
7835	3	-103344	17493	7834
7836	4	-103344	17494	7834
7837	1	-103344	17495	7836
7838	1	-103344	17497	7837
7839	2	-103344	17498	7837
7840	3	-103344	17496	7837
7841	2	-103344	17499	7836
7842	3	-103344	17501	7841
7843	4	-103344	17502	7841
7844	5	-103344	17500	7841
7845	6	-103344	17503	7833
7846	4	-103344	17505	7845
7847	5	-103344	17504	7845
7848	6	-103344	17506	7845
7849	8	-103344	17507	7822
7850	2	-103344	17512	7849
7851	3	-103344	17510	7849
7852	4	-103344	17508	7849
7853	5	-103344	17509	7849
7854	6	-103344	17511	7849
7855	9	-103344	17513	7822
7856	6	-103344	17529	7855
7857	7	-103344	17514	7855
7858	6	-103344	17515	7857
7859	7	-103344	17517	7857
7860	8	-103344	17516	7857
7861	8	-103344	17518	7855
7701	1	10075	4782	\N
7702	1	10075	6161	7701
7703	1	10075	54525	7702
7704	1	10075	54531	7703
7705	2	10075	54530	7703
7706	3	10075	54529	7703
7707	4	10075	54528	7703
7708	5	10075	54527	7703
7709	6	10075	54526	7703
7710	2	10075	51854	7702
7711	3	10075	51853	7702
7712	4	10075	51199	7702
7713	5	10075	56428	7702
7714	6	10075	56431	7713
7715	7	10075	56430	7713
7716	8	10075	56429	7713
7862	8	-103344	17519	7861
8264	4	42357	17502	8262
8265	5	42357	17500	8262
8266	6	42357	17503	8254
8267	4	42357	17505	8266
8268	5	42357	17504	8266
8269	6	42357	17506	8266
8270	8	42357	17507	8243
8271	2	42357	17512	8270
8272	3	42357	17510	8270
8273	4	42357	17508	8270
8274	5	42357	17509	8270
8275	6	42357	17511	8270
8276	9	42357	17513	8243
8277	6	42357	17529	8276
7717	6	10075	51847	7702
7718	8	10075	51849	7717
7719	1	10075	51852	7718
7720	2	10075	51851	7718
7721	3	10075	51850	7718
7722	9	10075	51844	7717
7723	7	10075	55483	7702
7724	2	10075	8051	7701
7725	7	10075	50177	7724
7726	9	10075	54459	7725
7727	3	10075	54461	7726
7728	4	10075	54460	7726
7729	8	10075	50228	7724
7730	9	10075	52680	7729
7731	4	10075	52694	7730
7732	5	10075	52689	7730
7733	6	10075	56432	7730
7734	1	10075	56433	7733
7735	2	10075	56434	7733
7736	3	10075	56435	7733
7737	7	10075	52728	7730
7738	10	10075	52679	7729
7739	7	10075	52734	7738
7740	3	10075	52736	7739
7741	1	10075	52740	7740
7742	2	10075	52739	7740
7743	3	10075	52738	7740
7744	4	10075	52737	7740
7745	4	10075	52735	7739
7746	4	10075	52747	7745
7747	1	10075	52758	7746
7748	2	10075	52748	7746
7749	1	10075	52750	7748
7750	1	10075	52757	7749
7751	2	10075	52756	7749
7752	3	10075	52755	7749
7753	2	10075	52749	7748
7754	3	10075	52754	7753
7755	4	10075	52753	7753
7756	5	10075	52751	7753
7757	5	10075	52743	7745
7758	2	10075	52745	7757
7759	3	10075	52744	7757
7760	8	10075	52729	7738
7761	4	10075	52733	7760
7762	5	10075	52732	7760
7763	6	10075	52731	7760
7764	7	10075	52730	7760
7765	9	10075	52722	7738
7766	7	10075	52726	7765
7767	8	10075	52723	7765
7768	2	10075	4788	\N
7769	2	10075	54514	7768
7770	3	10075	54515	7768
7771	3	10075	4793	\N
7772	3	10075	54520	7771
7787	1	-3344	52840	7786
7788	2	-3344	52841	7786
7789	2	-3344	4781	7773
7952	1	112	4782	\N
7953	1	112	12233	7952
7954	1	112	12242	7953
7955	2	112	12244	7953
7956	3	112	12234	7953
7957	1	112	12235	7956
7958	2	112	12236	7956
7959	4	112	12240	7953
7960	5	112	22602	7953
7961	2	112	22605	7960
7962	1	112	50438	7961
7963	2	112	50439	7961
7964	3	112	22604	7960
7965	4	112	22603	7960
7966	6	112	12237	7953
7967	4	112	12238	7966
7968	5	112	12239	7966
7969	7	112	12243	7953
7970	8	112	12245	7953
7971	2	112	12246	7952
7972	8	112	12337	7971
7790	4	-3344	52275	7789
8148	1	18367	4782	\N
8149	1	18367	12233	8148
8150	1	18367	12242	8149
8151	2	18367	12244	8149
8152	3	18367	12234	8149
8153	1	18367	12235	8152
8154	2	18367	12236	8152
8155	4	18367	12240	8149
8156	5	18367	22602	8149
8157	2	18367	22605	8156
8158	1	18367	50438	8157
8159	2	18367	50439	8157
8160	3	18367	22604	8156
8161	4	18367	22603	8156
8162	6	18367	12237	8149
8163	4	18367	12238	8162
8164	5	18367	12239	8162
8165	7	18367	12243	8149
8166	8	18367	12245	8149
8167	2	18367	12246	8148
8168	8	18367	12337	8167
8169	5	18367	12341	8168
8170	6	18367	12338	8168
8171	7	18367	12344	8168
8172	9	18367	12247	8167
8173	7	18367	12248	8172
8174	2	18367	12249	8173
8175	1	18367	12250	8174
8176	2	18367	12251	8174
8177	1	18367	12252	8176
8178	2	18367	12253	8176
8179	3	18367	12254	8176
8180	3	18367	12255	8173
8181	2	18367	12267	8180
8182	3	18367	12269	8181
8183	4	18367	12271	8181
8184	1	18367	12273	8183
8185	1	18367	12274	8184
8186	2	18367	14925	8184
8187	3	18367	12285	8184
8188	2	18367	12289	8183
8189	3	18367	12291	8188
8190	4	18367	12294	8188
8191	5	18367	12296	8188
8192	3	18367	12256	8180
8193	4	18367	12257	8192
8194	5	18367	12263	8192
8195	8	18367	12298	8172
8196	3	18367	12299	8195
8197	3	18367	12301	8196
8198	4	18367	12304	8196
8199	5	18367	12309	8196
8200	4	18367	12310	8195
7311	1	3343	4782	\N
7312	1	3343	17404	7311
7313	1	3343	17459	7312
7314	1	3343	17462	7313
7315	2	3343	17460	7313
7316	2	3343	17452	7312
7317	2	3343	17458	7316
7318	3	3343	17456	7316
7319	4	3343	17453	7316
7320	3	3343	17445	7312
7321	4	3343	17447	7320
7322	5	3343	17449	7320
7323	4	3343	17405	7312
7324	5	3343	17406	7323
7325	1	3343	17407	7324
7326	2	3343	17408	7324
7327	2	3343	17396	7311
7328	4	3343	17397	7327
7329	5	3343	17398	7327
7330	5	3343	17399	7329
7331	2	3343	17401	7330
7332	3	3343	17400	7330
7333	6	3343	17403	7329
7334	2	3343	4788	\N
7335	2	3343	17467	7334
7336	3	3343	17465	7334
7337	4	3343	17463	7334
7338	3	3343	4793	\N
7339	4	3343	17469	7338
7973	5	112	12341	7972
7974	6	112	12338	7972
7975	7	112	12344	7972
7976	9	112	12247	7971
7977	7	112	12248	7976
7978	2	112	12249	7977
7979	1	112	12250	7978
7980	2	112	12251	7978
7981	1	112	12252	7980
7982	2	112	12253	7980
7983	3	112	12254	7980
7984	3	112	12255	7977
7985	2	112	12267	7984
7986	3	112	12269	7985
7987	4	112	12271	7985
7988	1	112	12273	7987
7989	1	112	12274	7988
7990	2	112	14925	7988
7991	3	112	12285	7988
7992	2	112	12289	7987
7993	3	112	12291	7992
7994	4	112	12294	7992
7995	5	112	12296	7992
7996	3	112	12256	7984
7997	4	112	12257	7996
7998	5	112	12263	7996
7999	8	112	12298	7976
8000	3	112	12299	7999
8001	3	112	12301	8000
8002	4	112	12304	8000
8003	5	112	12309	8000
8004	4	112	12310	7999
8005	5	112	12312	8004
8006	6	112	12314	8004
8007	9	112	12340	7976
8008	4	112	12355	8007
8009	5	112	12349	8007
8010	6	112	12350	8009
8011	7	112	12352	8009
8012	8	112	12353	8009
8013	6	112	15881	8007
8014	8	112	15882	8013
8015	5	112	15885	8014
8016	6	112	12342	8014
8017	2	112	12345	8016
8018	3	112	12346	8016
8201	5	18367	12312	8200
8202	6	18367	12314	8200
8203	9	18367	12340	8172
8204	4	18367	12355	8203
8205	5	18367	12349	8203
8206	6	18367	12350	8205
8207	7	18367	12352	8205
8208	8	18367	12353	8205
7773	1	-3344	4782	\N
7774	1	-3344	4761	7773
7775	1	-3344	56421	7774
7776	1	-3344	56422	7775
7777	2	-3344	56423	7775
7778	2	-3344	55986	7774
7779	2	-3344	55989	7778
7780	3	-3344	55987	7778
7781	4	-3344	55988	7778
7782	3	-3344	50584	7774
7783	4	-3344	50586	7782
7784	5	-3344	50585	7782
7785	4	-3344	52838	7774
7786	5	-3344	52839	7785
8019	9	112	15883	8013
8020	6	112	15884	8019
8021	7	112	12348	8019
8022	2	112	4788	\N
8023	2	112	12347	8022
8024	3	112	12351	8022
8025	3	112	4793	\N
8026	3	112	12354	8025
7791	5	-3344	52274	7789
7792	5	-3344	52277	7791
7793	2	-3344	52279	7792
7794	3	-3344	52278	7792
7795	6	-3344	52276	7791
7796	2	-3344	4788	\N
7797	2	-3344	52283	7796
7798	3	-3344	52282	7796
7799	4	-3344	52281	7796
7800	3	-3344	4793	\N
7801	4	-3344	52280	7800
7863	6	-103344	17520	7862
7864	7	-103344	17521	7862
7865	2	-103344	17525	7864
7866	3	-103344	17522	7864
7867	5	-103344	17523	7866
7868	6	-103344	17524	7866
7869	9	-103344	17526	7861
7870	7	-103344	17527	7869
7871	8	-103344	17528	7869
7872	2	-103344	4788	\N
7873	2	-103344	17531	7872
7874	3	-103344	17530	7872
7875	3	-103344	4793	\N
7876	3	-103344	17532	7875
8209	6	18367	15881	8203
8210	8	18367	15882	8209
8211	5	18367	15885	8210
8212	6	18367	12342	8210
8213	2	18367	12345	8212
8214	3	18367	12346	8212
8215	9	18367	15883	8209
8216	6	18367	15884	8215
8217	7	18367	12348	8215
8218	2	18367	4788	\N
8219	2	18367	12347	8218
8220	3	18367	12351	8218
8221	3	18367	4793	\N
8222	3	18367	12354	8221
8278	7	42357	17514	8276
8279	6	42357	17515	8278
8280	7	42357	17517	8278
8281	8	42357	17516	8278
8282	8	42357	17518	8276
8283	8	42357	17519	8282
8284	6	42357	17520	8283
8285	7	42357	17521	8283
8286	2	42357	17525	8285
8287	3	42357	17522	8285
8288	5	42357	17523	8287
8289	6	42357	17524	8287
8290	9	42357	17526	8282
8291	7	42357	17527	8290
8292	8	42357	17528	8290
8293	2	42357	4788	\N
8294	2	42357	17531	8293
8295	3	42357	17530	8293
8296	3	42357	4793	\N
8297	3	42357	17532	8296
8298	1	200091	4782	\N
8299	1	200091	6161	8298
8300	1	200091	54525	8299
8301	1	200091	54531	8300
8302	2	200091	54530	8300
8303	3	200091	54529	8300
8304	4	200091	54528	8300
8305	5	200091	54527	8300
8306	6	200091	54526	8300
8307	2	200091	51854	8299
8308	3	200091	51853	8299
8309	4	200091	51199	8299
8310	5	200091	56428	8299
8095	1	113	22601	8094
8096	1	113	50434	8095
8097	2	113	50435	8095
8098	3	113	50436	8095
8099	4	113	50437	8095
8100	2	113	22603	8094
8101	6	113	5096	8089
8102	7	113	5097	8089
8103	8	113	7321	8089
8104	2	113	5099	8088
8105	8	113	5665	8104
8106	9	113	5492	8104
8107	10	113	5126	8104
8108	11	113	5127	8104
8109	2	113	5493	8108
8110	4	113	5494	8109
8111	1	113	5495	8110
8112	2	113	5496	8110
8113	3	113	5497	8110
8114	5	113	5498	8109
8115	6	113	5499	8109
8116	3	113	5500	8115
8117	1	113	5501	8116
8118	2	113	5502	8116
8119	1	113	5503	8118
8120	1	113	5504	8119
8121	2	113	5505	8119
8122	3	113	5507	8119
8123	2	113	5508	8118
8124	3	113	5509	8123
8125	4	113	5510	8123
8126	5	113	5511	8123
8127	4	113	5512	8115
8128	2	113	5513	8127
8129	3	113	5514	8127
8130	3	113	5515	8108
8131	6	113	5516	8130
8132	7	113	5517	8130
8133	8	113	5518	8130
8134	9	113	5519	8130
8135	4	113	5520	8108
8136	9	113	5521	8135
8137	4	113	5522	8136
8138	5	113	5523	8136
8139	6	113	5524	8136
8140	10	113	5525	8135
8141	11	113	5862	8135
8142	12	113	5526	8135
8143	13	113	5527	8135
8144	2	113	4788	\N
8145	2	113	13161	8144
8146	3	113	4793	\N
8147	2	113	4794	8146
7640	1	-1110	4782	\N
7641	1	-1110	4761	7640
7642	1	-1110	5091	7641
7643	2	-1110	5092	7641
7644	3	-1110	5093	7641
7645	4	-1110	5094	7641
7646	5	-1110	22602	7641
7647	1	-1110	22601	7646
7648	1	-1110	50434	7647
7649	2	-1110	50435	7647
7650	3	-1110	50436	7647
7651	4	-1110	50437	7647
7652	2	-1110	22603	7646
7653	6	-1110	5096	7641
7654	7	-1110	5097	7641
7655	8	-1110	7321	7641
7656	2	-1110	5099	7640
7657	8	-1110	5665	7656
7658	9	-1110	5492	7656
8311	6	200091	56431	8310
8312	7	200091	56430	8310
8313	8	200091	56429	8310
8314	6	200091	51847	8299
8315	8	200091	51849	8314
8316	1	200091	51852	8315
8317	2	200091	51851	8315
8318	3	200091	51850	8315
8319	9	200091	51844	8314
8320	7	200091	55483	8299
8321	2	200091	8051	8298
8322	7	200091	50177	8321
8323	9	200091	54459	8322
7659	10	-1110	5126	7656
7660	11	-1110	5127	7656
7661	2	-1110	5493	7660
7662	4	-1110	5494	7661
7663	1	-1110	5495	7662
7664	2	-1110	5496	7662
7665	3	-1110	5497	7662
7666	5	-1110	5498	7661
7667	6	-1110	5499	7661
7668	3	-1110	5500	7667
7669	1	-1110	5501	7668
7670	2	-1110	5502	7668
7671	1	-1110	5503	7670
7672	1	-1110	5504	7671
7673	2	-1110	5505	7671
7674	3	-1110	5507	7671
7675	2	-1110	5508	7670
7676	3	-1110	5509	7675
7677	4	-1110	5510	7675
7678	5	-1110	5511	7675
7679	4	-1110	5512	7667
7680	2	-1110	5513	7679
7681	3	-1110	5514	7679
7682	3	-1110	5515	7660
7683	6	-1110	5516	7682
7684	7	-1110	5517	7682
7685	8	-1110	5518	7682
7686	9	-1110	5519	7682
7687	4	-1110	5520	7660
7688	9	-1110	5521	7687
7689	4	-1110	5522	7688
7690	5	-1110	5523	7688
7691	6	-1110	5524	7688
7692	10	-1110	5525	7687
7693	11	-1110	5862	7687
7694	12	-1110	5526	7687
7695	13	-1110	5527	7687
7696	2	-1110	4788	\N
7697	2	-1110	13161	7696
7698	3	-1110	4793	\N
7699	2	-1110	4794	7698
7700	4	-1110	4795	\N
7581	5	-1618	12239	7579
7582	7	-1618	12243	7566
7583	8	-1618	12245	7566
7584	2	-1618	12246	7565
7585	8	-1618	12337	7584
7586	5	-1618	12341	7585
7587	6	-1618	12338	7585
7588	7	-1618	12344	7585
7589	9	-1618	12247	7584
7590	7	-1618	12248	7589
7591	2	-1618	12249	7590
7592	1	-1618	12250	7591
7593	2	-1618	12251	7591
7594	1	-1618	12252	7593
7595	2	-1618	12253	7593
7596	3	-1618	12254	7593
7597	3	-1618	12255	7590
7598	2	-1618	12267	7597
7599	3	-1618	12269	7598
7600	4	-1618	12271	7598
7601	1	-1618	12273	7600
7602	1	-1618	12274	7601
7603	2	-1618	14925	7601
7604	3	-1618	12285	7601
7605	2	-1618	12289	7600
7606	3	-1618	12291	7605
7607	4	-1618	12294	7605
7608	5	-1618	12296	7605
7609	3	-1618	12256	7597
7610	4	-1618	12257	7609
7611	5	-1618	12263	7609
7612	8	-1618	12298	7589
7613	3	-1618	12299	7612
7614	3	-1618	12301	7613
7615	4	-1618	12304	7613
7616	5	-1618	12309	7613
7617	4	-1618	12310	7612
7618	5	-1618	12312	7617
7619	6	-1618	12314	7617
7620	9	-1618	12340	7589
7621	4	-1618	12355	7620
7622	5	-1618	12349	7620
7623	6	-1618	12350	7622
7624	7	-1618	12352	7622
7625	8	-1618	12353	7622
7626	6	-1618	15881	7620
7627	8	-1618	15882	7626
7628	5	-1618	15885	7627
7629	6	-1618	12342	7627
7630	2	-1618	12345	7629
7631	3	-1618	12346	7629
7632	9	-1618	15883	7626
7633	6	-1618	15884	7632
7634	7	-1618	12348	7632
7635	2	-1618	4788	\N
7636	2	-1618	12347	7635
7637	3	-1618	12351	7635
7638	3	-1618	4793	\N
7639	3	-1618	12354	7638
7565	1	-1618	4782	\N
7566	1	-1618	12233	7565
7567	1	-1618	12242	7566
7568	2	-1618	12244	7566
7569	3	-1618	12234	7566
7570	1	-1618	12235	7569
7571	2	-1618	12236	7569
7572	4	-1618	12240	7566
7573	5	-1618	22602	7566
7574	2	-1618	22605	7573
7575	1	-1618	50438	7574
7576	2	-1618	50439	7574
7577	3	-1618	22604	7573
7578	4	-1618	22603	7573
7579	6	-1618	12237	7566
7580	4	-1618	12238	7579
8223	1	42357	4782	\N
8224	1	42357	17444	8223
8225	1	42357	17470	8224
8226	2	42357	17468	8224
8227	3	42357	17446	8224
8228	4	42357	17466	8224
8229	5	42357	17454	8224
8230	1	42357	17455	8229
8231	2	42357	17457	8229
8232	3	42357	17461	8229
8233	6	42357	17448	8224
8234	3	42357	17451	8233
8235	4	42357	17450	8233
8236	7	42357	17464	8224
8237	2	42357	17472	8223
8238	7	42357	17473	8237
8239	4	42357	17478	8238
8240	5	42357	17479	8238
8241	6	42357	17475	8238
8242	7	42357	17477	8238
8243	8	42357	17480	8237
8244	7	42357	17481	8243
8245	1	42357	17482	8244
8246	1	42357	17489	8245
8247	2	42357	17488	8245
8248	3	42357	17487	8245
8249	4	42357	17490	8245
8250	5	42357	17483	8245
8251	1	42357	17484	8250
8252	2	42357	17486	8250
8253	3	42357	17485	8250
8254	2	42357	17491	8244
8255	5	42357	17492	8254
8256	3	42357	17493	8255
8257	4	42357	17494	8255
8258	1	42357	17495	8257
8259	1	42357	17497	8258
8260	2	42357	17498	8258
8261	3	42357	17496	8258
8262	2	42357	17499	8257
8263	3	42357	17501	8262
8324	3	200091	54461	8323
8325	4	200091	54460	8323
8326	8	200091	50228	8321
8327	9	200091	52680	8326
8328	4	200091	52694	8327
8329	5	200091	52689	8327
8330	6	200091	56432	8327
8331	1	200091	56433	8330
8332	2	200091	56434	8330
8333	3	200091	56435	8330
8334	7	200091	52728	8327
8335	10	200091	52679	8326
8336	7	200091	52734	8335
8337	3	200091	52736	8336
8338	1	200091	52740	8337
8339	2	200091	52739	8337
8340	3	200091	52738	8337
8341	4	200091	52737	8337
8342	4	200091	52735	8336
8343	4	200091	52747	8342
8344	1	200091	52758	8343
8345	2	200091	52748	8343
8346	1	200091	52750	8345
8347	1	200091	52757	8346
8348	2	200091	52756	8346
8349	3	200091	52755	8346
8350	2	200091	52749	8345
8351	3	200091	52754	8350
8352	4	200091	52753	8350
8353	5	200091	52751	8350
8354	5	200091	52743	8342
8355	2	200091	52745	8354
8356	3	200091	52744	8354
8357	8	200091	52729	8335
8358	4	200091	52733	8357
8359	5	200091	52732	8357
8360	6	200091	52731	8357
8361	7	200091	52730	8357
8362	9	200091	52722	8335
8363	7	200091	52726	8362
8364	8	200091	52723	8362
8365	2	200091	4788	\N
8366	2	200091	54514	8365
8367	3	200091	54515	8365
8368	3	200091	4793	\N
8369	3	200091	54520	8368
8399	1	200034	4782	\N
8400	1	200034	4761	8399
8401	1	200034	56421	8400
8402	1	200034	56422	8401
8403	2	200034	56423	8401
8404	2	200034	55986	8400
8405	2	200034	55989	8404
8406	3	200034	55987	8404
8407	4	200034	55988	8404
8408	3	200034	50584	8400
8409	4	200034	50586	8408
8410	5	200034	50585	8408
8411	4	200034	63225	8400
8412	5	200034	63277	8411
8413	1	200034	63229	8412
8414	2	200034	63228	8412
8415	2	200034	4781	8399
8416	4	200034	52275	8415
8417	5	200034	52274	8415
8418	5	200034	52277	8417
8419	2	200034	52279	8418
8420	3	200034	52278	8418
8421	6	200034	52276	8417
8422	2	200034	4788	\N
8423	2	200034	52283	8422
8424	3	200034	52282	8422
8425	4	200034	52281	8422
8426	3	200034	4793	\N
8427	4	200034	52280	8426
8619	5	10323	62279	8618
8620	6	10323	62277	8618
8621	2	10323	4788	\N
8622	2	10323	62384	8621
8623	3	10323	62385	8621
8624	3	10323	4793	\N
8625	3	10323	62386	8624
8370	1	-10322	4782	\N
8371	1	-10322	4761	8370
8372	1	-10322	56421	8371
8373	1	-10322	56422	8372
8374	2	-10322	56423	8372
8375	2	-10322	55986	8371
8376	2	-10322	55989	8375
8377	3	-10322	55987	8375
8378	4	-10322	55988	8375
8379	3	-10322	50584	8371
8380	4	-10322	50586	8379
8381	5	-10322	50585	8379
8382	4	-10322	63225	8371
8383	5	-10322	63277	8382
8384	1	-10322	63229	8383
8385	2	-10322	63228	8383
8386	2	-10322	4781	8370
8387	4	-10322	62847	8386
8388	5	-10322	61839	8386
8389	5	-10322	61842	8388
8390	2	-10322	61846	8389
8391	3	-10322	61845	8389
8392	6	-10322	61841	8388
8393	2	-10322	4788	\N
8394	2	-10322	52283	8393
8395	3	-10322	52282	8393
8396	4	-10322	52281	8393
8397	3	-10322	4793	\N
8398	4	-10322	52280	8397
8428	1	-10323	4782	\N
8429	1	-10323	6161	8428
8430	1	-10323	62910	8429
8431	1	-10323	62916	8430
8432	2	-10323	62915	8430
8433	3	-10323	62914	8430
8434	4	-10323	62913	8430
8435	5	-10323	62912	8430
8436	6	-10323	62911	8430
8437	2	-10323	62901	8429
8438	3	-10323	62902	8429
8439	4	-10323	62909	8429
8440	5	-10323	62883	8429
8441	6	-10323	62886	8440
8442	7	-10323	62885	8440
8443	8	-10323	62884	8440
8444	6	-10323	62903	8429
8445	8	-10323	62905	8444
8446	1	-10323	62908	8445
8447	2	-10323	62907	8445
8448	3	-10323	62906	8445
8449	9	-10323	62904	8444
8450	7	-10323	62879	8429
8451	8	-10323	62880	8429
8452	9	-10323	62882	8451
8453	10	-10323	62881	8451
8454	2	-10323	8051	8428
8455	8	-10323	50177	8454
8456	10	-10323	62869	8455
8457	3	-10323	62871	8456
8458	9	-10323	50228	8454
8459	10	-10323	62355	8458
8460	11	-10323	62273	8458
8461	3	-10323	62289	8460
8462	1	-10323	62298	8461
8463	1	-10323	62372	8462
8464	2	-10323	62371	8462
8465	3	-10323	62315	8462
8466	2	-10323	62290	8461
8467	3	-10323	62373	8466
8468	1	-10323	62383	8467
8469	2	-10323	62374	8467
8470	1	-10323	62379	8469
8471	1	-10323	62382	8470
8472	2	-10323	62381	8470
8473	3	-10323	62380	8470
8474	2	-10323	62375	8469
8475	3	-10323	62378	8474
8476	4	-10323	62377	8474
8477	5	-10323	62376	8474
8478	4	-10323	62299	8466
8479	2	-10323	62301	8478
8480	3	-10323	62300	8478
8481	4	-10323	62280	8460
8482	2	-10323	62286	8481
8483	3	-10323	62283	8481
8484	4	-10323	62282	8481
8485	5	-10323	62281	8481
8486	5	-10323	62275	8460
8487	5	-10323	62279	8486
8488	6	-10323	62277	8486
8489	2	-10323	4788	\N
8490	2	-10323	62384	8489
8491	3	-10323	62385	8489
8492	3	-10323	4793	\N
8493	3	-10323	62386	8492
8626	1	10322	4782	\N
8627	1	10322	4761	8626
8628	1	10322	63221	8627
8629	1	10322	63222	8628
8630	2	10322	63223	8628
8631	2	10322	63233	8627
8632	2	10322	63235	8631
8633	3	10322	63236	8631
8634	4	10322	63234	8631
8635	3	10322	63230	8627
8636	4	10322	63232	8635
8637	5	10322	63231	8635
8638	4	10322	63225	8627
8639	5	10322	63277	8638
8640	1	10322	63229	8639
8641	2	10322	63228	8639
8642	2	10322	4781	8626
8643	4	10322	62847	8642
8644	5	10322	61839	8642
8645	5	10322	61842	8644
8646	2	10322	61846	8645
8647	3	10322	61845	8645
8648	6	10322	61841	8644
8649	2	10322	4788	\N
8650	2	10322	52283	8649
8651	3	10322	52282	8649
8652	4	10322	52281	8649
8653	3	10322	4793	\N
8654	4	10322	52280	8653
8494	1	-123	4782	\N
8495	1	-123	6161	8494
8496	1	-123	62910	8495
8497	1	-123	62916	8496
8498	2	-123	62915	8496
8499	3	-123	62914	8496
8500	4	-123	62913	8496
8501	5	-123	62912	8496
8502	6	-123	62911	8496
8503	2	-123	62901	8495
8504	3	-123	62902	8495
8505	4	-123	62909	8495
8506	5	-123	62883	8495
8507	6	-123	62886	8506
8508	7	-123	62885	8506
8509	8	-123	62884	8506
8510	6	-123	62903	8495
8511	8	-123	62905	8510
8512	1	-123	62908	8511
8513	2	-123	62907	8511
8514	3	-123	62906	8511
8515	9	-123	62904	8510
8516	7	-123	62879	8495
8517	8	-123	62880	8495
8518	9	-123	62882	8517
8519	10	-123	62881	8517
8520	2	-123	8051	8494
8521	8	-123	50177	8520
8522	10	-123	62869	8521
8523	3	-123	62871	8522
8524	9	-123	50228	8520
8525	10	-123	62355	8524
8526	11	-123	62273	8524
8527	3	-123	62289	8526
8528	1	-123	62298	8527
8529	1	-123	62372	8528
8530	2	-123	62371	8528
8531	3	-123	62315	8528
8532	2	-123	62290	8527
8533	3	-123	62373	8532
8534	1	-123	62383	8533
8535	2	-123	62374	8533
8536	1	-123	62379	8535
8537	1	-123	62382	8536
8538	2	-123	62381	8536
8539	3	-123	62380	8536
8540	2	-123	62375	8535
8541	3	-123	62378	8540
8542	4	-123	62377	8540
8543	5	-123	62376	8540
8544	4	-123	62299	8532
8545	2	-123	62301	8544
8546	3	-123	62300	8544
8547	4	-123	62280	8526
8548	2	-123	62286	8547
8549	3	-123	62283	8547
8550	4	-123	62282	8547
8551	5	-123	62281	8547
8552	5	-123	62275	8526
8553	5	-123	62279	8552
8554	6	-123	62277	8552
8555	2	-123	4788	\N
8556	2	-123	62384	8555
8557	3	-123	62385	8555
8558	3	-123	4793	\N
8559	3	-123	62386	8558
\.
COPY s335141.semester_rpd (id, number_from_start, credits, id_rpd) FROM stdin;
3773	1	4	3951
3406	1	4	18034
3408	1	4	13675
3440	1	3	35211
4268	1	4	53697
4269	1	7	53992
4270	1	4	53700
3464	1	6	18068
4271	1	4	53696
3490	1	3	18086
3491	2	3	18086
3475	1	6	18080
3494	1	4	6121
4272	1	4	53701
3368	1	4	33957
3382	1	3	30498
3770	1	3	20127
3771	2	3	20127
3462	1	6	18066
3456	1	3	18062
3482	1	6	36237
3459	1	3	7068
3370	1	0	16560
3463	1	6	18067
3466	1	6	18070
4302	1	3	56551
4303	1	3	56553
4304	1	3	56552
4305	1	3	56554
4306	1	3	56555
3465	1	6	18069
4292	1	3	56219
4293	1	3	55851
4294	2	3	55851
4295	1	3	55852
4296	2	3	55852
4297	1	3	56123
4298	1	3	56122
4299	1	3	56116
4300	1	3	56547
4301	1	3	56548
4307	1	4	58772
4308	1	3	58768
4309	1	3	57871
4310	1	3	57870
4311	1	3	57869
4312	1	3	57868
4313	1	5	57876
4315	1	5	57883
4316	1	5	57882
4317	1	4	57880
4077	1	3	36822
4318	1	3	54764
4319	1	3	56178
4320	1	3	56176
4321	1	3	57886
4322	1	3	57884
4323	1	3	57881
4314	1	3	57872
4324	1	6	57885
4325	1	18	59495
4073	1	1	38269
4074	2	2	38269
4078	1	3	33340
3772	1	3	31772
3528	2	6	35220
3525	1	6	35219
3526	2	3	35219
3523	1	3	35218
3524	2	6	35218
4217	1	3	52372
4273	1	3	57873
4148	1	3	53684
3534	1	9	31769
3535	1	6	31770
4223	1	3	53691
4226	1	5	52376
4225	1	4	52375
4229	1	4	53693
3554	1	1	1
4144	1	4	53681
4068	1	4	53680
4143	1	3	53677
4232	1	3	53676
4216	1	3	53991
3915	1	3	16544
3916	1	3	16543
4085	1	6	35978
4086	1	3	35977
3917	1	3	16542
4235	1	6	52344
3918	1	3	16540
4088	1	6	16985
4236	1	6	52343
4149	1	6	52342
4238	1	3	52341
3919	1	3	16539
3920	1	1	16550
4093	1	6	35981
4067	1	3	53707
4237	1	3	52340
3921	1	3	16568
4097	1	3	16994
3536	1	6	31771
3537	1	6	16977
4240	1	6	52339
4153	1	3	21452
4154	2	3	21452
4155	1	3	19045
4239	1	6	52338
3983	1	6	36263
3543	1	6	31775
4080	1	3	36728
4099	1	6	16991
4081	1	3	36729
4091	1	3	31776
3514	1	6	35214
4156	1	9	29980
4157	1	6	29433
4158	1	6	29435
4089	1	6	16982
3540	1	3	10121
3515	1	6	35213
3516	2	3	35213
4090	1	3	1001
3518	1	6	18098
3520	1	3	18076
3521	2	6	18076
3517	1	6	18101
3532	1	6	35222
3522	1	3	35217
3529	1	6	18096
4095	1	6	16996
3530	1	3	35221
3531	2	6	35221
3527	1	6	35220
4195	1	3	51292
4200	1	3	50666
4207	1	4	53673
4209	1	3	53674
4241	1	6	52336
3722	2	0	16560
3723	3	0	16560
3724	4	0	16560
3725	5	0	16560
3726	6	0	16560
3727	2	1	16559
4326	1	3	52517
3512	1	3	35215
3513	2	6	35215
4079	1	3	34013
4196	1	3	51302
4204	1	3	51887
4205	1	3	51841
4206	1	3	51843
4197	1	3	51295
4198	1	3	51294
4199	1	3	51293
4201	1	3	50664
4202	1	3	51290
4203	1	3	50277
3989	1	3	35368
4211	1	4	52374
4210	1	5	52373
4214	1	4	52354
4213	1	4	52353
4212	1	4	52352
4274	1	4	57874
4227	1	3	51900
4228	1	3	51899
4146	1	3	53683
4233	1	3	51923
4220	1	3	51920
4234	1	3	51918
4082	1	3	30285
3961	2	3	21451
4189	1	3	51299
3984	1	2	35553
3965	1	6	29996
3986	1	3	35862
3987	1	3	31283
3988	1	3	2263
3978	1	6	18097
3962	1	3	18063
3403	2	3	18036
4002	1	3	19747
4042	1	6	36257
4030	1	6	36231
4275	1	4	58000
4023	1	3	36228
3990	1	3	35861
4161	1	2	52127
4038	1	3	35856
3991	1	4	36196
4162	1	2	52327
3995	1	4	36199
4043	1	6	36258
4005	1	4	36209
4167	1	2	52131
4168	1	2	52324
4059	1	3	36253
4052	1	3	36248
3967	1	3	32911
4053	1	3	36247
4169	1	2	52130
4024	1	3	36227
3968	1	3	21455
3996	1	3	36200
4008	1	3	36208
4173	2	3	53919
4039	1	3	36233
3998	1	3	37118
4060	1	3	36250
4004	1	3	36211
4003	1	3	36210
3969	2	3	21455
4061	1	6	36251
4028	1	3	36230
4170	1	2	52323
4026	1	3	35853
3992	1	3	36202
4044	1	3	36245
4006	1	4	36206
4029	1	3	37119
3999	1	3	35844
4045	1	6	36246
4007	1	4	36207
4032	1	3	35855
4025	1	3	36225
4329	1	3	51234
4330	1	6	59496
4063	1	6	36261
3533	1	3	16291
4021	1	3	36224
3970	1	3	21453
4035	1	3	36236
4009	1	5	36203
4054	1	3	36255
3956	1	3	7957
4327	1	3	36730
4186	1	3	53921
4174	1	3	53918
4010	1	4	36204
4013	1	4	36213
4175	2	3	53918
4163	1	2	52128
4019	1	3	36215
4000	1	3	35845
4062	1	9	36262
4187	2	3	53921
4046	1	6	36242
3957	1	3	7130
4164	1	2	52326
4033	1	4	38324
4179	2	3	53916
4031	1	3	31764
4190	1	3	51298
4047	1	6	36244
4012	1	4	36212
3958	1	3	21447
4191	1	3	51297
4176	1	3	53917
4276	1	3	57875
3976	1	3	18100
3959	1	3	18039
4014	1	3	36220
3977	2	6	18100
3519	2	6	18098
4055	1	6	36256
3960	1	3	21451
4049	1	6	36243
3971	1	4	18091
3972	2	6	18091
4056	1	6	36252
3973	1	5	18087
3974	1	4	18082
3975	2	4	18082
4192	1	3	51296
4159	1	2	52126
4193	1	3	50667
4015	1	3	36219
4184	1	3	53920
4177	2	3	53917
4178	1	3	53916
4036	1	3	37121
4037	1	3	36232
4057	1	6	36254
4185	2	3	53920
4058	1	6	36249
4280	1	5	58001
4040	1	3	36259
4041	1	3	36260
4172	1	3	53919
4048	1	3	36239
4051	1	3	36241
4171	1	3	52215
3993	1	4	36201
4001	1	3	19843
4278	1	6	57877
4180	1	3	53915
4181	2	3	53915
4020	1	3	36214
4182	1	3	53914
4183	2	3	53914
4188	1	3	51300
4016	1	3	36218
4022	1	3	36223
4027	1	3	36229
3997	1	4	36198
4011	1	4	36205
4194	1	3	51301
4165	1	2	52129
4328	1	3	56142
4166	1	2	52325
4279	1	3	58143
4050	1	6	36240
4018	1	3	36216
4017	1	3	36217
3994	1	4	36197
4160	1	2	52328
4277	1	5	57879
3966	1	3	37120
4083	1	3	16464
3395	1	3	9326
3396	1	3	21052
4281	1	3	54491
3398	1	3	34617
3949	2	3	36569
3399	1	4	20123
3425	1	5	18044
3426	2	4	18044
3427	1	5	18043
4283	1	3	54488
3428	2	5	18043
3429	3	5	18043
4282	1	3	54487
4252	1	3	52371
4286	1	3	54859
3439	1	3	35212
3401	1	3	18037
3442	1	4	34377
3448	1	4	34380
3985	2	2	35553
3400	1	2	18040
3365	1	4	33954
3364	1	4	33953
3363	1	4	33951
3950	1	3	36568
3951	2	3	36568
4208	1	3	53682
3409	1	3	7799
3954	1	3	36566
3955	2	3	36566
3982	1	3	30175
3402	1	4	18036
3383	1	3	29867
3922	1	3	36646
3393	1	3	33341
3392	1	3	30182
3391	1	3	30181
3388	1	3	30178
3404	1	4	18035
3405	2	4	18035
3387	1	3	30177
3542	1	3	31773
3923	2	3	36646
3415	1	3	21137
3924	1	3	36645
4242	1	6	52337
4244	1	3	52335
4243	1	3	52334
4147	1	3	53678
4075	3	3	38269
4092	1	3	9189
4253	1	3	52332
4254	1	3	52331
3449	1	4	34379
3367	1	4	33956
3366	1	4	33955
3416	1	3	21013
3417	1	3	19905
3418	1	3	19903
3407	1	3	18033
3419	1	3	19745
3410	1	3	7118
3412	1	3	31768
3413	1	3	30195
3414	2	3	30195
3420	1	3	19743
3421	1	3	19742
3925	2	3	36645
3926	1	3	36644
4215	1	6	53690
3927	2	3	36644
3928	1	3	36643
3929	2	3	36643
3930	1	3	36642
3931	2	3	36642
4255	1	3	52330
4284	1	3	54500
3932	1	3	36641
3933	2	3	36641
3934	1	3	36640
3935	2	3	36640
3384	1	3	36639
4285	1	3	54474
4287	1	3	54499
3390	1	3	30180
3389	1	3	30179
4256	1	3	52329
4247	1	3	21041
3386	1	3	30176
3394	1	3	30183
3385	2	3	36639
3936	1	3	36575
4094	1	3	35980
3937	2	3	36575
3938	1	3	36574
3939	2	3	36574
3940	1	3	36573
4096	1	6	16995
4248	1	3	52346
4084	1	6	35979
3538	1	3	16978
3422	1	4	18046
3423	1	4	18045
3424	2	4	18045
3941	2	3	36573
3942	1	3	36572
3943	2	3	36572
3944	1	3	36571
3945	2	3	36571
3946	1	3	36570
3947	2	3	36570
3948	1	3	36569
4251	1	3	52347
4098	1	3	16993
4100	1	6	35986
4101	1	9	35985
3397	1	3	30184
3369	1	2	5895
3376	1	1	16559
3728	3	1	16559
4102	1	6	35984
4076	1	3	36738
4245	1	3	52211
4246	1	3	51303
4103	1	15	35983
4104	1	6	35982
4249	1	6	52345
4250	1	3	52333
4105	1	6	35987
4087	1	6	16988
3541	1	3	16984
3539	1	3	16649
3952	1	3	36567
3953	2	3	36567
3470	1	3	38205
3453	1	3	31762
3499	1	3	35818
3500	1	3	35819
3479	1	3	16768
3483	1	5	36234
3502	1	3	2086
3478	1	3	18073
3458	1	3	18060
4231	1	3	53687
3510	1	3	18095
3511	1	3	35216
4142	1	3	53679
3430	1	3	18042
3481	1	6	37122
3485	1	3	21192
3441	1	3	35210
3471	1	4	38204
3472	2	5	38204
3477	1	3	18075
3431	1	3	5967
3432	2	3	5967
3488	1	3	18090
3433	1	3	16579
3434	1	3	16580
3445	1	3	18048
3435	1	3	16581
3436	1	3	16582
3489	1	3	18089
3492	1	3	18084
3437	1	3	16583
3444	1	3	18053
3438	1	3	16584
3493	1	4	7841
3495	1	4	5917
3460	1	3	826
4266	1	5	53719
3452	1	3	18058
3484	1	3	29227
4219	1	3	52349
3501	1	3	18094
3480	1	3	18079
3447	1	3	2243
3503	1	3	5902
3487	1	3	19037
3504	1	3	3312
3507	1	6	18102
3454	1	3	18065
4034	1	3	36235
3446	1	3	18032
3476	1	6	18078
4288	1	3	56559
3455	1	3	18064
4289	1	3	56563
4290	1	3	57386
4291	1	3	57389
3496	1	3	31767
3497	2	3	31767
3498	1	3	30209
3474	1	3	30185
4145	1	6	53685
3473	1	6	31763
3443	1	3	32187
4222	1	3	53695
4230	1	3	53689
3450	1	3	34378
3486	1	4	21190
4267	1	3	53723
3505	1	3	20393
3506	2	3	20393
3508	1	6	18099
3509	2	6	18099
3468	1	4	18071
3469	2	4	18071
3964	1	6	36221
4265	1	4	53445
3411	1	4	5959
4218	1	3	53698
3467	1	3	18072
3457	1	3	18061
3451	1	3	31765
4221	1	6	53694
3963	1	6	36222
3461	1	6	31766
4224	1	3	53686
\.
COPY s335141.specialties (code, name) FROM stdin;
54.03.01	Дизайн
09.03.04	Программная инженерия
 44.03.04	Профессиональное обучение
\.
COPY s335141.students (id, name, group_id) FROM stdin;
1	Ivan	\N
\.
COPY s335141.track_specialty (id_track, code) FROM stdin;
16	09.03.04
17	09.03.04
18	09.03.04
19	09.03.04
20	09.03.04
21	 44.03.04
22	09.03.04
23	09.03.04
24	09.03.04
25	09.03.04
26	09.03.04
27	09.03.04
28	09.03.04
29	09.03.04
30	 44.03.04
31	 44.03.04
32	09.03.04
33	09.03.04
34	09.03.04
35	09.03.04
36	 44.03.04
37	 44.03.04
38	54.03.01
39	09.03.04
40	09.03.04
41	09.03.04
42	 44.03.04
43	09.03.04
45	09.03.04
46	09.03.04
47	09.03.04
48	09.03.04
49	09.03.04
50	09.03.04
51	09.03.04
52	09.03.04
53	09.03.04
54	09.03.04
55	09.03.04
56	09.03.04
57	 44.03.04
58	09.03.04
59	09.03.04
60	09.03.04
61	09.03.04
62	 44.03.04
63	09.03.04
64	09.03.04
65	09.03.04
66	09.03.04
67	 44.03.04
68	09.03.04
69	09.03.04
70	09.03.04
71	09.03.04
72	09.03.04
73	54.03.01
74	54.03.01
75	54.03.01
76	09.03.04
77	09.03.04
78	54.03.01
79	54.03.01
80	54.03.01
81	54.03.01
82	54.03.01
83	54.03.01
84	54.03.01
85	09.03.04
86	09.03.04
87	54.03.01
88	54.03.01
89	54.03.01
90	09.03.04
91	09.03.04
92	09.03.04
93	09.03.04
\.
COPY s335141.tracks (id, name, number, count_limit, id_section) FROM stdin;
1	test	1	\N	\N
2	9	9	\N	\N
4	Трек тестовый	6	\N	\N
3	Разработка компьютерных игр	1	\N	\N
5	Разработка компьютерных игр	1	\N	\N
6	3D-визуализация	2	\N	\N
7	Дизайн графических и интерфейсов	3	\N	\N
8	Разработка графических в веб-приложений	4	\N	\N
9	Компьютерные игры в образованиии	5	\N	\N
10	Искусственный интеллект в образовании	6	\N	\N
11	Разработка компьютерных игр	1	\N	\N
16	Разработка компьютерных игр КТвД 24	11	\N	\N
17	Разработка компьютерных игр КТвД 24	1	\N	\N
18	Разработка компьютерных игр КТвД 24	1	\N	\N
19	3D-визуализация КТвД 24	2	\N	\N
20	Дизайн графических и интерфейсов КТвД 24	3	\N	\N
21	Компьютерные игры в образованиии КТвД 24	5	\N	\N
22	Разработка компьютерных игр	1	\N	7671
23	3D-визуализация	2	\N	7675
24	Дизайн графических интерфейсов	3	\N	7679
25	Разработка графических и веб-приложений	4	\N	7682
26	Разработка компьютерных игр	1	\N	7601
27	3D-визуализация	2	\N	7605
28	Дизайн графических интерфейсов	3	\N	7609
29	Разработка графических и веб-приложений	4	\N	7612
30	Компьютерные игры в образованиии	5	\N	7627
31	Искусственный интеллект в образовании	6	\N	7632
38	Дизайн компьютерных игр КТвД 25	1	\N	7749
39	3D-визуализация КТвД 25	2	\N	7753
40	Дизайн графических интерфейсов КТвД 25	3	\N	7757
41	Разработка графических и веб-приложений КТвД 25	4	\N	7760
42	Анимация и развивающие приложения КТвД 25	5	\N	7765
43	Компьютерная графика и мультимедиа в образовании	5	\N	7692
13	Разработка компьютерных игр	1	\N	\N
14	3D-визуализация	2	\N	\N
15	Компьютерные игры в образованиии	5	\N	\N
36	Компьютерные игры в образованиии КТвД 24	5	\N	\N
37	Искусственный интеллект в образовании КТвД 24	6	\N	\N
32	Разработка компьютерных игр КТвД 24	1	\N	\N
33	3D-визуализация КТвД 24	2	\N	\N
34	Дизайн графических интерфейсов КТвД 24	3	\N	\N
53	Разработка компьютерных игр	1	\N	7988
54	3D-визуализация	2	\N	7992
55	Дизайн Графических интерфейсов.	3	\N	7996
56	Разработка графических и веб-приложений	4	\N	7999
57	Компьютерная графика и мультимедиа в образовании	5	\N	8014
58	Разработка компьютерных игр	1	\N	8119
59	3D-визулизация	2	\N	8123
60	Дизайн графических интерфейсов	3	\N	8127
61	Разработка графических и веб-приложений	4	\N	8130
62	Компьютерная графика и мультимедиа в образовании	5	\N	8135
63	Разработка компьютерных игр	1	\N	8184
64	3D-визуализация	2	\N	8188
65	Дизайн Графических интерфейсов	3	\N	8192
66	Разработка графических и веб-приложений	4	\N	8195
67	Компьютерная графика и мультимедиа в образовании	5	\N	8210
68	Разработка компьютерных игр	1	\N	8258
69	3D-визуализация	2	\N	8262
70	Дизайн Графических интерфейсов	3	\N	8266
71	Разработка графических и веб-приложений	4	\N	8270
72	Компьютерные игры в образовании	5	\N	8283
73	Дизайн компьютерных игр	1	\N	8346
74	3D-визуализация	2	\N	8350
75	Дизайн графических интерфейсов	3	\N	8354
76	Разработка графических и веб-приложений	4	\N	8357
77	Анимация и развивающие приложения	5	\N	8362
78	Дизайн человеко-компьютерных систем	1	\N	8389
79	Технологии трёхмерного моделирования и расширенной реальности	2	\N	8392
46	3D-визуализация КТвД 24	2	\N	7841
47	Дизайн Графических интерфейсов КТвД 24	3	\N	7845
48	Разработка компьютерных игр КТвД 24	1	\N	7912
49	3D-визуализация КТвД 24	2	\N	7916
50	Дизайн Графических интерфейсов КТвД 24	3	\N	7920
52	Компьютерная графика и мультимедиа в образовании КТвД 24	5	\N	7937
51	Разработка графических и веб-приложений КТвД 24	4	\N	7924
35	Разработка графических и веб-приложений КТвД 24	4	\N	\N
80	Дизайн человеко-компьютерных систем	1	\N	8418
81	Технологии трёхмерного моделирования и расширенной реальности	2	\N	8421
82	Дизайн компьютерных игр	1	\N	8470
83	3D-визуализация	2	\N	8474
85	Разработка графических и веб-приложений	4	\N	8481
45	Разработка компьютерных игр КТвД 24	1	\N	7837
84	Дизайн графических интерфейсов	3	\N	8478
86	Анимация и развивающие приложения	5	\N	8486
87	Дизайн компьютерных игр	1	\N	8602
88	3D-визуализация	2	\N	8606
89	Дизайн графических интерфейсов	3	\N	8610
90	Разработка графических и веб-приложений	4	\N	8613
91	Анимация и развивающие приложения	5	\N	8618
92	Дизайн человеко-компьютерных систем	1	\N	8645
93	Технологии трёхмерного моделирования и расширенной реальности	2	\N	8648
\.
COPY s335141.workloads (id, hours, type, id_sem) FROM stdin;
5228	16	Пр	3382
6419	12	Лек	3988
6420	12	Пр	3988
6449	\N	УСРС	3998
6452	\N	УСРС	3999
6467	\N	УСРС	4005
7088	32	Лек	4067
7089	16	Лаб	4067
7090	\N	УСРС	4067
6547	\N	УСРС	4037
6550	\N	УСРС	4038
6517	36	Пр	4026
6662	113	УСРС	4088
6389	\N	УСРС	3514
6400	\N	УСРС	3532
6222	\N	УСРС	3507
7149	36	Лек	4283
6515	\N	УСРС	4025
7260	\N	УСРС	4325
7150	36	Пр	4283
7151	\N	УСРС	4283
6624	\N	УСРС	4073
7146	36	Лек	4282
7147	36	Пр	4282
7148	\N	УСРС	4282
7208	16	Лек	4307
5985	\N	УСРС	3915
5988	\N	УСРС	3916
6000	\N	УСРС	3920
6006	\N	УСРС	3921
4838	16	Лек	3406
4839	40	Пр	3406
4842	32	Лек	3408
4843	32	Лаб	3408
6108	32	Пр	3960
6110	32	Лек	3961
6111	32	Пр	3961
7209	48	Лаб	4307
7106	48	Лаб	4268
7107	\N	УСРС	4268
7108	48	Лаб	4269
7109	\N	УСРС	4269
6163	\N	УСРС	3965
7112	48	Лаб	4270
7113	\N	УСРС	4270
7114	16	Лек	4271
7115	32	Лаб	4271
7116	\N	УСРС	4271
6182	32	Лек	3969
6184	\N	УСРС	3969
6194	\N	УСРС	3971
6199	56	Лаб	3973
6200	16	Пр	3973
6205	32	Лек	3974
7210	\N	УСРС	4307
7211	16	Лек	4308
6206	16	Лаб	3974
6207	16	Пр	3974
7212	32	Лаб	4308
6209	32	Лек	3975
5233	24	Лек	3773
5234	24	Пр	3773
5235	68	К	3773
7117	48	Лаб	4272
7118	\N	УСРС	4272
6139	16	Лек	3962
5213	24	Лек	3368
6329	\N	УСРС	3368
6403	\N	УСРС	3535
6633	0	УСРС	4077
6405	16	Лек	3984
6413	16	Лек	3986
6414	16	Пр	3986
6416	12	Лек	3987
5231	16	Лек	3772
6417	12	Пр	3987
7213	\N	УСРС	4308
7181	\N	УСРС	4294
7187	16	Пр	4297
7188	\N	УСРС	4297
7189	32	Пр	4298
7190	\N	УСРС	4298
7191	16	Лек	4299
7192	16	Пр	4299
7193	\N	УСРС	4299
7194	16	Пр	4300
5232	16	Лаб	3772
7195	\N	УСРС	4300
7196	16	Пр	4301
7197	\N	УСРС	4301
7145	\N	УСРС	4281
7214	24	Лек	4309
7215	12	Пр	4309
7216	\N	УСРС	4309
7217	16	Лек	4310
7218	32	Лаб	4310
7219	\N	УСРС	4310
7220	16	Лек	4311
7221	32	Лаб	4311
6636	0	УСРС	4078
6639	0	УСРС	4079
7222	\N	УСРС	4311
7223	16	Лек	4312
7224	32	Лаб	4312
7225	\N	УСРС	4312
6464	16	Пр	4004
6445	32	Лаб	3997
7226	16	Лек	4313
7227	32	Лаб	4313
7228	32	Пр	4313
7229	\N	УСРС	4313
6494	\N	УСРС	4016
6504	\N	УСРС	4020
4908	48	Лаб	3450
6507	16	Лек	4022
6135	\N	УСРС	3451
6153	\N	УСРС	3461
7002	\N	УСРС	4229
6497	\N	УСРС	4017
6129	\N	УСРС	3444
7161	\N	УСРС	4286
7232	\N	УСРС	4314
5010	32	Лаб	3507
5227	16	Лек	3382
6526	32	Лаб	4030
6527	32	Пр	4030
5065	3	Лек	3554
4928	48	Пр	3463
7246	\N	УСРС	4319
6168	\N	УСРС	3966
7119	16	Лек	3454
7120	32	Лаб	3454
4926	48	Пр	3462
6511	\N	УСРС	4023
6512	32	Лаб	4024
6626	\N	УСРС	4074
6668	\N	УСРС	3540
6671	\N	УСРС	4090
6677	\N	УСРС	4092
7077	\N	УСРС	4254
6694	\N	УСРС	4098
4932	48	Пр	3465
4929	16	Лек	3464
4889	8	Лек	3440
4890	40	Лаб	3440
7066	\N	УСРС	4249
7069	\N	УСРС	4250
6171	\N	УСРС	3967
6195	64	Лаб	3972
6201	\N	УСРС	3973
4975	48	Лаб	3490
4976	48	Лаб	3491
6208	\N	УСРС	3974
4947	8	Лек	3475
4948	16	Лаб	3475
4981	16	Лек	3494
4982	32	Лаб	3494
6683	\N	УСРС	3542
5210	24	Лек	3367
5207	24	Лек	3366
5208	24	Пр	3366
5209	68	К	3366
5204	24	Лек	3365
5205	24	Пр	3365
5206	68	К	3365
5201	24	Лек	3364
5202	24	Пр	3364
5229	48	Лаб	3770
5230	48	Лаб	3771
6397	\N	УСРС	3526
4916	32	Лаб	3456
4959	20	Лек	3482
4960	32	Лаб	3482
6546	36	Пр	4037
6548	36	Лек	4038
6533	36	Пр	4032
6534	\N	УСРС	4032
4919	16	Лек	3459
7185	\N	УСРС	4296
7261	16	Лек	4326
7262	16	Пр	4326
7263	\N	УСРС	4326
6432	32	Лек	3993
6433	32	Пр	3993
6942	\N	УСРС	4210
6946	\N	УСРС	4212
6541	\N	УСРС	4035
4930	48	Пр	3464
4934	48	Пр	3466
4925	16	Лек	3462
4931	16	Лек	3465
4933	16	Лек	3466
4927	16	Лек	3463
5987	16	Пр	3916
5989	16	Лек	3917
6043	\N	УСРС	3938
6045	\N	УСРС	3939
5032	16	Лек	3522
6047	\N	УСРС	3940
6051	\N	УСРС	3942
5990	16	Пр	3917
6055	\N	УСРС	3944
5043	32	Лаб	3530
5038	16	Лек	3527
5039	32	Лаб	3527
6656	0	УСРС	4086
5040	64	Лаб	3528
5200	68	К	3363
5992	16	Лек	3918
6008	64	Пр	3922
6169	16	Лек	3967
6063	\N	УСРС	3948
5993	16	Пр	3918
6658	8	Лек	4087
6009	\N	УСРС	3922
5995	16	Лек	3919
6170	32	Пр	3967
6183	32	Пр	3969
6185	32	Лек	3970
6010	64	Пр	3923
5036	64	Лаб	3525
5037	48	Лаб	3526
5034	48	Лаб	3523
6012	64	Пр	3924
6013	\N	УСРС	3924
6075	\N	УСРС	3954
5996	16	Пр	3919
6014	64	Пр	3925
5999	36	Пр	3920
4812	16	Пр	3392
4809	16	Лек	3391
4810	16	Пр	3391
4804	32	Пр	3388
4803	32	Пр	3387
6450	36	Лек	3999
5019	16	Лек	3512
6631	16	Лек	4077
6016	64	Пр	3926
6451	36	Пр	3999
6017	\N	УСРС	3926
6632	16	Пр	4077
6466	48	Лаб	4005
6651	16	Лек	4085
5033	32	Лаб	3522
5041	64	Лаб	3529
5047	16	Лек	3533
6659	32	Лаб	4087
5054	16	Лек	3539
6018	64	Пр	3927
5049	8	Лек	3537
5050	16	Лаб	3537
5051	12	Пр	3537
6020	64	Пр	3928
5055	22	Пр	3539
4807	16	Лек	3390
4816	16	Пр	3394
4808	16	Пр	3390
4805	16	Лек	3389
4806	16	Пр	3389
4817	16	Лек	3395
5214	24	Пр	3368
6661	40	Лаб	4088
4818	32	Пр	3395
4820	22	Лек	3397
5998	\N	УСРС	3369
6022	64	Пр	3929
6023	\N	УСРС	3929
5060	32	Лаб	3542
5061	8	Пр	3542
6024	64	Пр	3930
6025	\N	УСРС	3930
5062	8	Лек	3543
5063	40	Лаб	3543
6634	16	Лек	4078
6635	32	Пр	4078
6028	64	Пр	3932
6637	16	Лек	4079
6638	32	Пр	4079
6030	64	Пр	3933
5222	12	Пр	3727
6652	16	Лаб	4085
7121	16	К	3420
6654	16	Лек	4086
6031	\N	УСРС	3933
4799	64	Пр	3384
5020	32	Лаб	3512
6036	\N	УСРС	3384
6037	\N	УСРС	3385
6071	\N	УСРС	3952
4819	32	Пр	3396
7122	48	Лаб	4273
7123	\N	УСРС	4273
5056	16	Лек	3540
6347	16	Лек	3982
6167	32	Лаб	3966
6623	12	Пр	4073
5057	16	Лаб	3540
5215	68	К	3368
5203	68	К	3364
6348	16	Пр	3982
6084	\N	УСРС	3396
5226	64	Пр	3383
6354	\N	УСРС	3389
5198	24	Лек	3363
6625	12	Пр	4074
5199	24	Пр	3363
7264	36	Пр	4327
4801	16	Лек	3386
5983	16	Лек	3915
5984	16	Пр	3915
5986	16	Лек	3916
7265	\N	УСРС	4327
6004	16	Лек	3921
6005	16	Пр	3921
7266	16	Лек	4328
4815	16	Лек	3394
7267	16	Пр	4328
5023	64	Лаб	3514
5026	64	Лаб	3517
5046	64	Лаб	3532
7268	\N	УСРС	4328
7269	8	К	4329
5024	64	Лаб	3515
5025	48	Лаб	3516
7270	\N	УСРС	4329
5027	16	Лек	3518
5028	32	Лаб	3518
5030	48	Лаб	3520
6655	16	Лаб	4086
5031	64	Лаб	3521
5042	16	Лек	3530
6041	\N	УСРС	3937
7271	32	Лек	4330
7272	32	Лаб	4330
7273	\N	УСРС	4330
6540	48	Лаб	4035
6516	36	Лек	4026
4846	32	Лек	3410
4847	16	Лаб	3410
6052	64	Пр	3943
6054	64	Пр	3944
6056	64	Пр	3945
6105	\N	УСРС	3410
4850	36	Лек	3412
4851	36	Пр	3412
4852	36	Лек	3413
4853	36	Пр	3413
6361	\N	УСРС	3413
6058	64	Пр	3946
4855	36	Лек	3414
4856	36	Пр	3414
4857	16	К	3414
4821	42	Пр	3397
5217	16	Лаб	3369
5048	32	Лаб	3533
6070	64	Пр	3952
6429	16	Лек	3992
6062	64	Пр	3948
6064	64	Пр	3949
6066	64	Пр	3950
6068	64	Пр	3951
6430	32	Лаб	3992
6107	32	Лек	3960
6074	64	Пр	3954
6076	64	Пр	3955
7124	64	Лаб	4274
6161	16	Лек	3965
6162	48	Пр	3965
6179	32	Лек	3968
6180	32	Пр	3968
7125	\N	УСРС	4274
6186	32	Пр	3970
6191	20	Лек	3971
6192	32	Лаб	3971
6193	12	Пр	3971
6486	16	Лек	4014
6487	32	Лаб	4014
6492	16	Лек	4016
6493	32	Лаб	4016
6508	32	Лаб	4022
4865	48	Лаб	3422
6113	\N	УСРС	3422
6510	32	Лаб	4023
4866	48	Лаб	3423
6115	\N	УСРС	3424
4868	48	Лаб	3425
6116	\N	УСРС	3425
4869	48	Лаб	3426
6117	\N	УСРС	3426
4870	32	Лаб	3427
4871	32	Пр	3427
4872	32	Лаб	3428
4873	32	Пр	3428
6514	32	Лаб	4025
6664	28	Лек	4089
4826	24	Лек	3400
4827	12	Пр	3400
6936	\N	УСРС	4208
6549	36	Пр	4038
4822	24	Лек	3398
4823	16	Пр	3398
4824	24	Лек	3399
4825	32	Лаб	3399
6090	\N	УСРС	3399
4844	16	Лек	3409
4845	32	Лаб	3409
4858	16	К	3415
6500	16	Лек	4019
6363	\N	УСРС	3415
4859	16	К	3416
4828	16	Лек	3401
4860	16	К	3417
4829	32	Лаб	3401
6095	\N	УСРС	3401
4830	16	Лек	3402
4831	48	Лаб	3402
6096	\N	УСРС	3402
4832	16	Лек	3403
4833	32	Лаб	3403
6097	\N	УСРС	3403
4834	32	Лек	3404
4862	16	К	3419
4864	16	К	3421
4835	32	Пр	3404
6098	\N	УСРС	3404
4836	32	Лек	3405
4837	32	Пр	3405
6099	\N	УСРС	3405
4840	16	Лек	3407
4841	16	Пр	3407
6101	\N	УСРС	3407
6078	16	Лек	3956
6079	16	Пр	3956
6080	\N	УСРС	3956
6081	16	Лек	3957
6082	16	Пр	3957
6087	32	Лек	3958
6088	32	Пр	3958
6505	48	Лаб	4021
6092	24	Лек	3959
6093	16	Пр	3959
5029	64	Лаб	3519
5045	32	Лаб	3531
6032	64	Пр	3934
6038	64	Пр	3936
6040	64	Пр	3937
6042	64	Пр	3938
6046	64	Пр	3940
6048	64	Пр	3941
6050	64	Пр	3942
4906	16	Лек	3449
4907	48	Лаб	3449
6227	16	Лек	3977
6536	16	Пр	4033
6240	\N	УСРС	3770
6680	0	УСРС	4093
6241	\N	УСРС	3771
6392	\N	УСРС	3530
6215	\N	УСРС	3494
5044	16	Лек	3531
6537	\N	УСРС	4033
6495	16	Лек	4017
6542	36	Лек	4036
6543	36	Пр	4036
5035	64	Лаб	3524
6544	\N	УСРС	4036
6406	16	Пр	3984
6551	16	Лек	4039
7141	64	Лаб	4280
6552	32	Лаб	4039
7142	\N	УСРС	4280
6967	\N	УСРС	4147
6234	64	Лаб	3978
6672	32	Лаб	4091
6235	\N	УСРС	3978
6554	16	Лек	4040
6140	32	Лаб	3962
6141	\N	УСРС	3962
6555	32	Лаб	4040
6566	16	Лек	4044
6678	8	Лек	4093
6679	40	Лаб	4093
6523	32	Лаб	4029
6529	16	Лаб	4031
6530	16	Пр	4031
6531	\N	УСРС	4031
6673	8	Пр	4091
6660	\N	УСРС	4087
6332	\N	УСРС	3365
6333	\N	УСРС	3364
6334	\N	УСРС	3363
6236	\N	УСРС	3529
6665	32	Пр	4089
6667	\N	УСРС	3539
6349	\N	УСРС	3982
6364	\N	УСРС	3416
6365	\N	УСРС	3417
4861	16	К	3418
6366	\N	УСРС	3419
6026	64	Пр	3931
4800	64	Пр	3385
6060	64	Пр	3947
6367	\N	УСРС	3420
6368	\N	УСРС	3421
6067	\N	УСРС	3950
6954	\N	УСРС	4215
6351	\N	УСРС	3392
6353	\N	УСРС	3390
4802	16	Пр	3386
6085	\N	УСРС	3395
4854	16	К	3413
6086	\N	УСРС	3397
6352	\N	УСРС	3391
6690	20	Лаб	4097
6356	\N	УСРС	3387
5216	16	Лек	3369
4792	12	Пр	3376
5194	12	Пр	3728
6463	32	Лек	4004
6483	\N	УСРС	4012
7130	48	Лаб	4276
4867	48	Лаб	3424
4874	64	Лаб	3429
4887	8	Лек	3439
7131	\N	УСРС	4276
6470	48	Лаб	4007
6476	\N	УСРС	4009
7126	8	Лек	4275
7127	32	Лаб	4275
6696	0	УСРС	4099
7128	32	Пр	4275
7129	\N	УСРС	4275
6695	64	Лаб	4099
6519	48	Лаб	4027
4888	40	Лаб	3439
7138	16	Лек	4279
7139	32	Лаб	4279
7140	\N	УСРС	4279
6124	\N	УСРС	3439
4893	16	Лек	3442
4894	48	Лаб	3442
7132	64	Лаб	4277
4904	16	Лек	3448
4905	48	Лаб	3448
6224	16	Лек	3976
6225	32	Лаб	3976
6535	48	Лаб	4033
6338	0	УСРС	3724
6339	0	УСРС	3725
7133	\N	УСРС	4277
6340	0	УСРС	3726
6498	48	Лаб	4018
5021	16	Лек	3513
7134	8	Лек	4278
7135	32	Лаб	4278
7136	\N	УСРС	4278
6770	32	Лек	4144
6768	16	Лек	4143
5022	32	Лаб	3513
6408	\N	УСРС	3984
6907	\N	УСРС	4198
6415	\N	УСРС	3986
6895	\N	УСРС	4194
4813	16	Лек	3393
6441	16	Лек	3996
6089	\N	УСРС	3958
6442	32	Лаб	3996
6785	\N	УСРС	4153
4814	16	Пр	3393
6418	\N	УСРС	3987
6502	\N	УСРС	4019
4811	16	Лек	3392
6421	\N	УСРС	3988
6933	\N	УСРС	4207
6524	16	Пр	4029
6525	\N	УСРС	4029
6950	\N	УСРС	4214
6939	\N	УСРС	4209
6948	\N	УСРС	4213
6424	36	Пр	3990
6425	\N	УСРС	3990
6426	32	Лек	3991
6427	32	Пр	3991
6443	\N	УСРС	3996
6428	\N	УСРС	3991
6485	\N	УСРС	4013
6482	48	Лаб	4012
6885	\N	УСРС	4189
6488	\N	УСРС	4014
7160	36	Пр	4286
6788	\N	УСРС	4154
6503	48	Лаб	4020
6468	48	Лаб	4006
6469	\N	УСРС	4006
6605	\N	УСРС	4060
6435	32	Лек	3994
6506	\N	УСРС	4021
7158	32	Пр	4226
6474	32	Лаб	4009
5211	24	Пр	3367
6587	48	Лаб	4053
6606	64	Лаб	4061
6002	\N	УСРС	3727
6873	\N	УСРС	4183
5212	68	К	3367
6607	\N	УСРС	4061
7155	36	Лек	4285
7156	36	Пр	4285
7157	\N	УСРС	4285
6475	32	Пр	4009
6330	\N	УСРС	3367
6589	16	Лек	4054
6521	48	Лаб	4028
6478	32	Лаб	4010
6477	32	Пр	4010
6226	\N	УСРС	3976
6479	\N	УСРС	4010
6239	\N	УСРС	3521
6407	26	К	3984
6879	\N	УСРС	4186
7159	36	Лек	4286
6073	\N	УСРС	3953
6590	32	Лаб	4054
6522	\N	УСРС	4028
6592	16	Лек	4055
6581	64	Лаб	4050
6593	32	Лаб	4055
4961	12	Пр	3482
6898	\N	УСРС	4195
6545	36	Лек	4037
6532	36	Лек	4032
6838	\N	УСРС	4168
6423	\N	УСРС	3989
6015	\N	УСРС	3925
6910	\N	УСРС	4199
6869	\N	УСРС	4181
6871	\N	УСРС	4182
6594	\N	УСРС	4055
7144	36	Пр	4281
6595	16	Лек	4056
6034	64	Пр	3935
6596	32	Лаб	4056
6598	64	Лаб	4057
6851	\N	УСРС	4172
6044	64	Пр	3939
6057	\N	УСРС	3945
6599	\N	УСРС	4057
6924	0	УСРС	4204
6927	0	УСРС	4205
6930	0	УСРС	4206
6059	\N	УСРС	3946
6559	\N	УСРС	4041
6061	\N	УСРС	3947
6434	\N	УСРС	3993
6916	\N	УСРС	4201
6609	\N	УСРС	4063
6698	\N	УСРС	4101
7152	36	Лек	4284
6562	\N	УСРС	4042
6600	64	Лаб	4058
6565	\N	УСРС	4043
6601	\N	УСРС	4058
6602	48	Лаб	4059
6444	16	Лек	3997
6608	\N	УСРС	4062
6919	\N	УСРС	4202
6921	\N	УСРС	4203
6913	\N	УСРС	4200
6422	32	Пр	3989
6501	32	Лаб	4019
6887	\N	УСРС	4190
6603	\N	УСРС	4059
7143	36	Лек	4281
6604	48	Лаб	4060
6944	\N	УСРС	4211
6881	\N	УСРС	4187
6480	64	Лаб	4011
6481	\N	УСРС	4011
6877	\N	УСРС	4185
6072	64	Пр	3953
6867	\N	УСРС	4180
6883	\N	УСРС	4188
6889	\N	УСРС	4191
6893	\N	УСРС	4193
6901	\N	УСРС	4196
6904	\N	УСРС	4197
6438	16	Лек	3995
6439	48	Лаб	3995
6440	\N	УСРС	3995
6472	48	Лаб	4008
6473	\N	УСРС	4008
6585	48	Лаб	4052
6484	48	Лаб	4013
6520	\N	УСРС	4027
6496	32	Лаб	4017
7153	36	Пр	4284
7154	\N	УСРС	4284
7162	36	Лек	4287
7163	36	Пр	4287
7164	\N	УСРС	4287
6458	16	К	4002
6387	36	УСРС	3512
6569	16	Лек	4045
6228	32	Лаб	3977
6880	64	Пр	4187
6394	\N	УСРС	3527
6395	\N	УСРС	3528
6398	\N	УСРС	3523
6409	16	Лек	3985
6410	16	Пр	3985
6874	64	Пр	4184
6411	26	К	3985
6447	36	Лек	3998
6448	36	Пр	3998
6453	36	Лек	4000
6454	36	Пр	4000
6807	16	Лек	4161
6876	64	Пр	4185
6850	64	Пр	4172
6471	\N	УСРС	4007
6852	64	Пр	4173
6808	16	Пр	4161
6083	\N	УСРС	3957
6100	\N	УСРС	3406
6103	\N	УСРС	3408
6820	16	Пр	4164
6783	32	Лек	4153
6809	26	К	4161
6854	64	Пр	4174
6784	32	Пр	4153
6786	32	Лек	4154
6787	32	Пр	4154
6125	\N	УСРС	3440
6187	\N	УСРС	3970
6995	0	УСРС	4227
6998	0	УСРС	4228
6210	16	Лаб	3975
6211	16	Пр	3975
6793	16	Лек	4155
6856	64	Пр	4175
6858	64	Пр	4176
6821	26	К	4164
6570	32	Лаб	4045
6572	16	Лек	4046
7021	0	УСРС	4233
6974	0	УСРС	4220
6573	32	Лаб	4046
7024	0	УСРС	4234
6794	16	Лаб	4155
6868	64	Пр	4181
6792	32	Пр	3459
6836	16	Пр	4168
7071	\N	УСРС	4251
6575	64	Лаб	4047
6588	\N	УСРС	4053
6823	16	Лек	4165
6557	16	Лек	4041
6630	\N	УСРС	4076
6558	32	Лаб	4041
6837	26	К	4168
6560	16	Лек	4042
6839	16	Лек	4169
6561	32	Лаб	4042
6563	16	Лек	4043
6564	32	Лаб	4043
6811	16	Лек	4162
6567	32	Лаб	4044
6223	\N	УСРС	3517
6812	16	Пр	4162
6840	16	Пр	4169
6841	26	К	4169
6843	16	Лек	4170
6870	64	Пр	4182
6872	64	Пр	4183
6882	32	Пр	4188
6884	32	Пр	4189
6886	32	Пр	4190
6888	32	Пр	4191
6890	32	Пр	4192
6489	16	Лек	4015
6460	32	Лек	4003
6956	\N	УСРС	4146
6963	\N	УСРС	4217
6965	\N	УСРС	4148
6509	\N	УСРС	4022
6982	\N	УСРС	4223
6992	\N	УСРС	4226
6989	\N	УСРС	4225
6674	\N	УСРС	4091
7026	\N	УСРС	4235
7028	\N	УСРС	4236
6528	\N	УСРС	4030
7030	\N	УСРС	4149
7036	\N	УСРС	4238
7033	\N	УСРС	4237
7039	\N	УСРС	4239
7047	\N	УСРС	4242
6847	16	Лек	4171
6848	16	Пр	4171
7009	\N	УСРС	4144
7011	\N	УСРС	4068
7053	\N	УСРС	4244
6461	16	Пр	4003
7050	\N	УСРС	4243
6579	64	Лаб	4049
6577	48	Лаб	4048
6813	26	К	4162
6666	\N	УСРС	4089
6682	\N	УСРС	4094
6689	\N	УСРС	4096
7015	\N	УСРС	4143
6456	16	К	4001
6824	16	Пр	4165
6799	16	Лек	4159
6800	16	Пр	4159
6801	26	К	4159
6803	16	Лек	4160
6815	16	Лек	4163
6816	16	Пр	4163
6804	16	Пр	4160
6628	\N	УСРС	4075
6805	26	К	4160
7018	\N	УСРС	4232
6959	\N	УСРС	4216
6817	26	К	4163
6825	26	К	4165
6827	16	Лек	4166
6828	16	Пр	4166
6829	26	К	4166
6831	16	Лек	4167
7045	\N	УСРС	4241
6832	16	Пр	4167
6819	16	Лек	4164
6844	16	Пр	4170
6845	26	К	4170
6860	64	Пр	4177
6862	64	Пр	4178
6864	64	Пр	4179
6878	64	Пр	4186
6833	26	К	4167
6835	16	Лек	4168
6866	64	Пр	4180
6957	16	Лек	4216
6958	32	Лаб	4216
6127	\N	УСРС	3442
7025	64	Лаб	4235
6132	\N	УСРС	3448
6922	36	Лек	4204
6923	36	Пр	4204
6925	36	Лек	4205
6926	36	Пр	4205
6928	36	Лек	4206
6929	36	Пр	4206
6961	16	Лаб	4217
6391	\N	УСРС	3516
6393	\N	УСРС	3531
6396	\N	УСРС	3525
6962	32	Пр	4217
7027	64	Лаб	4236
6964	48	Лаб	4148
6627	12	Пр	4075
6402	\N	УСРС	3534
6931	12	Лек	4207
6932	16	Лаб	4207
7059	8	К	4247
6691	25	УСРС	4097
6934	16	Лек	4208
6935	32	Лаб	4208
6993	36	Лек	4227
6994	36	Пр	4227
6937	16	Лек	4209
6996	36	Лек	4228
6997	36	Пр	4228
6518	\N	УСРС	4026
6938	32	Лаб	4209
6094	\N	УСРС	3959
6640	32	Пр	4080
7165	16	Пр	4288
6133	\N	УСРС	3449
7029	64	Лаб	4149
6202	\N	УСРС	3490
6203	\N	УСРС	3491
6039	\N	УСРС	3936
6049	\N	УСРС	3941
6065	\N	УСРС	3949
6903	16	Пр	4197
6401	\N	УСРС	3522
6069	\N	УСРС	3951
6905	16	Лек	4198
7019	36	Лек	4233
7020	36	Пр	4233
6906	16	Пр	4198
6972	36	Лек	4220
6973	36	Пр	4220
6908	16	Лек	4199
7022	36	Лек	4234
7023	36	Пр	4234
6246	\N	УСРС	3418
6909	16	Пр	4199
6914	16	Лек	4201
6915	16	Пр	4201
6213	\N	УСРС	3533
7034	16	Лек	4238
7035	32	Лаб	4238
6917	16	Лек	4202
7166	\N	УСРС	4288
6918	16	Пр	4202
6894	32	Пр	4194
6896	16	Лек	4195
7167	16	Пр	4289
7168	\N	УСРС	4289
6897	16	Пр	4195
6920	32	Пр	4203
6490	24	Лаб	4015
7169	28	Лек	4290
6491	\N	УСРС	4015
7170	8	Пр	4290
7031	16	Лек	4237
6981	48	Лаб	4223
6990	32	Лаб	4226
6643	8	К	4082
6987	32	Лаб	4225
6645	8	К	4083
6988	32	Пр	4225
7171	\N	УСРС	4290
6499	\N	УСРС	4018
6999	20	Лек	4229
6951	16	Лек	4215
7032	32	Лаб	4237
6911	16	Лек	4200
7040	16	Лек	4240
6912	16	Пр	4200
6952	32	Лаб	4215
6953	32	Пр	4215
7172	32	Лаб	4291
7041	32	Лаб	4240
6943	64	Лаб	4211
6941	64	Лаб	4210
6949	48	Лаб	4214
6947	48	Лаб	4213
7037	16	Лек	4239
6945	48	Лаб	4212
7038	32	Лаб	4239
7046	64	Лаб	4242
7000	32	Лаб	4229
7001	12	Пр	4229
7008	32	Лаб	4144
7010	64	Лаб	4068
7014	32	Лаб	4143
7173	8	Пр	4291
7174	\N	УСРС	4291
7016	16	Лек	4232
7043	16	Лек	4241
7044	32	Лаб	4241
7051	16	Лек	4244
7052	32	Лаб	4244
7048	16	Лек	4243
7049	32	Лаб	4243
6966	48	Лаб	4147
6699	\N	УСРС	4102
6513	\N	УСРС	4024
6700	\N	УСРС	4103
6875	\N	УСРС	4184
6629	36	Пр	4076
7054	16	Лек	4245
7055	16	Пр	4245
7057	32	Пр	4246
6955	48	Лаб	4146
7017	32	Лаб	4232
6701	\N	УСРС	4104
6702	\N	УСРС	4105
6960	6	Лек	4217
6892	32	Пр	4193
6899	16	Лек	4196
6900	16	Пр	4196
6902	16	Лек	4197
6404	\N	УСРС	3983
6109	\N	УСРС	3960
6112	\N	УСРС	3961
6157	\N	УСРС	3453
4935	48	Лаб	3467
6358	\N	УСРС	3394
6359	\N	УСРС	3398
6968	48	Лаб	4218
6360	\N	УСРС	3412
6114	\N	УСРС	3423
4940	32	Лаб	3471
4941	32	Пр	3471
4942	32	Лаб	3472
4943	32	Пр	3472
6969	\N	УСРС	4218
6976	48	Пр	4221
6164	\N	УСРС	3470
6644	0	УСРС	4082
6646	0	УСРС	4083
4911	48	Лаб	3453
6335	0	УСРС	3370
6148	48	Пр	3963
4923	16	Лек	3461
7012	32	Лаб	4142
6766	16	Лек	4142
6336	0	УСРС	3722
6337	0	УСРС	3723
6983	48	Лаб	4224
6143	\N	УСРС	3457
6233	\N	УСРС	3519
6985	64	Лаб	4145
4936	64	Лаб	3468
4954	32	Лаб	3479
6155	\N	УСРС	3468
6986	\N	УСРС	4145
4937	64	Лаб	3469
4944	64	Лаб	3473
7056	\N	УСРС	4245
6156	\N	УСРС	3469
6172	\N	УСРС	3473
7058	\N	УСРС	4246
7061	16	Лек	4248
7005	16	Лек	4231
6984	\N	УСРС	4224
7013	\N	УСРС	4142
7184	64	Пр	4296
7062	16	Лаб	4248
6647	8	Лек	4084
6053	\N	УСРС	3943
6648	12	Лаб	4084
6077	\N	УСРС	3955
6649	12	Пр	4084
5052	8	Лек	3538
6355	\N	УСРС	3388
7064	16	Лек	4249
7003	48	Лаб	4230
7065	16	Лаб	4249
7067	28	Лек	4250
7068	8	Пр	4250
5053	28	Лаб	3538
7004	\N	УСРС	4230
6377	\N	УСРС	3482
7070	40	Лаб	4251
7060	\N	УСРС	4247
6145	\N	УСРС	3459
5058	16	Лек	3541
6591	\N	УСРС	4054
6104	\N	УСРС	3409
7006	32	Лаб	4231
6641	\N	УСРС	4080
7175	16	Лек	4292
7176	16	Пр	4292
4910	48	Лаб	3452
5059	22	Лаб	3541
6669	32	Лаб	4090
6150	16	Лек	3964
6553	\N	УСРС	4039
7178	64	Пр	4293
7179	\N	УСРС	4293
7230	32	Лек	4314
6670	8	Пр	4090
7072	32	Лаб	4252
6675	4	Лек	4092
6676	28	Пр	4092
7074	32	Лаб	4253
7076	40	Лаб	4254
7042	\N	УСРС	4240
7198	16	Пр	4302
6181	\N	УСРС	3968
6642	\N	УСРС	4081
7177	\N	УСРС	4292
6331	\N	УСРС	3366
7199	\N	УСРС	4302
7200	16	Пр	4303
7201	\N	УСРС	4303
7202	16	Пр	4304
7078	32	Лаб	4255
7080	32	Лаб	4256
6681	24	Лаб	4094
6684	60	Лаб	4095
4938	16	Лек	3470
4939	16	Лаб	3470
6151	48	Пр	3964
7007	\N	УСРС	4231
4909	48	Лаб	3451
6685	4	Пр	4095
6687	48	Лаб	4096
6688	16	Пр	4096
6692	8	Лек	4098
6693	28	Лаб	4098
7203	\N	УСРС	4304
7204	16	Пр	4305
7205	\N	УСРС	4305
7206	16	Пр	4306
7207	\N	УСРС	4306
4924	48	Пр	3461
4949	64	Лаб	3476
4917	48	Лаб	3457
6853	\N	УСРС	4173
7182	64	Пр	4295
7183	\N	УСРС	4295
6977	\N	УСРС	4221
7186	16	Лек	4297
6147	16	Лек	3963
6975	16	Лек	4221
7180	64	Пр	4294
4987	36	Лек	3497
7231	16	Лаб	4314
6120	\N	УСРС	3429
4988	36	Пр	3497
4989	36	Лек	3498
6196	\N	УСРС	3972
4848	32	Лек	3411
6165	\N	УСРС	3471
6166	\N	УСРС	3472
4973	16	Лек	3489
6978	8	Лек	4222
4974	32	Лаб	3489
6375	\N	УСРС	3479
6979	16	Лаб	4222
6582	\N	УСРС	4050
6388	8	УСРС	3513
7102	32	Пр	4266
6007	\N	УСРС	3383
7103	\N	УСРС	4266
6865	\N	УСРС	4179
6175	\N	УСРС	3477
4898	48	Пр	3445
6130	\N	УСРС	3445
4977	16	Лек	3492
4849	16	Лаб	3411
4965	20	Лек	3485
4963	16	Лек	3484
6390	\N	УСРС	3515
6383	\N	УСРС	3499
6431	\N	УСРС	3992
6574	\N	УСРС	4046
6861	\N	УСРС	4177
6232	\N	УСРС	3518
4896	8	Лек	3444
4921	16	Лек	3460
6842	\N	УСРС	4169
6371	0	УСРС	3464
4962	64	Лаб	3483
6369	0	УСРС	3466
4958	16	Пр	3481
4983	32	Лек	3495
4970	16	Лаб	3487
6190	\N	УСРС	3487
6174	\N	УСРС	3476
6154	\N	УСРС	3467
4897	32	Лаб	3444
4980	16	Лаб	3493
6001	\N	УСРС	3376
6849	\N	УСРС	4171
7097	32	Лек	4265
6021	\N	УСРС	3928
6029	\N	УСРС	3932
6033	\N	УСРС	3934
4957	64	Лаб	3481
6980	\N	УСРС	4222
6370	0	УСРС	3465
6446	\N	УСРС	3997
6372	0	УСРС	3463
6373	0	УСРС	3462
6857	\N	УСРС	4175
6568	\N	УСРС	4044
4966	28	Лаб	3485
6859	\N	УСРС	4176
4985	36	Лек	3496
7073	\N	УСРС	4252
7075	\N	УСРС	4253
6134	\N	УСРС	3450
6091	\N	УСРС	3400
7079	\N	УСРС	4255
6863	\N	УСРС	4178
4971	16	Лек	3488
7081	\N	УСРС	4256
4972	32	Лаб	3488
6891	\N	УСРС	4192
6378	\N	УСРС	3483
6197	\N	УСРС	3488
4978	32	Лаб	3492
6204	\N	УСРС	3492
4967	56	Лаб	3486
4979	32	Лек	3493
4990	36	Пр	3498
6382	\N	УСРС	3498
4945	36	Лек	3474
4946	36	Пр	3474
6855	\N	УСРС	4174
6374	\N	УСРС	3474
6188	\N	УСРС	3485
6142	\N	УСРС	3456
4964	32	Лаб	3484
6686	\N	УСРС	4095
6379	\N	УСРС	3484
6697	\N	УСРС	4100
4968	16	Пр	3486
6189	\N	УСРС	3486
6173	\N	УСРС	3475
6653	169	УСРС	4085
6657	\N	УСРС	3538
4986	36	Пр	3496
6149	\N	УСРС	3963
6106	\N	УСРС	3411
6003	\N	УСРС	3728
7233	64	Лаб	4315
6357	\N	УСРС	3386
6663	\N	УСРС	3541
6457	\N	УСРС	4001
4922	32	Лаб	3460
4914	8	Лек	3455
4915	32	Лаб	3455
6138	\N	УСРС	3455
6380	\N	УСРС	3496
6118	\N	УСРС	3427
6119	\N	УСРС	3428
5991	\N	УСРС	3917
5994	\N	УСРС	3918
5997	\N	УСРС	3919
6152	\N	УСРС	3964
6214	\N	УСРС	3493
7063	\N	УСРС	4248
6650	\N	УСРС	4084
7100	20	Лек	4266
7101	12	Лаб	4266
6846	\N	УСРС	4170
6136	\N	УСРС	3452
6146	\N	УСРС	3460
4984	16	Лаб	3495
4969	32	Лек	3487
7098	32	Лаб	4265
7099	\N	УСРС	4265
6538	48	Лаб	4034
6539	\N	УСРС	4034
4991	32	Лек	3499
4992	16	Лаб	3499
4993	16	Пр	3499
6198	\N	УСРС	3489
6571	\N	УСРС	4045
6216	\N	УСРС	3495
4950	16	Лек	3477
4951	16	Пр	3477
4952	16	Лек	3478
4953	16	Пр	3478
6176	\N	УСРС	3478
6399	\N	УСРС	3524
6376	\N	УСРС	3481
6465	\N	УСРС	4004
7259	\N	УСРС	4324
6580	\N	УСРС	4049
7237	56	Лаб	4317
5004	16	Лаб	3504
7242	\N	УСРС	4318
6229	\N	УСРС	3977
4999	16	Лек	3502
5000	16	Лаб	3502
6217	\N	УСРС	3502
6586	\N	УСРС	4052
6385	\N	УСРС	3501
7104	48	Лаб	4267
4955	32	Лаб	3480
7105	\N	УСРС	4267
5005	16	Лек	3505
6462	\N	УСРС	4003
7238	16	Пр	4317
5006	32	Лаб	3505
6238	\N	УСРС	3520
4918	32	Пр	3458
6220	\N	УСРС	3505
5007	16	Лек	3506
5008	32	Лаб	3506
6144	\N	УСРС	3458
5015	16	Лек	3510
5016	32	Лаб	3510
6597	\N	УСРС	4056
6237	\N	УСРС	3510
4877	32	Лек	3431
4878	16	Пр	3431
6122	\N	УСРС	3431
4879	32	Лек	3432
6212	\N	УСРС	3975
4880	16	Пр	3432
6221	\N	УСРС	3506
5011	16	Лек	3508
5012	32	Лаб	3508
6230	\N	УСРС	3508
6381	\N	УСРС	3497
6123	\N	УСРС	3432
6583	48	Лаб	4051
4875	32	Лек	3430
6584	\N	УСРС	4051
5009	16	Лек	3507
4876	16	Лаб	3430
6137	\N	УСРС	3454
4895	48	Пр	3443
6128	\N	УСРС	3443
6814	\N	УСРС	4162
6818	\N	УСРС	4163
6822	\N	УСРС	4164
6556	\N	УСРС	4040
5013	16	Лек	3509
7239	\N	УСРС	4317
4901	6	Лек	3447
4994	16	Лек	3500
6412	\N	УСРС	3985
4902	32	Лаб	3447
4891	8	Лек	3441
5014	32	Лаб	3509
6231	\N	УСРС	3509
4903	16	Пр	3447
4881	16	К	3433
6011	\N	УСРС	3923
6019	\N	УСРС	3927
6027	\N	УСРС	3931
6035	\N	УСРС	3935
6131	\N	УСРС	3447
6121	\N	УСРС	3430
6247	\N	УСРС	3433
4882	16	К	3434
6248	\N	УСРС	3434
4892	40	Лаб	3441
7247	32	Лек	4320
4956	16	Пр	3480
7252	\N	УСРС	4321
6436	32	Пр	3994
6350	\N	УСРС	3393
4883	16	К	3435
6249	\N	УСРС	3435
6455	\N	УСРС	4000
4884	16	К	3436
6250	\N	УСРС	3436
4885	16	К	3437
4995	16	Лаб	3500
4996	16	Пр	3500
7248	16	Лаб	4320
7249	16	Пр	4320
6970	32	Лаб	4219
6126	\N	УСРС	3441
6251	\N	УСРС	3437
4886	16	К	3438
6796	\N	УСРС	4156
6797	\N	УСРС	4157
6798	\N	УСРС	4158
6252	\N	УСРС	3438
6384	\N	УСРС	3500
6437	\N	УСРС	3994
6795	\N	УСРС	4155
5002	32	Лаб	3503
7253	48	Лаб	4322
7254	\N	УСРС	4322
7255	16	Лек	4323
7256	32	Лаб	4323
6459	\N	УСРС	4002
7257	\N	УСРС	4323
7258	64	Лаб	4324
6578	\N	УСРС	4048
4899	24	Лек	3446
6362	\N	УСРС	3414
6102	\N	УСРС	3446
7240	36	Лек	4318
7241	36	Пр	4318
6576	\N	УСРС	4047
7235	64	Лаб	4316
6826	\N	УСРС	4165
7243	16	Лек	4319
5017	16	Лек	3511
5018	32	Лаб	3511
6386	\N	УСРС	3511
6830	\N	УСРС	4166
6834	\N	УСРС	4167
7236	\N	УСРС	4316
7244	16	Лаб	4319
7245	16	Пр	4319
7250	\N	УСРС	4320
6971	\N	УСРС	4219
4997	16	Лек	3501
4998	32	Пр	3501
5001	16	Лек	3503
7234	\N	УСРС	4315
6177	\N	УСРС	3480
6218	\N	УСРС	3503
5003	16	Лек	3504
6802	\N	УСРС	4159
6806	\N	УСРС	4160
6810	\N	УСРС	4161
6219	\N	УСРС	3504
7251	48	Лаб	4321
4900	24	Пр	3446
\.
-- Name: assessments_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.assessments_id_seq', 4113, true);


--
-- Name: changes_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.changes_id_seq', 1328, true);


--
-- Name: disciplines_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.disciplines_id_seq', 6415, true);


--
-- Name: disciplines_in_modules_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.disciplines_in_modules_id_seq', 22998, true);


--
-- Name: discp_starts_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.discp_starts_id_seq', 20681, true);


--
-- Name: memorandums_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.memorandums_id_seq', 132, true);


--
-- Name: sections_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.sections_id_seq', 8654, true);


--
-- Name: semester_rpd_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.semester_rpd_id_seq', 4330, true);


--
-- Name: tracks_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.tracks_id_seq', 93, true);


--
-- Name: workloads_id_seq; Type: SEQUENCE SET; Schema: s335141; Owner: s335141
--

SELECT pg_catalog.setval('s335141.workloads_id_seq', 7273, true);


--
-- Name: assessments assessments_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.assessments
    ADD CONSTRAINT assessments_pkey PRIMARY KEY (id);


--
-- Name: change_discp_module change_discp_module_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_discp_module
    ADD CONSTRAINT change_discp_module_pkey PRIMARY KEY (id_change);


--
-- Name: change_discp_starts change_discp_starts_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_discp_starts
    ADD CONSTRAINT change_discp_starts_pkey PRIMARY KEY (id_change);


--
-- Name: change_rpd change_rpd_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_rpd
    ADD CONSTRAINT change_rpd_pkey PRIMARY KEY (id_change);


--
-- Name: changes changes_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.changes
    ADD CONSTRAINT changes_pkey PRIMARY KEY (id);


--
-- Name: curricula curricula_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.curricula
    ADD CONSTRAINT curricula_pkey PRIMARY KEY (id_isu);


--
-- Name: disciplines_in_modules disciplines_in_modules_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.disciplines_in_modules
    ADD CONSTRAINT disciplines_in_modules_pkey PRIMARY KEY (id);


--
-- Name: disciplines disciplines_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.disciplines
    ADD CONSTRAINT disciplines_pkey PRIMARY KEY (id);


--
-- Name: discp_starts discp_starts_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.discp_starts
    ADD CONSTRAINT discp_starts_pkey PRIMARY KEY (id);


--
-- Name: disciplines fk_change_discip; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.disciplines
    ADD CONSTRAINT fk_change_discip UNIQUE (name);


--
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);


--
-- Name: memorandums memorandums_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.memorandums
    ADD CONSTRAINT memorandums_pkey PRIMARY KEY (id);


--
-- Name: modules modules_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.modules
    ADD CONSTRAINT modules_pkey PRIMARY KEY (id_isu);


--
-- Name: track_specialty pk_track_specialty; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.track_specialty
    ADD CONSTRAINT pk_track_specialty PRIMARY KEY (id_track, code);


--
-- Name: rpd rpd_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.rpd
    ADD CONSTRAINT rpd_pkey PRIMARY KEY (id_isu);


--
-- Name: sections sections_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.sections
    ADD CONSTRAINT sections_pkey PRIMARY KEY (id);


--
-- Name: semester_rpd semester_rpd_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.semester_rpd
    ADD CONSTRAINT semester_rpd_pkey PRIMARY KEY (id);


--
-- Name: specialties specialties_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.specialties
    ADD CONSTRAINT specialties_pkey PRIMARY KEY (code);


--
-- Name: students students_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (id);


--
-- Name: tracks tracks_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.tracks
    ADD CONSTRAINT tracks_pkey PRIMARY KEY (id);


--
-- Name: curricula uk_curricula_name_year; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.curricula
    ADD CONSTRAINT uk_curricula_name_year UNIQUE (name, year);


--
-- Name: discp_starts uk_discp_start; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.discp_starts
    ADD CONSTRAINT uk_discp_start UNIQUE (id_discp_module, sem);


--
-- Name: disciplines_in_modules uk_position_module; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.disciplines_in_modules
    ADD CONSTRAINT uk_position_module UNIQUE ("position", id_module);


--
-- Name: disciplines_in_modules uk_rpd_module; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.disciplines_in_modules
    ADD CONSTRAINT uk_rpd_module UNIQUE (id_rpd, id_module);


--
-- Name: sections uk_sections_position_curricula_section; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.sections
    ADD CONSTRAINT uk_sections_position_curricula_section UNIQUE ("position", id_parent_section);


--
-- Name: sections uk_sections_section_curricula_module; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.sections
    ADD CONSTRAINT uk_sections_section_curricula_module UNIQUE (id_parent_section, id_module);


--
-- Name: semester_rpd uk_semester_rpd; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.semester_rpd
    ADD CONSTRAINT uk_semester_rpd UNIQUE (number_from_start, id_rpd);


--
-- Name: tracks uk_tracks_section; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.tracks
    ADD CONSTRAINT uk_tracks_section UNIQUE (id_section);


--
-- Name: workloads uk_workload_unique; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.workloads
    ADD CONSTRAINT uk_workload_unique UNIQUE (type, id_sem);


--
-- Name: workloads workloads_pkey; Type: CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.workloads
    ADD CONSTRAINT workloads_pkey PRIMARY KEY (id);


--
-- Name: assessments fk_assessment_semester; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.assessments
    ADD CONSTRAINT fk_assessment_semester FOREIGN KEY (id_sem) REFERENCES s335141.semester_rpd(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: change_discp_module fk_change_discp_module_changes; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_discp_module
    ADD CONSTRAINT fk_change_discp_module_changes FOREIGN KEY (id_change) REFERENCES s335141.changes(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: change_discp_module fk_change_discp_module_discp; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_discp_module
    ADD CONSTRAINT fk_change_discp_module_discp FOREIGN KEY (id_discp_module) REFERENCES s335141.disciplines_in_modules(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: change_discp_starts fk_change_discp_starts_changes; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_discp_starts
    ADD CONSTRAINT fk_change_discp_starts_changes FOREIGN KEY (id_change) REFERENCES s335141.changes(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: change_discp_starts fk_change_discp_starts_start; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_discp_starts
    ADD CONSTRAINT fk_change_discp_starts_start FOREIGN KEY (id_discp_start) REFERENCES s335141.discp_starts(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: change_rpd fk_change_rpd_changes; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_rpd
    ADD CONSTRAINT fk_change_rpd_changes FOREIGN KEY (id_change) REFERENCES s335141.changes(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: change_rpd fk_change_rpd_rpd; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_rpd
    ADD CONSTRAINT fk_change_rpd_rpd FOREIGN KEY (id_rpd) REFERENCES s335141.rpd(id_isu) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: change_section fk_change_section_changes; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_section
    ADD CONSTRAINT fk_change_section_changes FOREIGN KEY (id_change) REFERENCES s335141.changes(id);


--
-- Name: change_section fk_change_section_section; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.change_section
    ADD CONSTRAINT fk_change_section_section FOREIGN KEY (id_section) REFERENCES s335141.sections(id);


--
-- Name: changes fk_changes_memorandum; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.changes
    ADD CONSTRAINT fk_changes_memorandum FOREIGN KEY (id_memorandum) REFERENCES s335141.memorandums(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: disciplines_in_modules fk_dim_module; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.disciplines_in_modules
    ADD CONSTRAINT fk_dim_module FOREIGN KEY (id_module) REFERENCES s335141.modules(id_isu) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: disciplines_in_modules fk_dim_rpd; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.disciplines_in_modules
    ADD CONSTRAINT fk_dim_rpd FOREIGN KEY (id_rpd) REFERENCES s335141.rpd(id_isu) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: discp_starts fk_discp_starts_module; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.discp_starts
    ADD CONSTRAINT fk_discp_starts_module FOREIGN KEY (id_discp_module) REFERENCES s335141.disciplines_in_modules(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: rpd fk_rpd_discipline; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.rpd
    ADD CONSTRAINT fk_rpd_discipline FOREIGN KEY (id_discipline) REFERENCES s335141.disciplines(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sections fk_sections_curricula; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.sections
    ADD CONSTRAINT fk_sections_curricula FOREIGN KEY (id_curricula) REFERENCES s335141.curricula(id_isu) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sections fk_sections_modules; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.sections
    ADD CONSTRAINT fk_sections_modules FOREIGN KEY (id_module) REFERENCES s335141.modules(id_isu) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sections fk_sections_parent; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.sections
    ADD CONSTRAINT fk_sections_parent FOREIGN KEY (id_parent_section) REFERENCES s335141.sections(id) ON DELETE RESTRICT;


--
-- Name: semester_rpd fk_semester_rpd; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.semester_rpd
    ADD CONSTRAINT fk_semester_rpd FOREIGN KEY (id_rpd) REFERENCES s335141.rpd(id_isu) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: track_specialty fk_track_specialty_code; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.track_specialty
    ADD CONSTRAINT fk_track_specialty_code FOREIGN KEY (code) REFERENCES s335141.specialties(code) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: track_specialty fk_track_specialty_track; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.track_specialty
    ADD CONSTRAINT fk_track_specialty_track FOREIGN KEY (id_track) REFERENCES s335141.tracks(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tracks fk_tracks_section; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.tracks
    ADD CONSTRAINT fk_tracks_section FOREIGN KEY (id_section) REFERENCES s335141.sections(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: workloads fk_workload_semester; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.workloads
    ADD CONSTRAINT fk_workload_semester FOREIGN KEY (id_sem) REFERENCES s335141.semester_rpd(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: students students_group_id_fkey; Type: FK CONSTRAINT; Schema: s335141; Owner: s335141
--

ALTER TABLE ONLY s335141.students
    ADD CONSTRAINT students_group_id_fkey FOREIGN KEY (group_id) REFERENCES s335141.groups(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- ADDED FOR PORTAL INTEGRATION
--

CREATE TABLE s335141.discipline_prerequisites (
    discipline_id integer NOT NULL,
    prerequisite_id integer NOT NULL,
    CONSTRAINT discipline_prerequisites_pkey PRIMARY KEY (discipline_id, prerequisite_id),
    CONSTRAINT fk_dp_discipline FOREIGN KEY (discipline_id) REFERENCES s335141.disciplines(id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_dp_prerequisite FOREIGN KEY (prerequisite_id) REFERENCES s335141.disciplines(id) ON UPDATE CASCADE ON DELETE CASCADE
);
ALTER TABLE s335141.discipline_prerequisites OWNER TO s335141;

ALTER TABLE s335141.appuser ADD COLUMN student_id integer;
ALTER TABLE s335141.appuser ADD CONSTRAINT fk_appuser_student FOREIGN KEY (student_id) REFERENCES s335141.students(id) ON UPDATE CASCADE ON DELETE SET NULL;

INSERT INTO s335141.appuser (id, login, password, role, student_id) VALUES (1, 'admin', 'admin', 'ADMIN', NULL);
INSERT INTO s335141.appuser (id, login, password, role, student_id) VALUES (2, 'student', 'student', 'STUDENT', 1);
