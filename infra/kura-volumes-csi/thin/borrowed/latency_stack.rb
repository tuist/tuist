#!/usr/bin/env ruby
# Mechanism isolation only: never run on a hosted node or accept a block device.
require 'json'
require 'open3'
require 'tmpdir'
require 'securerandom'
require 'fileutils'
require 'net/http'
require 'openssl'
require 'base64'
abort 'requires root in a disposable Linux VM' unless RUBY_PLATFORM.include?('linux') && Process.uid.zero? && ENV['KURA_THIN_DISPOSABLE_VM'] == '1'

class LatencyProbe
  IMAGE = 'ghcr.io/tuist/kura@sha256:2c7e3ddc67bd196452663078c9f95bf8dd17a654d8bb0d9c0c388bc8c072ab43'
  # Each edge isolates one factor. legacy reproduces the shipped thick settings.
  CASES = {
    'plain_matched' => [false, false, false, true, true],
    'thick_legacy' => [false, true, false, false, false],
    'thick_matched' => [false, true, false, true, true],
    'thick_quota' => [false, true, true, true, true],
    'thin_noquota' => [true, true, false, true, true],
    'thin_quota' => [true, true, true, true, true],
    'thin_legacy_crypto' => [true, true, true, false, true],
    'thin_legacy_format' => [true, true, true, true, false],
    'thin_log4k' => [true, true, true, true, true],
    'thin_flat_geometry' => [true, true, true, true, true]
  }.freeze

  def initialize
    @dir = Dir.mktmpdir('kura-latency-')
    @vg = "kura_latency_#{SecureRandom.hex(4)}"
    @mount = File.join(@dir, 'mount')
    @bench = ENV.fetch('KURA_LATENCY_BENCH')
    @report_path = ENV.fetch('KURA_LATENCY_REPORT', '/tmp/kura-latency-results.json')
    @report = {environment: {image: IMAGE, kernel: run('uname', '-r').strip,
      cpu: run('lscpu'), backing: 'private loop file on disposable VM; not hosted NVMe',
      runtime_cpu: 1, runtime_memory_bytes: 768 << 20, virtual_bytes: 13 << 30,
      thin_chunk_bytes: 512 << 10, small_count: 4000, warmup_count: 400, concurrency: 8}, samples: []}
    @key = SecureRandom.random_bytes(32)
    secret = SecureRandom.hex(32)
    b64 = ->(v) { Base64.urlsafe_encode64(JSON.generate(v), padding: false) }
    payload = [b64.call(alg: 'HS256', typ: 'JWT'), b64.call(sub: 'latency-fixture', type: 'user', scopes: ['project_cache_write'], cache_grants: {project: {read: ['default/shared'], write: ['default/shared']}}, exp: Time.now.to_i + 7200)].join('.')
    token = payload + '.' + Base64.urlsafe_encode64(OpenSSL::HMAC.digest('sha256', secret, payload), padding: false)
    @token = File.join(@dir, 'token'); File.write(@token, token, perm: 0600)
    @env = File.join(@dir, 'env')
    vars = {KURA_PORT: 4000, KURA_INTERNAL_PORT: 7443, KURA_NODE_URL: 'http://127.0.0.1:7443', KURA_PEERS: 'http://127.0.0.1:7443', KURA_TENANT_ID: 'default', KURA_REGION: 'qualification', KURA_DATA_DIR: '/fixture/base', KURA_TMP_DIR: '/fixture/base/tmp', KURA_TMP_DIR_MAX_BYTES: 2 << 30, KURA_CAS_CAPACITY_BYTES: 4 << 30, KURA_AUTH_JWT_SECRET: secret, RUST_LOG: 'warn', KURA_OTEL_SERVICE_NAME: 'latency-fixture', KURA_OTEL_DEPLOYMENT_ENVIRONMENT: 'qualification'}
    File.write(@env, vars.map { |k,v| "#{k}=#{v}" }.join("\n") + "\n", perm: 0600)
  end

  def run(*args, input: '')
    out, err, status = Open3.capture3(*args, stdin_data: input)
    raise "#{args.first} failed: #{err}" unless status.success?
    out
  end

  def save
    File.write(@report_path, JSON.pretty_generate(@report))
  end

  def setup
    file = File.join(@dir, 'pv.img')
    File.open(file, 'wb', 0600) { |f| f.truncate(36 << 30) }
    @loop = run('losetup', '--direct-io=on', '--find', '--show', file).strip
    raise 'foreign loop' unless run('losetup', '-n', '-O', 'BACK-FILE', @loop).strip == file
    run('pvcreate', '-y', @loop)
    run('vgcreate', @vg, @loop); @vg_created = true
    run('lvcreate', '-y', '--type', 'thin-pool', '-L', '16G', '--poolmetadatasize', '256M', '--chunksize', '512K', '--zero', 'y', '--discards', 'passdown', '-n', 'pool', @vg)
    run('lvchange', '--errorwhenfull', 'y', "#{@vg}/pool")
    # Keep pool counters available while the sample is a thick/plain LV.
    run('lvcreate', '-y', '-V', '64M', '--thinpool', "#{@vg}/pool", '-n', 'sentinel')
    FileUtils.mkdir_p(@mount)
    save
  end

  def prepare(config, name:)
    thin, encrypted, quota, submit, format = config
    @lv = "#{@vg}/sample"
    if thin
      run('lvcreate', '-y', '-V', '13G', '--thinpool', "#{@vg}/pool", '-n', 'sample')
    else
      run('lvcreate', '-y', '-L', '13G', '-n', 'sample', @vg)
    end
    device = "/dev/#{@lv}"
    if encrypted
      run('cryptsetup', 'luksFormat', '--type', 'luks2', '--cipher', 'aes-xts-plain64', '--key-size', '512', '--pbkdf', 'pbkdf2', '--pbkdf-force-iterations', '1000', '--batch-mode', '--key-file=-', device, input: @key)
      @mapper = "#{@vg}_crypt"
      # Discards are enabled uniformly; no discard runs during measured phases.
      run('cryptsetup', 'open', '--allow-discards', *(submit ? ['--perf-submit_from_crypt_cpus'] : []), '--key-file=-', device, @mapper, input: @key)
      device = "/dev/mapper/#{@mapper}"
    end
    # Matching command arguments does not match effective geometry: mkfs also
    # reads the block device's alignment hints. Keep that as an explicit factor.
    format_args = format ? ['-m', 'reflink=0', '-l', name == 'thin_log4k' ? 'size=64m,su=4k' : 'size=64m'] : []
    format_args += ['-d', 'noalign,agcount=4'] if name == 'thin_flat_geometry'
    run('mkfs.xfs', '-q', '-K', '-f', *format_args, device)
    run('mount', '-t', 'xfs', '-o', "nodev,nosuid,noatime#{quota ? ',prjquota' : ''}", device, @mount); @mounted = true
    if quota
      run('xfs_quota', '-x', '-c', "project -s -p #{@mount} 1", @mount)
      run('xfs_quota', '-x', '-c', 'limit -p bsoft=10g bhard=10g 1', @mount)
    end
    FileUtils.mkdir_p(File.join(@mount, 'base', 'tmp'))
    FileUtils.chown_R(1000, 1000, File.join(@mount, 'base'))
  end

  def counters
    {runtime: run('docker', 'exec', @container, 'sh', '-c', 'cat /sys/fs/cgroup/cpu.stat /sys/fs/cgroup/memory.events /sys/fs/cgroup/io.stat'), pool: run('dmsetup', 'status', "#{@vg}-pool-tpool"), host_cpu: File.readlines('/proc/stat').first}
  end

  def start
    @container = "#{@vg}-runtime"
    run('docker', 'run', '-d', '--name', @container, '--user', '1000:1000', '--cpus', '1', '--memory', '768m', '--memory-swap', '768m', '--env-file', @env, '-v', "#{@mount}:/fixture", '-p', '127.0.0.1::4000', IMAGE)
    @endpoint = 'http://' + run('docker', 'port', @container, '4000/tcp').strip
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
    loop do
      begin
        break if Net::HTTP.get_response(URI(@endpoint + '/ready')).code == '200'
      rescue SystemCallError, EOFError
      end
      raise 'runtime not ready' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.2
    end
  end

  def http(warmup:, count:)
    file = File.join(@dir, 'http.json')
    run(@bench, '-base', @endpoint, '-token-file', @token, '-account', 'default', '-small-only', '-small-count', count.to_s, '-warmup', warmup.to_s, '-out', file)
    phases = JSON.parse(File.read(file))
    raise 'HTTP failure' unless phases.all? { |p| p.fetch('failures').zero? }
    phases
  end

  def stop
    return unless @container
    run('docker', 'stop', '-t', '30', @container)
    run('docker', 'rm', @container)
    @container = nil
  end

  def fio(reuse:, sync:)
    file = File.join(@mount, 'sync-probe')
    File.unlink(file) if File.exist?(file) && !reuse
    args = ['fio', '--name=sync-probe', "--filename=#{file}", '--ioengine=psync', '--rw=write', '--bs=16k', '--size=16m', '--direct=0', '--fallocate=none', '--end_fsync=1', '--output-format=json', '--lat_percentiles=1', '--percentile_list=50:95:99']
    args << '--fdatasync=1' if sync
    report = JSON.parse(run(*args))
    raise 'fio failure' unless report.fetch('jobs').all? { |j| j.fetch('error').zero? }
    report
  end

  def release
    stop
    if @mounted
      run('umount', @mount); @mounted = false
    end
    if @mapper
      run('cryptsetup', 'close', @mapper); @mapper = nil
    end
    if @lv
      run('lvremove', '-y', @lv); @lv = nil
    end
  end

  def execute
    setup
    (CASES.keys + CASES.keys.reverse).each_with_index do |name, index|
      warn "LATENCY #{index + 1}/#{CASES.size * 2} #{name}"
      prepare(CASES.fetch(name), name: name); start
      entry = {name: name, round: index, factors: CASES.fetch(name), xfs: run('xfs_info', @mount), before: counters}
      # Reproduce the original short cold phase, then extend on the same runtime.
      entry[:cold] = http(warmup: 0, count: 400)
      entry[:after_cold] = counters
      entry[:warm] = http(warmup: 400, count: 4000)
      entry[:after_warm] = counters
      stop
      entry[:fresh_sync] = fio(reuse: false, sync: true)
      entry[:overwrite_sync] = fio(reuse: true, sync: true)
      entry[:fresh_buffered] = fio(reuse: false, sync: false)
      @report[:samples] << entry; save
      release
    end
  ensure
    begin
      release
      run('vgremove', '-y', @vg) if @vg_created
      if @loop
        run('pvremove', '-y', @loop)
        run('losetup', '-d', @loop)
      end
      FileUtils.remove_entry_secure(@dir)
      @report[:cleanup_verified] = true
    rescue => error
      @report[:cleanup_error] = error.message
      warn "Retained uncertain backing: #{error.message}"
      raise
    ensure
      save
    end
  end
end
LatencyProbe.new.execute
