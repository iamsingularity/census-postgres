﻿/*
TABLES AND VIEWS ALTERED FROM STANDARD STORAGE SCHEMA AS chariter FIELD
IS REQUIRED TO GUARANTEE UNIQUENESS.
*/
SET search_path = acs2010_spt;

--CREATE DDL FOR STORAGE BY SEQUENCE
DROP FUNCTION IF EXISTS sql_store_by_tables(boolean);
CREATE FUNCTION sql_store_by_tables(exec boolean = FALSE) RETURNS text AS $function$
DECLARE 
	sql TEXT := '';
	sql_estimate text;
	sql_moe text;
BEGIN	
	SELECT array_to_string(array_agg(sql1), E'\n'), array_to_string(array_agg(sql2), E'\n') 
	INTO sql_estimate, sql_moe
	FROM (
		SELECT 
			seq,
			CASE WHEN seq_position = 1 THEN 'CREATE TABLE ' || seq_id || E' (\n'
				|| E'\tfileid varchar(6),\n\tfiletype varchar(6), \n\tstusab varchar(2), \n'
				|| E'\tchariter varchar(3), \n\tseq varchar(4), \n\tlogrecno int,\n' 
				ELSE ''
			END || 
			E'\t' || cell_id || ' double precision,' ||
			CASE WHEN seq_position = max(seq_position) OVER (PARTITION BY seq)
				THEN E'\n\tPRIMARY KEY (stusab, logrecno, chariter)\n)\nWITH (autovacuum_enabled = FALSE, toast.autovacuum_enabled = FALSE);\n'
				ELSE ''
			END AS sql1,
			CASE WHEN seq_position = 1 THEN 'CREATE TABLE ' || seq_id || E'_moe (\n'
				|| E'\tfileid varchar(6),\n\tfiletype varchar(6), \n\tstusab varchar(2), \n'
				|| E'\tchariter varchar(3), \n\tseq varchar(4), \n\tlogrecno int,\n' 
				ELSE ''
			END || 
			E'\t' || cell_id || '_moe double precision,' ||
			CASE WHEN seq_position = max(seq_position) OVER (PARTITION BY seq)
				THEN E'\n\tPRIMARY KEY (stusab, logrecno, chariter)\n)\nWITH (autovacuum_enabled = FALSE, toast.autovacuum_enabled = FALSE);\n'
				ELSE ''
			END AS sql2
		FROM vw_cell
		ORDER BY seq, seq_position
		) s
	;

	sql := sql_estimate || E'\n\n' || sql_moe;
	IF exec THEN EXECUTE sql; END IF;
	RETURN sql;
END;
$function$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS sql_view_estimate_stored_by_tables(boolean);
CREATE FUNCTION sql_view_estimate_stored_by_tables(exec boolean = FALSE) RETURNS text AS $function$
DECLARE 
	sql TEXT := '';
BEGIN	
	SELECT array_to_string(array_agg(sql_statement), E'\n') INTO sql 
	FROM (
		SELECT 
			seq,
			CASE WHEN table_position = 1 THEN 'CREATE VIEW ' || table_id || E' AS SELECT \n'
				|| E'\tstusab, logrecno, chariter,\n' 
				ELSE ''
			END || 
			E'\t' || cell_id || 
			CASE WHEN table_position = max(table_position) OVER (PARTITION BY table_id)
				THEN E'\nFROM ' || join_clause || E';\n'
				ELSE ','
			END AS sql_statement
		FROM vw_cell JOIN (SELECT seq, coverage FROM vw_sequence) s USING (seq)
			JOIN (
				SELECT table_id, join_sequences(array_agg(seq_id)) AS join_clause
				FROM vw_subject_table JOIN (SELECT seq, coverage FROM vw_sequence) s USING (seq)
				WHERE COALESCE(coverage, 'all') != 'pr'
				GROUP BY table_id
				) j USING (table_id)
		WHERE COALESCE(coverage, 'all') != 'pr'
		ORDER BY seq, seq_position
		) s
	;

	IF exec THEN EXECUTE sql; END IF;
	RETURN sql;
END;
$function$ LANGUAGE plpgsql;

/*Margin of error will rarely be used without estimate, so even though
they are stored in independent sequences, subject table views return estimates
as well as margins of error
*/
DROP FUNCTION IF EXISTS sql_view_moe_stored_by_tables(boolean);
CREATE FUNCTION sql_view_moe_stored_by_tables(exec boolean = FALSE) RETURNS text AS $function$
DECLARE 
	sql TEXT := '';
BEGIN	
	SELECT array_to_string(array_agg(sql_statement), E'\n') INTO sql 
	FROM (
		SELECT 
			seq,
			CASE WHEN table_position = 1 THEN 'CREATE VIEW ' || table_id || E'_moe AS SELECT \n'
				|| E'\tstusab, logrecno, chariter,\n' 
				ELSE ''
			END || 
			E'\t' || cell_id || ', ' || cell_id || '_moe' ||
			CASE WHEN table_position = max(table_position) OVER (PARTITION BY table_id)
				THEN E'\nFROM ' || join_clause || E';\n'
				ELSE ','
			END AS sql_statement
		FROM vw_cell JOIN (SELECT seq, coverage FROM vw_sequence) s USING (seq)
			JOIN (
				SELECT table_id, join_sequences(array_cat(array_agg(seq_id), array_agg(seq_id || '_moe'))) AS join_clause
				FROM vw_subject_table JOIN (SELECT seq, coverage FROM vw_sequence) s USING (seq)
				WHERE COALESCE(coverage, 'all') != 'pr'
				GROUP BY table_id
				) j USING (table_id)
		WHERE COALESCE(coverage, 'all') != 'pr'
		ORDER BY seq, seq_position
		) s
	;

	IF exec THEN EXECUTE sql; END IF;
	RETURN sql;
END;
$function$ LANGUAGE plpgsql;
