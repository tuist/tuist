#!/usr/bin/env ruby
# ONLY in a disposable Linux VM. Never accept an existing device or filesystem.
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require 'digest'

abort 'requires a disposable Linux VM, root and KURA_FSCRYPT_DISPOSABLE_VM=1' unless
  RUBY_PLATFORM.include?('linux') && Process.uid.zero? && ENV['KURA_FSCRYPT_DISPOSABLE_VM'] == '1'
ENV['LC_ALL'] = 'C'

class FscryptFixture
  MIB = 1 << 20
  attr_reader :result
  def initialize
    @root = Dir.mktmpdir('kura-fscrypt-')
    File.chmod(0755, @root)
    @mounts, @loops, @keys, @ids = [], [], {}, {}
    @result = {schema: 1, assertions: [], observations: {}, benchmarks: []}
    @helper = File.join(@root, 'probe')
    run('cc', '-O2', '-Wall', '-Wextra', '-Werror', File.join(__dir__, 'probe.c'), '-o', @helper)
  end
  def cmd(*args, input: '', failure: false)
    out, err, status = Open3.capture3(*args, stdin_data: input)
    raise "#{args.first} failed: #{err}" unless status.success? || failure
    [out, err, status.success?]
  end
  def run(*args, **opts); cmd(*args, **opts).first; end
  def check(name, condition, **details)
    @result[:assertions] << {name: name, passed: !!condition, **details}
    raise "FAIL #{name}: #{details}" unless condition
    warn "PASS #{name}"
  end
  def user(*args, **opts)
    cmd('setpriv', '--reuid=1000', '--regid=1000', '--clear-groups', '--', *args, **opts)
  end
  def image(name, size)
    f = File.join(@root, "#{name}.img")
    File.open(f, 'wb', 0600) { |io| io.truncate(size) }
    loop = run('losetup', '--direct-io=on', '--find', '--show', f).strip
    @loops << loop
    check('loop belongs to private fixture', run('losetup', '-n', '-O', 'BACK-FILE', loop).strip == f)
    loop
  end
  def mount(device, name, type, options)
    path = File.join(@root, name)
    FileUtils.mkdir_p(path)
    run('mount', '-t', type, '-o', options, device, path)
    @mounts << path
    path
  end
  def setup
    @result[:environment] = {kernel: run('uname', '-r').strip, fscryptctl: run('fscryptctl', '--version').strip,
      backing: 'private loop files in disposable VM; no hosted storage', uid: 1000}
    @device = image('ext4', 3 << 30)
    run('mkfs.ext4', '-q', '-F', '-m', '0', '-O', 'encrypt,project,quota', '-E', 'lazy_itable_init=0,lazy_journal_init=0', @device)
    run('tune2fs', '-Q', 'prjquota', @device)
    @ext = mount(@device, 'ext4', 'ext4', 'nodev,nosuid,noatime,prjquota')
    %w[a b].each_with_index do |name, i|
      path = tenant(name)
      Dir.mkdir(path)
      @keys[name] = SecureRandom.random_bytes(64)
      @ids[name] = run('fscryptctl', 'add_key', @ext, input: @keys[name]).strip
      raise 'invalid key identifier' unless @ids[name].match?(/\A[0-9a-f]{32}\z/)
      run('fscryptctl', 'set_policy', @ids[name], path)
      run(@helper, 'project', path, (i+1).to_s)
      File.chown(1000, 1000, path)
      limit(name, 768)
    end
    check('distinct tenant encryption policies', @ids['a'] != @ids['b'])
    @result[:observations][:policies] = %w[a b].to_h { |n| [n, run('fscryptctl', 'get_policy', tenant(n))] }
    @result[:observations][:virtual_ceilings] = {a: 4 << 30, b: 4 << 30, physical_filesystem: space['total']}
    check('aggregate logical ceilings exceed physical filesystem', 8 << 30 > space['total'])
  end
  def tenant(name); File.join(@ext, name); end
  def project(name); name == 'a' ? '1' : '2'; end
  def limit(name, mib, inodes: 4096)
    run(@helper, 'set', @device, project(name), (mib*MIB).to_s, inodes.to_s)
    check('kernel quota readback', quota(name)['hard'] == mib*MIB)
  end
  def quota(name); JSON.parse(run(@helper, 'get', @device, project(name))); end
  def space; JSON.parse(run(@helper, 'space', @ext)); end
  def sync; run('sync', '-f', @ext); end
  def write(name, file, mib, failure: false)
    user('dd', 'if=/dev/urandom', "of=#{tenant(name)}/#{file}", 'bs=1M', "count=#{mib}", 'conv=fsync', 'status=none', failure: failure)
  end
  def reclamation
    write('a', 'held', 512)
    write('b', 'seed', 384)
    before = {a: quota('a'), b: quota('b'), space: space}
    handle = File.open(File.join(tenant('a'), 'held'), 'rb')
    File.unlink(handle.path)
    sync
    held = {a: quota('a'), space: space}
    check('unlinked open allocation remains charged', held[:a]['used'] >= 512*MIB)
    limit('a', 256)
    failed = write('a', 'refused', 32, failure: true)
    check('unprivileged growth refused above reduced quota', !failed[2] && failed[1].include?('Disk quota exceeded'))
    # A requested shrink is not enough to increase B. Observe max(usage, quota).
    charge = quota('a').values_at('used', 'hard').max + quota('b').values_at('used', 'hard').max
    check('held blocks prevent spending pending shrink', charge > (256+768)*MIB)
    handle.close
    sync
    released = {a: quota('a'), space: space}
    check('close releases quota allocation without TRIM', held[:a]['used']-released[:a]['used'] >= 512*MIB)
    check('filesystem confirms physical release without TRIM', released[:space]['available']-held[:space]['available'] >= 500*MIB)
    # Fixed 1.5 GiB admission budget including both hard quotas; physical headroom is separate.
    limit('b', 1280)
    check('redistributed quotas fit fixed admission budget', quota('a')['hard']+quota('b')['hard'] == 1536*MIB)
    write('b', 'borrowed', 768)
    check('B consumes released capacity within new grant', quota('b')['used'] >= 1152*MIB && quota('b')['used'] <= quota('b')['hard'])
    @result[:observations][:reclaim] = {before: before, held: held, released: released, after: {a: quota('a'), b: quota('b'), space: space}}
    %w[seed borrowed].each { |f| File.unlink(File.join(tenant('b'), f)) }
    File.unlink(File.join(tenant('a'), 'refused'))
    sync
  ensure
    handle&.close unless handle&.closed?
  end
  def pressure
    limit('a', 128)
    writers = 8.times.map { |i| Thread.new { write('a', "writer-#{i}", 32, failure: true) } }.map(&:value)
    sync
    check('concurrent writes cannot cross kernel hard quota', quota('a')['used'] <= quota('a')['hard'] && writers.any? { |r| !r[2] })
    write('b', 'healthy', 16)
    check('other tenant remains readable under quota pressure', File.size(File.join(tenant('b'), 'healthy')) == 16*MIB)
    Dir.glob(File.join(tenant('a'), 'writer-*')).each { |f| File.unlink(f) }
    limit('a', 128, inodes: 32)
    out = user('ruby', '-e', '100.times { |i| File.write(File.join(ARGV[0], "inode-#{i}"), "x") }', tenant('a'), failure: true)
    check('inode hard quota stops small-file exhaustion', !out[2] && out[1].include?('Disk quota exceeded') && quota('a')['inodes'] <= 32)
    Dir.glob(File.join(tenant('a'), 'inode-*')).each { |f| File.unlink(f) }
    limit('a', 768)
    limit('b', 768)
  end
  def keys_and_restart
    write('a', 'persistent', 8)
    file = File.join(tenant('a'), 'persistent')
    digest = Digest::SHA256.file(file).hexdigest
    user(@helper, 'mmap', file)
    check('mmap and pread return identical decrypted bytes', true)
    run('fscryptctl', 'remove_key', @ids['a'], @ext)
    check('A key removal denies new opens', !user('dd', "if=#{file}", 'of=/dev/null', 'status=none', failure: true)[2])
    check('removing A key leaves B usable', user('dd', "if=#{tenant('b')}/healthy", 'of=/dev/null', 'status=none')[2])
    wrong = run('fscryptctl', 'add_key', @ext, input: SecureRandom.random_bytes(64)).strip
    check('wrong key cannot unlock A', !user('dd', "if=#{file}", 'of=/dev/null', 'status=none', failure: true)[2])
    run('fscryptctl', 'remove_key', wrong, @ext)
    check('same key restores stable identity', run('fscryptctl', 'add_key', @ext, input: @keys['a']).strip == @ids['a'])
    before = {a: quota('a'), b: quota('b')}
    sync
    run('umount', @ext)
    @mounts.delete(@ext)
    mount(@device, 'ext4', 'ext4', 'nodev,nosuid,noatime,prjquota')
    check('cold remount has no unlocked tenant key', !user('dd', "if=#{file}", 'of=/dev/null', 'status=none', failure: true)[2])
    %w[a b].each { |n| check('key identifier survives remount', run('fscryptctl', 'add_key', @ext, input: @keys[n]).strip == @ids[n]) }
    check('reopen preserves content and quota limits', Digest::SHA256.file(file).hexdigest == digest && quota('a')['hard'] == before[:a]['hard'] && quota('b')['hard'] == before[:b]['hard'])
    File.unlink(file)
    File.unlink(File.join(tenant('b'), 'healthy'))
  end
  def benchmarks
    # Buffered, synchronous I/O on every layout: no silent fscrypt O_DIRECT fallback comparison.
    # These VM figures are not hosted NVMe or application throughput.
    @xdev = image('shared-xfs', 3 << 30)
    run('mkfs.xfs', '-q', '-f', '-m', 'reflink=0', @xdev)
    xfs = mount(@xdev, 'xfs', 'xfs', 'nodev,nosuid,noatime,prjquota')
    File.chown(1000, 1000, xfs)
    plain = File.join(@ext, 'plain')
    Dir.mkdir(plain)
    File.chown(1000, 1000, plain)
    limit('a', 2048)
    layouts = {'xfs'=>xfs, 'ext4'=>plain, 'fscrypt'=>tenant('a')}
    @vg = "kura_fscrypt_#{SecureRandom.hex(4)}"
    pv = image('lvm-controls', 10 << 30)
    run('pvcreate', '-y', pv)
    run('vgcreate', @vg, pv)
    run('lvcreate', '-y', '--type', 'thin-pool', '-L', '4G', '--poolmetadatasize', '128M',
      '--chunksize', '512K', '--discards', 'nopassdown', '-n', 'pool', @vg)
    run('lvchange', '--errorwhenfull', 'y', "#{@vg}/pool")
    @mappers = []
    %w[thick thin].each do |name|
      if name == 'thin'
        run('lvcreate', '-y', '-V', '3G', '--thinpool', "#{@vg}/pool", '-n', name)
      else
        run('lvcreate', '-y', '-L', '3G', '-n', name, @vg)
      end
      key = SecureRandom.random_bytes(32)
      device = "/dev/#{@vg}/#{name}"
      mapper = "#{@vg}_#{name}"
      run('cryptsetup', 'luksFormat', '--type', 'luks2', '--cipher', 'aes-xts-plain64', '--key-size', '512',
        '--pbkdf', 'pbkdf2', '--pbkdf-force-iterations', '1000', '--batch-mode', '--key-file=-', device, input: key)
      run('cryptsetup', 'open', '--allow-discards', *(name == 'thin' ? ['--perf-submit_from_crypt_cpus'] : []),
        '--key-file=-', device, mapper, input: key)
      key.replace("\0" * key.bytesize)
      @mappers << mapper
      run('mkfs.xfs', '-q', '-f', '-K', '-m', 'reflink=0', '-l', 'size=64m', "/dev/mapper/#{mapper}")
      target = mount("/dev/mapper/#{mapper}", name, 'xfs', 'nodev,nosuid,noatime,prjquota')
      File.chown(1000, 1000, target)
      layouts[name] = target
    end
    order = %w[xfs ext4 fscrypt thick thin thin thick fscrypt ext4 xfs]
    order.each_with_index do |layout, round|
      path = File.join(layouts.fetch(layout), 'bench')
      %w[write read randwrite randread].each do |rw|
        out = user('fio', '--name=cache', "--filename=#{path}", '--size=512m', "--rw=#{rw}",
          "--bs=#{rw.start_with?('rand') ? '4k' : '1m'}", '--ioengine=psync', '--direct=0', '--iodepth=1',
          '--runtime=8', '--time_based=1', '--end_fsync=1', '--group_reporting', '--output-format=json').first
        job = JSON.parse(out)['jobs'].first
        raise 'fio I/O failure' unless job['error'] == 0
        metric = job[rw.include?('write') ? 'write' : 'read']
        @result[:benchmarks] << {layout: layout, round: round, workload: rw, bandwidth_bytes: metric['bw_bytes'],
          iops: metric['iops'], p99_latency_ns: metric.dig('clat_ns', 'percentile', '99.000000')}
      end
      File.unlink(path)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      16.times do
        user('dd', 'if=/dev/urandom', "of=#{path}", 'bs=1M', 'count=64', 'conv=fsync', 'status=none')
        File.unlink(path)
        # Thin requires discard to release pool mappings. Shared filesystems
        # release blocks internally; SSD TRIM is not necessary for reassignment.
        run('fstrim', layouts[layout]) if layout == 'thin'
      end
      @result[:benchmarks] << {layout: layout, round: round, workload: '16x64MiB_write_delete_reclaim',
        seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC)-started}
    end
  end
  def cleanup
    safe = true
    @mounts.reverse_each { |m| safe = cmd('umount', m, failure: true)[2] && safe }
    (@mappers || []).reverse_each { |m| safe = cmd('cryptsetup', 'close', m, failure: true)[2] && safe } if safe
    safe = cmd('vgremove', '-y', @vg, failure: true)[2] && safe if safe && @vg
    if safe
      @loops.reverse_each { |d| safe = cmd('losetup', '-d', d, failure: true)[2] && safe }
    end
    @keys.each_value { |k| k.replace("\0" * k.bytesize) }
    if safe
      FileUtils.remove_entry(@root)
    else
      warn "Cleanup incomplete; retain backing files at #{@root}"
    end
    @result[:cleanup_complete] = safe
  end
end

fixture = FscryptFixture.new
begin
  fixture.setup
  fixture.reclamation
  fixture.pressure
  fixture.keys_and_restart
  fixture.benchmarks
ensure
  fixture.cleanup
  puts JSON.pretty_generate(fixture.result)
end
raise 'fixture cleanup incomplete' unless fixture.result[:cleanup_complete]
