#!/usr/bin/env ruby
# Run ONLY inside a disposable Linux VM. All block devices descend from our file.
require 'json'
require 'open3'
require 'tmpdir'
require 'securerandom'
require 'fileutils'

abort 'requires root inside a disposable Linux VM and KURA_THIN_DISPOSABLE_VM=1' unless
  RUBY_PLATFORM.include?('linux') && Process.uid.zero? && ENV['KURA_THIN_DISPOSABLE_VM'] == '1'

class Fixture
  MIB = 1 << 20
  attr_reader :results

  def initialize
    @dir = Dir.mktmpdir('kura-thin-')
    @vg = "kura_probe_#{SecureRandom.hex(4)}"
    @mappers = []
    @mounts = []
    @key = SecureRandom.random_bytes(32)
    @results = {schema: 1, environment: {}, assertions: [], observations: {}, benchmarks: []}
  end

  def command(*args, input: nil, allow_failure: false)
    out, err, status = Open3.capture3(*args, stdin_data: input || '')
    raise "#{args.first} failed (#{status.exitstatus}): #{err}" unless status.success? || allow_failure
    [out, status.success?]
  end

  def run(*args, **opts)
    command(*args, **opts).first
  end

  def assert(name, condition, details = {})
    @results[:assertions] << {name: name, passed: !!condition, **details}
    raise "assertion failed: #{name}: #{details}" unless condition
    warn "PASS #{name}"
  end

  def setup
    @results[:environment] = {
      kernel: run('uname', '-r').strip,
      lvm: run('lvm', 'version').lines.first.strip,
      cryptsetup: run('cryptsetup', '--version').strip,
      xfs: run('mkfs.xfs', '-V').strip,
      backing: '24 GiB sparse file on disposable VM disk; 64 KiB thin chunks; no snapshots'
    }
    file = File.join(@dir, 'pv.img')
    File.open(file, 'wb', 0600) { |f| f.truncate(24 << 30) }
    @loop = run('losetup', '--direct-io=on', '--find', '--show', file).strip
    assert('own loop device backed by private file', run('losetup', '-n', '-O', 'BACK-FILE', @loop).strip == file)
    run('pvcreate', '-y', @loop)
    run('vgcreate', @vg, @loop)
    run('lvcreate', '-y', '--type', 'thin-pool', '-L', '8G', '--poolmetadatasize', '128M',
        '--chunksize', '64K', '--discards', 'nopassdown', '-n', 'pool', @vg)
    run('lvchange', '--errorwhenfull', 'y', "#{@vg}/pool")
    %w[a b churn].each { |name| create(name, thin: true) }
    create('thick', thin: false)
  end

  def create(name, thin:)
    if thin
      run('lvcreate', '-y', '-V', '6G', '--thinpool', "#{@vg}/pool", '-n', name)
    else
      run('lvcreate', '-y', '-L', '6G', '-n', name, @vg)
    end
    mapper = "#{@vg}_#{name}"
    device = "/dev/#{@vg}/#{name}"
    run('cryptsetup', 'luksFormat', '--type', 'luks2', '--cipher', 'aes-xts-plain64', '--key-size', '512',
        '--pbkdf', 'pbkdf2', '--pbkdf-force-iterations', '1000', '--batch-mode', '--key-file=-', device, input: @key)
    @mappers << mapper
    run('cryptsetup', 'open', '--allow-discards', '--key-file=-', device, mapper, input: @key)
    run('mkfs.xfs', '-q', '-K', '-f', '-m', 'reflink=0', '-l', 'size=64m', "/dev/mapper/#{mapper}")
    path = File.join(@dir, name)
    FileUtils.mkdir_p(path)
    run('mount', '-t', 'xfs', '-o', 'nodev,nosuid,noatime,prjquota', "/dev/mapper/#{mapper}", path)
    @mounts << path
    run('xfs_quota', '-x', '-c', "project -s -p #{path} 1", path)
    quota(name, 2048)
  end

  def path(name)
    File.join(@dir, name)
  end
  def mapper(name)
    "#{@vg}_#{name}"
  end
  def quota(name, mib)
    run('xfs_quota', '-x', '-c', "limit -p bsoft=#{mib}m bhard=#{mib}m 1", path(name))
  end

  def snapshot
    # dmsetup thin status is integer mapped SECTORS, not lvs rounded Data%.
    vols = %w[a b churn].to_h do |name|
      fields = run('dmsetup', 'status', "#{@vg}-#{name}").split
      raise 'unexpected thin status' unless fields[2] == 'thin' && fields[3].match?(/\A\d+\z/)
      [name, fields[3].to_i * 512]
    end
    f = run('dmsetup', 'status', "#{@vg}-pool-tpool").split
    raise 'unexpected pool status' unless f[2] == 'thin-pool'
    meta_used, meta_total = f[4].split('/').map(&:to_i)
    data_used, data_total = f[5].split('/').map(&:to_i)
    {volumes: vols, pool_data_used: data_used * 65536, pool_data_total: data_total * 65536,
     pool_metadata_used: meta_used * 4096, pool_metadata_total: meta_total * 4096, flags: f[7..]}
  end

  def settle
    run('sync')
    sleep 1.2 # dm-thin periodically commits metadata; do not infer from trim exit.
    snapshot
  end

  def write(name, filename, mib)
    run('dd', 'if=/dev/zero', "of=#{path(name)}/#{filename}", 'bs=1M', "count=#{mib}", 'conv=fdatasync', 'status=none')
  end

  def trim(name)
    run('sync', '-f', path(name))
    run('fstrim', path(name))
    settle
  end

  def reclaim
    %w[a b churn].each { |n| trim(n) }
    before = settle
    write('a', 'payload', 768)
    held = File.open("#{path('a')}/payload", 'rb')
    allocated = settle
    quota('a', 512) # Enforcement remains active while use exceeds the target.
    File.unlink("#{path('a')}/payload")
    open_deleted = trim('a')
    assert('trim cannot release an open deleted file',
           open_deleted[:volumes]['a'] >= allocated[:volumes]['a'] - 4*MIB)
    _, permitted = command('dd', 'if=/dev/zero', "of=#{path('a')}/denied", 'bs=1M', 'count=1', 'conv=fdatasync', 'status=none', allow_failure: true)
    assert('project hard quota rejects new allocation above lowered grant', !permitted)
    held.close
    FileUtils.rm_f("#{path('a')}/denied")
    released = trim('a')
    freed_volume = open_deleted[:volumes]['a'] - released[:volumes]['a']
    freed_pool = open_deleted[:pool_data_used] - released[:pool_data_used]
    assert('closed file plus trim releases physical volume and pool mappings', freed_volume >= 760*MIB && freed_pool >= 760*MIB)
    quota('b', 2816)
    write('b', 'received', 768)
    reused = settle
    assert('another encrypted filesystem uses the released pool space', reused[:volumes]['b'] - released[:volumes]['b'] >= 768*MIB)
    @results[:observations][:reclaim] = {before: before, allocated: allocated, open_deleted: open_deleted, released: released, reused: reused}
    File.unlink("#{path('b')}/received")
    trim('b')
    quota('a', 2048)
    quota('b', 2048)
  end

  def discard_faults
    write('a', 'delayed', 512)
    allocated = settle
    File.unlink("#{path('a')}/delayed")
    delayed = settle
    assert('deletion without trim retains thin allocation', delayed[:volumes]['a'] >= allocated[:volumes]['a'] - 4*MIB)
    # Real failure: mapping no longer advertises discard, FITRIM must fail.
    run('cryptsetup', 'refresh', '--disable-external-tokens', '--key-file=-', mapper('a'), input: @key)
    _, success = command('fstrim', path('a'), allow_failure: true)
    failed = settle
    assert('disabled dm-crypt discard fails trim without releasing mappings', !success && failed[:volumes]['a'] >= delayed[:volumes]['a'])
    run('cryptsetup', 'refresh', '--allow-discards', '--key-file=-', mapper('a'), input: @key)
    recovered = trim('a')
    assert('restoring discard releases delayed blocks', failed[:volumes]['a'] - recovered[:volumes]['a'] >= 504*MIB)
    @results[:observations][:discard] = {delayed: delayed, failed: failed, recovered: recovered}
  end

  def restart
    content = SecureRandom.random_bytes(1 << 20)
    File.binwrite("#{path('a')}/persist", content)
    run('sync', '-f', path('a'))
    identity = run('lvs', '--noheadings', '-o', 'lv_uuid', "#{@vg}/a").strip
    run('umount', path('a'))
    run('cryptsetup', 'close', mapper('a'))
    run('lvchange', '-an', "#{@vg}/a")
    run('lvchange', '-ay', "#{@vg}/a")
    run('cryptsetup', 'open', '--allow-discards', '--key-file=-', "/dev/#{@vg}/a", mapper('a'), input: @key)
    run('mount', '-t', 'xfs', '-o', 'nodev,nosuid,noatime,prjquota', "/dev/mapper/#{mapper('a')}", path('a'))
    assert('cold mapping reopen preserves identity and data', File.binread("#{path('a')}/persist") == content && identity == run('lvs', '--noheadings', '-o', 'lv_uuid', "#{@vg}/a").strip)
    quota_report = run('xfs_quota', '-x', '-c', 'report -p -b -n', path('a'))
    assert('project quota survives unmount and mapping restart', quota_report.lines.any? { |l| l.split[0] == '#1' && l.split[3] == '2097152' })
    File.unlink("#{path('a')}/persist")
    trim('a')
  end

  def pool_discards(mode)
    %w[a b churn].each do |name|
      run('umount', path(name))
      run('cryptsetup', 'close', mapper(name))
      run('lvchange', '-an', "#{@vg}/#{name}")
    end
    run('lvchange', '-an', "#{@vg}/pool")
    run('lvchange', '--discards', mode, "#{@vg}/pool")
    %w[a b churn].each do |name|
      run('lvchange', '-ay', "#{@vg}/#{name}")
      run('cryptsetup', 'open', '--allow-discards', '--key-file=-', "/dev/#{@vg}/#{name}", mapper(name), input: @key)
      run('mount', '-t', 'xfs', '-o', 'nodev,nosuid,noatime,prjquota', "/dev/mapper/#{mapper(name)}", path(name))
    end
  end

  def quota_counterexample
    quota('churn', 256)
    # Exercise ignored discard in the pool as well as the dm-crypt failure
    # above; after restoring discard, retained live chunks must still count.
    pool_discards('ignore')
    before = settle
    # Allocate complete chunks, then punch out all but one filesystem block in
    # each chunk. Quota usage falls but every thin chunk still has live data.
    # Ignored discard additionally prevents any whole freed chunk reclamation.
    File.open("#{path('churn')}/sparse", 'wb') do |f|
      8.times do |round|
        128.times { f.write('x' * MIB) }
        f.fsync
        args = []
        2048.times do |i|
          offset = round * 128*MIB + i * 65536 + 4096
          args.concat(['-c', "fpunch #{offset} 61440"])
        end
        run('xfs_io', *args, "#{path('churn')}/sparse")
        f.seek((round + 1) * 128*MIB)
      end
    end
    _, trim_success = command('fstrim', path('churn'), allow_failure: true)
    after = settle
    allocated = after[:volumes]['churn'] - before[:volumes]['churn']
    assert('project quota does not cap mapped bytes under ignored discard and churn', allocated > 512*MIB,
           quota_bytes: 256*MIB, extra_mapped_bytes: allocated, trim_success: trim_success)
    @results[:observations][:quota_counterexample] = {before: before, after: after, quota_bytes: 256*MIB, trim_success: trim_success, quota_report: run('xfs_quota', '-x', '-c', 'report -p -b -n', path('churn'))}
    pool_discards('nopassdown')
    fragmented = trim('churn')
    assert('working trim cannot reclaim chunks containing live filesystem blocks',
           fragmented[:volumes]['churn'] > 512*MIB)
    @results[:observations][:quota_counterexample][:after_working_trim] = fragmented
    File.unlink("#{path('churn')}/sparse")
    trim('churn')
  end

  def benchmarks
    # Alternating order, same VM and encryption/XFS settings. Fio JSON records
    # actual issued bytes and latency. Neither cache HTTP nor hosted NVMe claim.
    %w[thick a a thick].each_with_index do |name, round|
      quota(name, 2048)
      %w[write read randwrite randread].each do |rw|
        out = run('fio', '--name=cache', "--filename=#{path(name)}/bench", '--size=512m',
                  "--rw=#{rw}", "--bs=#{rw.start_with?('rand') ? '4k' : '1m'}", '--ioengine=libaio',
                  '--direct=1', '--iodepth=32', '--runtime=8', '--time_based=1', '--group_reporting', '--output-format=json')
        job = JSON.parse(out)['jobs'].first
        raise "fio reported an I/O error" unless job['error'] == 0
        metric = job[rw.include?('write') ? 'write' : 'read']
        @results[:benchmarks] << {layout: name == 'a' ? 'thin' : 'thick', round: round, workload: rw,
                                 bandwidth_bytes: metric['bw_bytes'], iops: metric['iops'],
                                 mean_latency_ns: metric['clat_ns']['mean'], p99_latency_ns: metric['clat_ns']['percentile']['99.000000']}
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      16.times do
        write(name, 'evict', 64)
        File.unlink("#{path(name)}/evict")
        run('fstrim', path(name))
      end
      @results[:benchmarks] << {layout: name == 'a' ? 'thin' : 'thick', round: round,
                               workload: '16x64MiB_write_delete_trim', seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started}
      File.unlink("#{path(name)}/bench")
      run('fstrim', path(name))
    end
  end

  def cleanup
    @mounts.reverse_each { |p| command('umount', p, allow_failure: true) }
    @mappers.reverse_each { |m| command('cryptsetup', 'close', m, allow_failure: true) }
    command('vgremove', '-y', @vg, allow_failure: true)
    command('pvremove', '-y', @loop, allow_failure: true) if @loop
    command('losetup', '-d', @loop, allow_failure: true) if @loop
    # Do not unlink a still-attached backing file if cleanup was incomplete.
    remaining = false
    20.times do
      remaining = @loop && !run('losetup', '-j', File.join(@dir, 'pv.img')).strip.empty?
      break unless remaining
      sleep 0.1 # loop detach is asynchronous while udev finishes its inspection.
    end
    @results[:cleanup] = {loop_detached: !remaining}
    raise "cleanup incomplete; preserve #{@dir} for inspection" if remaining
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
    @key.replace("\0" * @key.bytesize)
  end
end

trap('TERM') { raise Interrupt }
if $PROGRAM_NAME == __FILE__
  fixture = Fixture.new
  begin
    fixture.setup
    fixture.reclaim
    fixture.discard_faults
    fixture.restart
    fixture.quota_counterexample
    fixture.benchmarks
    fixture.results[:completed] = true
  ensure
    begin
      fixture.cleanup
    ensure
      puts JSON.pretty_generate(fixture.results)
    end
  end
end
