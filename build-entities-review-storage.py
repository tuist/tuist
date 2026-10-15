import json, os, pathlib, re, socket, subprocess, tempfile, time, urllib.parse, urllib.request

PORT = 18337
HOST = '127.0.0.1'
with socket.socket() as probe:
    probe.bind((HOST, PORT))
root = pathlib.Path(tempfile.mkdtemp(prefix='tuist-build-entities-review-storage-'))
config = root / 'config.xml'
config.write_text(f'''<clickhouse>
<logger><level>warning</level><log>{root}/server.log</log><errorlog>{root}/error.log</errorlog></logger>
<path>{root}/data/</path><tmp_path>{root}/tmp/</tmp_path><listen_host>{HOST}</listen_host>
<http_port>{PORT}</http_port><tcp_port>0</tcp_port><interserver_http_port>0</interserver_http_port>
<max_server_memory_usage>2147483648</max_server_memory_usage>
<profiles><default><max_threads>2</max_threads></default></profiles>
<users><default><password></password><networks><ip>{HOST}</ip></networks><profile>default</profile><quota>default</quota></default></users>
<quotas><default></default></quotas></clickhouse>''')
binary = subprocess.check_output(['mise', 'which', 'clickhouse'], cwd='server', text=True).strip()
log = open(root / 'startup.log', 'w')
process = subprocess.Popen([binary, 'server', f'--config-file={config}'], stdout=log, stderr=log,
                           env={**os.environ, 'CLICKHOUSE_WATCHDOG_ENABLE': '0'})
def query(sql, database='default'):
    assert database == 'default' or database.startswith('build_entities_bench_review_storage_')
    url = f'http://{HOST}:{PORT}/?' + urllib.parse.urlencode({'database': database})
    request = urllib.request.Request(url, data=sql.encode(), method='POST')
    try:
        return urllib.request.urlopen(request, timeout=30).read().decode()
    except urllib.error.HTTPError as error:
        raise RuntimeError(error.read().decode()) from error

