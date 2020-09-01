WITH constants AS (
    SELECT current_setting('block_size')::numeric AS bs, 23 AS hdr, 8 AS ma
),
no_stats AS (
    SELECT table_schema, table_name, 
        n_live_tup::numeric as est_rows,
        pg_table_size(relid)::numeric as table_size        
        , pg_indexes_size(c.oid)                AS index_bytes
        , pg_total_relation_size(c.reltoastrelid) AS toast_bytes
    FROM information_schema.columns
        JOIN pg_stat_user_tables as psut
           ON table_schema = psut.schemaname
           AND table_name = psut.relname
        join pg_class c on c.oid = relid
        LEFT OUTER JOIN pg_stats
        ON table_schema = pg_stats.schemaname
            AND table_name = pg_stats.tablename
            AND column_name = attname 
    WHERE attname IS NULL
        AND table_schema NOT IN ('pg_catalog', 'information_schema')
    GROUP BY table_schema, table_name, relid, n_live_tup, c.oid, c.reltoastrelid
),
null_headers AS (
    SELECT
        hdr+1+(sum(case when null_frac <> 0 THEN 1 else 0 END)/8) as nullhdr,
        SUM((1-null_frac)*avg_width) as datawidth,
        MAX(null_frac) as maxfracsum,
        schemaname,
        tablename,
        hdr, ma, bs
    FROM pg_stats CROSS JOIN constants
        LEFT OUTER JOIN no_stats
            ON schemaname = no_stats.table_schema
            AND tablename = no_stats.table_name
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        AND no_stats.table_name IS NULL
        AND EXISTS ( SELECT 1
            FROM information_schema.columns
                WHERE schemaname = columns.table_schema
                    AND tablename = columns.table_name )
    GROUP BY schemaname, tablename, hdr, ma, bs
),
data_headers AS (
    SELECT
        ma, bs, hdr, schemaname, tablename,
        (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
        (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM null_headers
),
table_estimates AS (
    SELECT 
	  schemaname
	, tablename
	, bs
	, reltuples::numeric as est_rows
        , relpages * bs as table_bytes,
    CEIL((reltuples*
            (datahdr + nullhdr2 + 4 + ma -
                (CASE WHEN datahdr%ma=0
                    THEN ma ELSE datahdr%ma END)
                )/(bs-20))) * bs AS expected_bytes,
        reltoastrelid,
        pg_class.oid
        
    FROM data_headers
        JOIN pg_class ON tablename = relname
        JOIN pg_namespace ON relnamespace = pg_namespace.oid
            AND schemaname = nspname
    WHERE pg_class.relkind = 'r'
),
estimates_with_toast AS (
    SELECT schemaname, tablename, 
        TRUE as can_estimate,
        est_rows,
        table_bytes + ( coalesce(toast.relpages, 0) * bs ) as table_bytes,
        expected_bytes + ( ceil( coalesce(toast.reltuples, 0) / 4 ) * bs ) as expected_bytes

        
        , pg_indexes_size(oid)                AS index_bytes
        , pg_total_relation_size(table_estimates.reltoastrelid) AS toast_bytes

                                  
    FROM table_estimates LEFT OUTER JOIN pg_class as toast
        ON table_estimates.reltoastrelid = toast.oid
            AND toast.relkind = 't'
),
table_estimates_plus AS (
    SELECT current_database() as databasename,
            schemaname, tablename, can_estimate, 
            est_rows,
            CASE WHEN table_bytes > 0
                THEN table_bytes::NUMERIC
                ELSE NULL::NUMERIC END
                AS table_bytes,
            CASE WHEN expected_bytes > 0 
                THEN expected_bytes::NUMERIC
                ELSE NULL::NUMERIC END
                    AS expected_bytes,
            CASE WHEN expected_bytes > 0 AND table_bytes > 0
                AND expected_bytes <= table_bytes
                THEN (table_bytes - expected_bytes)::NUMERIC
                ELSE 0::NUMERIC END AS bloat_bytes
               , index_bytes
               , toast_bytes 
                
    FROM estimates_with_toast
    UNION ALL
    SELECT current_database() as databasename, 
        table_schema, table_name, FALSE, 
        est_rows, table_size,
        NULL::NUMERIC, NULL::NUMERIC
        , index_bytes
        , toast_bytes 
    FROM no_stats
),
bloat_data AS (
    select current_database() as databasename,
        schemaname, tablename, can_estimate, 
        table_bytes, round(table_bytes/(1024^2)::NUMERIC,3) as table_mb,
        round(toast_bytes/(1024^2)::NUMERIC,3) as toast_mb,
        round(index_bytes/(1024^2)::NUMERIC,3) as index_mb,
        expected_bytes, round(expected_bytes/(1024^2)::NUMERIC,3) as expected_mb,
        round(bloat_bytes*100/table_bytes) as pct_bloat,
        round(bloat_bytes/(1024::NUMERIC^2),2) as mb_bloat,
        
        table_bytes, expected_bytes, est_rows
    FROM table_estimates_plus
)
SELECT 
    clock_timestamp()::date as "Timestamp",
    schemaname, 
    tablename,
    can_estimate,
    est_rows,
    pct_bloat, 
    mb_bloat,
    table_mb,
    toast_mb,
    index_mb
FROM bloat_data
where 
	table_mb > 50
order by pct_bloat desc nulls last
