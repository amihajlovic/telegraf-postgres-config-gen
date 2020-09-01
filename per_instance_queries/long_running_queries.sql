select 
                pid
                , pg_blocking_pids(sa.pid) blocking_pids
                , sa.state
                , sa.wait_event
                , sa.wait_event_Type
                , now() - sa.xact_start duration
                , sa.query
                , l.locks
                , sa.datname 
                , sa.usename
                , sa.application_name
                , sa.client_addr
                , sa.client_hostname
                , sa.backend_start
                , sa.xact_start
                , sa.query_start
                , sa.state_change 
            from 
                pg_stat_activity sa
                left join lateral (
                    select array_agg(distinct ROW(datname, relname, mode)) locks
                    from pg_locks l
                        join pg_class c
                            on l.relation = c.oid
                        join pg_database d 
                            on l.database = d.oid
                    where l.pid = sa.pid
                
                )l on true
            where 
                sa.state <> 'idle'   and sa.pid <> pg_backend_pid() 
                AND now() - sa.xact_start > '1 second'::interval