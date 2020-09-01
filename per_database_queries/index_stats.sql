SELECT
    clock_timestamp()::date as "Timestamp"
    , table_schema
    , table_name
    , index_name
    , real_size_mb
    , extra_mb
    , extra_ratio
    , fillfactor
    , bloat_mb
    , bloat_ratio
    , idx_blks_read
    , idx_blks_hit
    , idx_scan
    , idx_tup_read
    , idx_tup_fetch
FROM
    (
        SELECT
            nspname                                             AS table_schema
            , tblname                                           AS table_name
            , idxname                                           AS index_name
            , ROUND((bs *(relpages) / (1024 * 1024)), 2)::float AS real_size_mb
            , CASE
                WHEN relpages-est_pages < 0 THEN 0
                    ELSE ROUND((bs *(relpages-est_pages) / (1024 * 1024))::numeric, 2)
            END::float AS extra_mb
            , CASE
                WHEN relpages-est_pages < 0 THEN 0
                    ELSE ROUND((100 * (relpages-est_pages) / relpages )::numeric, 2)
            END::float AS extra_ratio
            , fillfactor
            , CASE
                WHEN relpages-est_pages_ff < 0 THEN 0
                    ELSE ROUND((bs *(relpages-est_pages_ff) / (1024 * 1024))::numeric ,2)
            END::float AS bloat_mb
            , CASE
                WHEN relpages-est_pages_ff < 0 THEN 0
                    ELSE ROUND((100 * (relpages-est_pages_ff) / relpages)::numeric,2)
            END::float AS bloat_ratio
            , indexrelid
        
        FROM
            (
                SELECT
                    COALESCE(1   + ceil(reltuples/floor((bs-pageopqdata-pagehdr)/(4+nulldatahdrwidth)::float)), 0 )                  AS est_pages
                    , COALESCE(1 + ceil(reltuples/floor((bs-pageopqdata-pagehdr)*fillfactor/(100*(4+nulldatahdrwidth)::float))), 0 ) AS est_pages_ff
                    , bs
                    , nspname
                    , table_oid
                    , tblname
                    , idxname
                    , relpages
                    , fillfactor
                    , is_na
                    , indexrelid
                FROM
                    (
                        SELECT
                            maxalign
                            , bs
                            , nspname
                            , tblname
                            , idxname
                            , reltuples
                            , relpages
                            , relam
                            , table_oid
                            , fillfactor
                            , ( index_tuple_hdr_bm + maxalign -
                            CASE
                                WHEN index_tuple_hdr_bm%maxalign = 0 THEN maxalign
                                    ELSE index_tuple_hdr_bm%maxalign
                            END + nulldatawidth + maxalign -
                            CASE
                                WHEN nulldatawidth                   = 0 THEN 0
                                WHEN nulldatawidth::integer%maxalign = 0 THEN maxalign
                                    ELSE nulldatawidth::integer%maxalign
                            END )::numeric AS nulldatahdrwidth
                            , pagehdr
                            , pageopqdata
                            , is_na
                            , indexrelid
                        
                        FROM
                            (
                                SELECT
                                    i.indexrelid
                                    , i.nspname
                                    , i.tblname
                                    , i.idxname
                                    , i.reltuples
                                    , i.relpages
                                    , i.relam
                                    , a.attrelid                             AS table_oid
                                    , current_setting('block_size')::numeric AS bs
                                    , fillfactor
                                    , CASE
                                        WHEN version() ~ 'mingw32'
                                            OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64' THEN 8
                                            ELSE 4
                                    END  AS maxalign
                                    , 24 AS pagehdr
                                    , 16 AS pageopqdata
                                    , CASE
                                        WHEN MAX(COALESCE(s.null_frac,0)) = 0 THEN 2
                                            ELSE 2 + (( 32 + 8 - 1 ) / 8)
                                    END                                                                AS index_tuple_hdr_bm
                                    , SUM( (1-COALESCE(s.null_frac, 0)) * COALESCE(s.avg_width, 1024)) AS nulldatawidth
                                    , MAX(
                                        CASE
                                            WHEN a.atttypid = 'pg_catalog.name'::regtype THEN 1
                                                ELSE 0
                                        END
                                    ) > 0 AS is_na
                                FROM
                                    pg_attribute AS a
                                    JOIN
                                        (
                                            SELECT
                                                nspname
                                                , tbl.relname AS tblname
                                                , idx.relname AS idxname
                                                , idx.reltuples
                                                , idx.relpages
                                                , idx.relam
                                                , indrelid
                                                , indexrelid
                                                , indkey::smallint[]                                                                                  AS attnum
                                                , COALESCE(substring( array_to_string(idx.reloptions, ' ') FROM 'fillfactor=([0-9]+)')::smallint, 90) AS fillfactor
                                            FROM
                                                pg_index
                                                JOIN pg_class idx
                                                    ON  idx.oid=pg_index.indexrelid
                                                JOIN pg_class tbl
                                                    ON  tbl.oid=pg_index.indrelid
                                                JOIN pg_namespace
                                                    ON  pg_namespace.oid = idx.relnamespace
                                            WHERE
                                                pg_index.indisvalid
                                                AND tbl.relkind  = 'r'
                                                AND idx.relpages > 0
                                        )
                                        AS i
                                        ON  a.attrelid = i.indexrelid
                                    LEFT JOIN pg_stats AS s
                                        ON  s.schemaname = i.nspname
                                            AND
                                            (
                                                (
                                                    s.tablename   = i.tblname
                                                    AND s.attname = pg_catalog.pg_get_indexdef(a.attrelid, a.attnum, TRUE)
                                                )
                                                OR
                                                (
                                                    s.tablename   = i.idxname
                                                    AND s.attname = a.attname
                                                )
                                            )
                                    JOIN pg_type AS t
                                        ON  a.atttypid = t.oid
                                WHERE
                                    a.attnum > 0
                                GROUP BY
                                    1
                                    , 2
                                    , 3
                                    , 4
                                    , 5
                                    , 6
                                    , 7
                                    , 8
                                    , 9
                                    , 10
                            )
                            AS s1
                    )
                               AS s2
                    JOIN pg_am    am
                        ON  s2.relam = am.oid
                WHERE
                    am.amname = 'btree'
            )
            AS sub
    )
                               s
    JOIN pg_statio_all_indexes sai
        ON  s.indexrelid = sai.indexrelid
    JOIN pg_stat_all_indexes sai1
        ON  s.indexrelid = sai1.indexrelid

WHERE
    table_schema NOT IN ('pg_catalog', 'information_schema')
