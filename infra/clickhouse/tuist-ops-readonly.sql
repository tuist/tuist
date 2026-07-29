CREATE ROLE IF NOT EXISTS tuist_ops_readonly;

ALTER ROLE tuist_ops_readonly SETTINGS
    readonly = 1,
    max_execution_time = 10,
    max_memory_usage = 1073741824,
    max_rows_to_read = 100000000,
    max_bytes_to_read = 5000000000,
    max_result_bytes = 5242880,
    max_threads = 2;

GRANT SELECT ON {database:Identifier}.* TO tuist_ops_readonly;
GRANT SELECT ON system.tables TO tuist_ops_readonly;
GRANT SELECT ON system.columns TO tuist_ops_readonly;

CREATE USER IF NOT EXISTS {username:Identifier}
IDENTIFIED WITH sha256_password BY {password:String};

GRANT tuist_ops_readonly TO {username:Identifier};
ALTER USER {username:Identifier} DEFAULT ROLE tuist_ops_readonly;
