#!/usr/bin/env ruby
# Prepare a NEW pool from explicitly checked free extents. Never converts an LV,
# shrinks XFS, removes a device, or takes space from an existing volume.
require 'json'
require 'open3'
require 'optparse'
options = {data_mib: nil, metadata_mib: nil, max_volumes: 128, reserve_mib: 1024, metadata_reserve_mib: 64}
OptionParser.new do |parser|
  parser.on('--vg NAME') { |v| options[:vg] = v }
  parser.on('--pool NAME') { |v| options[:pool] = v }
  parser.on('--state-dir PATH') { |v| options[:state_dir] = v }
  %i[data_mib metadata_mib max_volumes reserve_mib metadata_reserve_mib].each do |key|
    parser.on("--#{key.to_s.tr('_', '-')} INTEGER", Integer) { |v| options[key] = v }
  end
end.parse!
raise 'Linux root required' unless RUBY_PLATFORM.include?('linux') && Process.uid.zero?
raise 'unexpected arguments' unless ARGV.empty?
state = options[:state_dir]
raise 'existing canonical state dir required' unless state && File.directory?(state) && File.realpath(state) == state
config_path = File.join(state, 'thin-pool.json')
raise 'configuration already exists' if File.exist?(config_path) || File.symlink?(config_path)
%i[vg pool].each { |key| raise "invalid #{key}" unless options[key]&.match?(/\A[a-zA-Z0-9_][a-zA-Z0-9_.+-]*\z/) }
raise 'reserved pool name' if options[:pool] == 'data' || options[:pool].start_with?('pvc-')
data, metadata = options.values_at(:data_mib, :metadata_mib)
raise 'explicit bounded sizes required' unless data && metadata && data.between?(1024, 2**30) && metadata.between?(64, 16384)
raise 'invalid reserve/slot profile' unless options[:reserve_mib].between?(64, data - 1) && options[:metadata_reserve_mib].between?(16, metadata - 1) && options[:max_volumes].between?(1, 1024)
# 64 KiB chunks, 128 bytes/chunk, 1 MiB/device, plus the explicit reserve.
minimum_metadata = (data * 16 * 128 + (2**20 - 1)) / 2**20 + options[:max_volumes] + options[:metadata_reserve_mib]
raise "metadata must be at least #{minimum_metadata} MiB" if metadata < minimum_metadata
config = 'devices { use_devicesfile = 0 obtain_device_list_from_udev = 0 } activation { udev_sync = 0 udev_rules = 0 } backup { backup = 0 archive = 0 }'
run = lambda do |command, *args|
  output, error, status = Open3.capture3(command, '--config', config, *args)
  raise "#{command} failed: #{error}" unless status.success?
  output
end
# Share the host-wide LVM lock directory with CSI. The VG's free space is only
# consumed by lvcreate, which fails if another administrator allocated it first.
rows = JSON.parse(run.call('lvs', '--reportformat', 'json', '-o', 'lv_name', options[:vg])).fetch('report').first.fetch('lv')
raise 'pool already exists; inspect it instead of mutating it' if rows.any? { |row| row['lv_name'] == options[:pool] }
free = Integer(run.call('vgs', '--noheadings', '--units', 'b', '--nosuffix', '-o', 'vg_free', options[:vg]).strip, 10)
# Account for both metadata and LVM's metadata spare, plus extent rounding.
raise 'insufficient unallocated VG space' if free < (data + 2 * metadata + 16) * 2**20
run.call('lvcreate', '--yes', '--type', 'thin-pool', '--size', "#{data}M", '--poolmetadatasize', "#{metadata}M", '--chunksize', '64K', '--zero', 'y', '--discards', 'passdown', '--name', options[:pool], options[:vg])
run.call('lvchange', '--errorwhenfull', 'y', "#{options[:vg]}/#{options[:pool]}")
configuration = {pool: options[:pool], data_reserve_bytes: options[:reserve_mib] * 2**20, metadata_reserve_bytes: options[:metadata_reserve_mib] * 2**20, max_volumes: options[:max_volumes]}
File.open(config_path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(JSON.generate(configuration)); f.fsync }
File.open(state) { |f| f.fsync }
puts JSON.generate(options.merge(layout: 'thin-luks-xfs-v1', mode: 'ceiling-backed-v1', created: true))