try:
    for _ in range(100):
        try:
            query('SELECT 1')
            break
        except Exception:
            if process.poll() is not None:
                raise RuntimeError(f'Private ClickHouse exited: {root}')
            time.sleep(.1)
    else:
        raise RuntimeError('Private ClickHouse did not become ready')
    source = pathlib.Path('server/priv/ingest_repo/migrations/20261009130000_create_build_entity_tables.exs').read_text()
    ddl = re.findall(r'IngestRepo.query!\("""(.*?)"""\)', source, re.S)[:3]
    assert len(ddl) == 3
    ddl = [re.sub(r'#\{Migration.engine\("([^"]+)"\)\}', r'\1', sql) for sql in ddl]
    kinds = [
        ('gradle', 'task', "concat(':app:compile', toString(number % 1000))", "map('root_project_name', 'Shop', 'build_path', ':', 'task_path', concat(':app:compile', toString(number % 1000)), 'task_type', 'org.gradle.api.tasks.compile.JavaCompile')"),
        ('xcode', 'module', "concat('Module', toString(number % 1000))", "map('project', 'ShopProject', 'target', concat('Module', toString(number % 1000)))"),
        ('once', 'action', "concat('Compile ', toString(number % 1000))", "map('target_id', concat('//app:module_', toString(number % 1000)), 'capability', 'build', 'action_index', '0')"),
        ('mix', 'file', "concat('lib/domain_', toString(number % 1000), '.ex')", "map('path', concat('lib/domain_', toString(number % 1000), '.ex'))"),
        ('mix', 'module', "concat('Shop.Domain', toString(number % 1000))", "map('module', concat('Shop.Domain', toString(number % 1000)))"),
    ]
    result = {'scope': 'Synthetic local storage only; no production writes or load. No shared process/cache reset.',
              'port': PORT, 'private_config': str(config), 'rows_per_kind': 10000, 'identities_per_kind': 1000,
              'limitations': 'Stopped merges quantify initial parts, not steady-state compaction. Synthetic paths/branches and high within-batch identity reuse compress differently from customer data. These byte rates are not production capacity sign-off.',
              'scenarios': []}
    for batch_size in [1000, 10000]:
        database = f'build_entities_bench_review_storage_{batch_size}'
        query(f'CREATE DATABASE {database}')
        for sql in ddl:
            query(sql, database)
        for table in ['build_entity_observations', 'build_entities']:
            query(f'SYSTEM STOP MERGES {database}.{table}')
        for system, kind, name, identity in kinds:
            for start in range(0, 10000, batch_size):
                query(f'''INSERT INTO build_entity_observations SELECT
                1, '{system}', '{kind}', reinterpretAsUUID(MD5(concat('{system}/{kind}/', toString(number % 1000)))),
                now64(6) - toIntervalSecond(10000 - number),
                reinterpretAsUUID(MD5(concat('{system}/{kind}/event/', toString(number)))),
                {name}, toJSONString({identity}),
                toString(reinterpretAsUUID(MD5(toString(intDiv(number, 1000))))),
                toString(reinterpretAsUUID(MD5(concat('native/', toString(number))))),
                if('{system}' = 'xcode', 'unknown', 'success'),
                if(number % 3 = 0, 'hit_remote', 'none'),
                if('{system}' = 'xcode', NULL, number % 5000),
                if(number % 4 = 0, 'feature/synthetic-storage-check', 'main'),
                hex(MD5(toString(intDiv(number, 1000)))), number % 2 = 0, now64(6)
                FROM numbers({start}, {batch_size}) SETTINGS async_insert=0''', database)
        stats = json.loads(query(f'''SELECT table, sum(rows) AS physical_rows,
            sum(data_compressed_bytes) AS compressed_column_bytes,
            sum(data_uncompressed_bytes) AS uncompressed_column_bytes,
            sum(bytes_on_disk) AS bytes_on_disk
            FROM system.parts WHERE active AND database = '{database}'
            GROUP BY table ORDER BY table FORMAT JSON'''))['data']
        stats = [{key: (int(value) if key != 'table' else value) for key, value in row.items()} for row in stats]
        by_table = {row['table']: row for row in stats}
        assert by_table['build_entity_observations']['physical_rows'] == 50000
        assert by_table['build_entities']['physical_rows'] == 50000 * 1000 // batch_size
        per_kind = []
        for table in ['build_entity_observations', 'build_entities']:
            rows = json.loads(query(f'''SELECT '{table}' AS table, samples.system AS system,
                samples.kind AS kind, sum(parts.rows) AS physical_rows,
                sum(parts.bytes_on_disk) AS bytes_on_disk
                FROM (SELECT _part, any(source.system) AS system, any(source.kind) AS kind
                    FROM {table} AS source GROUP BY _part
                    HAVING uniqExact(tuple(source.system, source.kind)) = 1) AS samples
                INNER JOIN system.parts AS parts ON parts.name = samples._part
                WHERE parts.active AND parts.database = '{database}' AND parts.table = '{table}'
                GROUP BY samples.system, samples.kind ORDER BY samples.system, samples.kind FORMAT JSON''', database))['data']
            per_kind.extend([{key: (int(value) if key in ['physical_rows', 'bytes_on_disk'] else value)
                             for key, value in row.items()} for row in rows])
        assert sum(row['bytes_on_disk'] for row in per_kind) == sum(row['bytes_on_disk'] for row in stats)
        result['scenarios'].append({'batch_size': batch_size, 'tables': stats, 'per_kind': per_kind})
    pathlib.Path('/tmp/build-entities-review-storage.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
finally:
    if process.poll() is None:
        command = subprocess.check_output(['ps', '-p', str(process.pid), '-o', 'command='], text=True)
        assert f'--config-file={config}' in command
        process.terminate()
        process.wait(timeout=30)
    log.close()
    print(f'Owned process stopped; data retained at {root}')
