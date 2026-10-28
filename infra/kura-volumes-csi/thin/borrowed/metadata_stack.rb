#!/usr/bin/env ruby
require_relative 'stack'
abort 'explicit private 128-device scale profile required' unless ENV['KURA_BORROWED_METADATA_SCALE']=='128'
class MetadataProbe < BorrowedProbe
  def qualify
    initial=snapshot
    payload=SecureRandom.random_bytes(4096)
    paths=[]
    128.times do |index|
      n=index+1
      create(n,'bench','unit',256<<20)
      path=File.join(@exports,'bench','units',id(n),'segments','scattered')
      paths << path
      File.open(path,'wb') do |f|
        64.times{|i|f.seek(i*(8<<20));f.write(payload)}
        f.fsync
      end
      warn "SCALE_DEVICES=#{n}" if n%16==0
    end
    full=snapshot
    check('all configured devices are present and physically backed',full['volumes'].size==128 && full['available_commitment_bytes']>0)
    _,ok=rpc('create',id:129,owner:'bench',kind:'unit',bytes:256<<20)
    check('device 129 is refused despite spare data commitment',!ok && snapshot['volumes'].size==128)
    check('128-device metadata remains below conservative reserve',full['metadata_used_bytes']<full['metadata_total_bytes']-full['metadata_reserve_bytes'])
    pressured=call('pressure',kind:'metadata')
    check('metadata reserve crossing withdraws healthy admission',!pressured['healthy'])
    _,ok=rpc('create',id:129,owner:'bench',kind:'unit',bytes:256<<20)
    check('metadata pressure refuses additional allocation',!ok)
    call('restart')
    started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    recovered=call('cold-pool')
    seconds=Process.clock_gettime(Process::CLOCK_MONOTONIC)-started
    check('closed mappings and deactivated pool recover all identities',full['volumes'].to_h{|v|[v['volume_id'],v['lv_uuid']]}==recovered['volumes'].to_h{|v|[v['volume_id'],v['lv_uuid']]})
    paths.each do |path|
      File.open(path,'rb'){|f|f.seek(63*(8<<20));raise 'recovered checksum mismatch' unless f.read(4096)==payload}
    end
    check('all 128 scattered files survive cold pool activation',true)
    128.times{|i|call('delete',id:i+1)}
    empty=snapshot
    check('all mapped allocations and commitments disappear after deletion',empty['volumes'].empty? && empty['committed_bytes']==0 && empty['data_used_bytes']==0)
    @report[:observations][:metadata_scale]={devices:128,scattered_chunks_per_device:64,cold_pool_seconds:seconds,initial:initial,full:full,pressured:pressured,recovered:recovered,deleted:empty}
  end
end
probe=MetadataProbe.new(ARGV.fetch(0))
begin
  probe.qualify
rescue Exception=>e
  probe.report[:failure]="#{e.class}: #{e.message}"
  raise
ensure
  begin;probe.cleanup;ensure
    File.write(ENV.fetch('KURA_BORROWED_REPORT','/tmp/kura-borrowed-results.json'),JSON.pretty_generate(probe.report))
    puts JSON.generate(probe.report.reject{|k,_|k==:runtime_logs})
  end
end
