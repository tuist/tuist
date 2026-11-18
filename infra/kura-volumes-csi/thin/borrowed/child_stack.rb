#!/usr/bin/env ruby
require_relative 'stack'

# Exercises the actual parent/child API; no direct fixture control-file writes.
class ChildProbe < BorrowedProbe
  def parent(n);snapshot.fetch('volumes').find{|v|v.fetch('volume_id')==id(n)};end
  def request_for(n,unit,action,bytes:0)
    parent(n).slice('volume_id','lv_uuid','pool_uuid','pod_uid','generation').merge('operation_id'=>SecureRandom.uuid,'unit_id'=>unit,'action'=>action,'cache_bytes'=>bytes)
  end
  def scale_and_recovery
    create(3,'a','parent',256<<20)
    # Exhaustion before LV creation must be cancellable without optimistic credit.
    failed=SecureRandom.uuid
    _,ok=rpc('unit',unit:request_for(3,failed,'create',bytes:32*GIB))
    check('unbacked child create fails',!ok)
    call('restart')
    call('unit',unit:request_for(3,failed,'abort'))
    _,ok=rpc('unit',unit:request_for(3,failed,'create',bytes:256<<20))
    check('cancelled create identity remains retired',!ok)
    partial=SecureRandom.uuid
    before_partial=snapshot
    call('fail-quota')
    _,ok=rpc('unit',unit:request_for(3,partial,'create',bytes:256<<20))
    check('quota failure interrupts child stage after mounting',!ok)
    charged=snapshot
    check('partially staged child retains its full commitment',charged['volumes'].size==2 && charged['committed_bytes']>before_partial['committed_bytes'])
    call('restart')
    aborted=call('unit',unit:request_for(3,partial,'abort'))
    check('abort closes an unrecorded mount before returning backing',aborted['volumes'].size==1 && aborted['committed_bytes']==before_partial['committed_bytes'])
    units=7.times.map do
      u=SecureRandom.uuid;call('unit',unit:request_for(3,u,'create',bytes:256<<20));u
    end
    full=snapshot
    _,ok=rpc('unit',unit:request_for(3,SecureRandom.uuid,'create',bytes:256<<20))
    check('eight device profile refuses ninth device',!ok && snapshot['committed_bytes']==full['committed_bytes'])
    paths=[File.join(@exports,'a','base')]+units.map{|u|File.join(@exports,'a','units',id(3)+'-unit-'+u,'segments')}
    payload=SecureRandom.random_bytes(4096)
    paths.each do |path|
      File.open(File.join(path,'scale'),'wb') do |f|
        # Sparse 4 KiB writes occupy separate 512 KiB thin chunks. This is
        # deliberately hostile to interpreting quota usage as mapped allocation.
        2048.times{|i|f.seek(i*(512<<10));f.write(payload)}
        f.fsync
      end
    end
    mapped=snapshot
    check('all eight devices retain physical backing under scattered writes',mapped['volumes'].size==8 && mapped['volumes'].all?{|v|v['mapped_bytes']>=GIB})
    check('metadata remains below reserve at qualified device count',mapped['metadata_used_bytes']<mapped['metadata_total_bytes']-mapped['metadata_reserve_bytes'])
    call('restart')
    paths.each do |path|
      File.open(File.join(path,'scale'),'rb') do |f|
        f.seek(2047*(512<<10));check('scattered data survives CSI reconstruction',f.read(4096)==payload)
      end
    end
    # Parent lifecycle owns deletion, including non-empty children after the
    # workload is gone; no allocator-side drain is needed for PVC teardown.
    call('delete',id:3)
    empty=snapshot
    check('parent deletion reclaims all eight detached devices',empty['volumes'].empty? && empty['committed_bytes']==0)
    @report[:observations][:metadata_scale]={slots:8,scattered_chunks_per_device:2048,full:full,mapped:mapped,deleted:empty}
  end
  def transfer
    create(1,'a','parent');create(2,'b','parent')
    initial=snapshot
    %w[a b].each{|o|start(o)}
    base=File.join(@root,'child-base-corpus.json');bench('a',working:true,corpus:base)
    unit=SecureRandom.uuid;child=id(1)+'-unit-'+unit
    grant=request_for(1,unit,'create',bytes:4*GIB)
    granted=call('unit',unit:grant)
    replay=call('unit',unit:grant)
    check('lost grant response retries without double allocation',granted['committed_bytes']==replay['committed_bytes'] && granted['volumes'].size==replay['volumes'].size)
    stale=grant.merge('operation_id'=>SecureRandom.uuid,'unit_id'=>SecureRandom.uuid)
    _,ok=rpc('unit',unit:stale);check('stale parent generation refuses another grant',!ok)
    corpus=File.join(@root,'child-corpus.json');bench('a',working:true,corpus:corpus)
    segments=File.join(@exports,'a','units',child,'segments')
    check('CSI hot child publication reaches running runtime',Dir.glob(segments+'/*.seg').any?)
    stop('a')
    before=parent(1);new_pod=SecureRandom.uuid
    recovered=call('cold-parent',id:1,pod_uid:new_pod)
    check('closed mappings restage with stable child LV identity',recovered['volumes'].find{|v|v['volume_id']==child}['lv_uuid']==granted['volumes'].find{|v|v['volume_id']==child}['lv_uuid'])
    _,ok=rpc('unit',unit:before.slice('volume_id','lv_uuid','pool_uuid','pod_uid','generation').merge('operation_id'=>SecureRandom.uuid,'unit_id'=>unit,'action'=>'drain','cache_bytes'=>0))
    check('replacement pod fences the old budget incarnation',!ok)
    start('a');bench('a',verify:true,corpus:corpus);bench('a',verify:true,corpus:base)
    file=Dir.glob(segments+'/*.seg').first;@held=File.open(file,'rb');prefix=@held.read(4096);@held.rewind
    drain=request_for(1,unit,'drain');call('unit',unit:drain)
    wait('CSI-driven idle segment retirement'){Dir.glob(segments+'/*.seg').empty?}
    charged=snapshot
    release=request_for(1,unit,'release');_,ok=rpc('unit',unit:release)
    check('CSI child release refuses an open unlinked file',!ok)
    call('restart')
    retained=snapshot
    check('interrupted release retains complete child backing',retained['committed_bytes']==charged['committed_bytes'])
    check('held reader remains readable through failed release',@held.read(4096)==prefix)
    @held.close;@held=nil
    released=call('unit',unit:release)
    check('retry completes interrupted release after final close',released['volumes'].none?{|v|v['volume_id']==child} && charged['committed_bytes']-released['committed_bytes']==(13*GIB/2))
    replay=call('unit',unit:release)
    check('release response retry never credits twice',replay['committed_bytes']==released['committed_bytes'])
    _,ok=rpc('unit',unit:request_for(1,unit,'create',bytes:4*GIB));check('released cryptographic identity cannot be reused',!ok)
    recipient=SecureRandom.uuid;grant_b=request_for(2,recipient,'create',bytes:4*GIB)
    received=call('unit',unit:grant_b)
    check('recipient obtains capacity only after donor deletion',received['committed_bytes']==charged['committed_bytes'])
    b_corpus=File.join(@root,'child-recipient-corpus.json');bench('b',working:true,corpus:b_corpus)
    recipient_id=id(2)+'-unit-'+recipient
    check('recipient writes its independently encrypted child',Dir.glob(File.join(@exports,'b','units',recipient_id,'segments','*.seg')).any?)
    [1,2].each{|n|check('stable base survives child transactions',parent(n)['lv_uuid']==initial['volumes'].find{|v|v['volume_id']==id(n)}['lv_uuid'])}
    call('unit',unit:request_for(2,recipient,'drain'))
    wait('recipient drain'){Dir.glob(File.join(@exports,'b','units',recipient_id,'segments','*.seg')).empty?}
    call('unit',unit:request_for(2,recipient,'release'))
    %w[a b].each{|o|stop(o)}
    [1,2].each{|n|call('delete',id:n)}
    check('parent and child accounting returns to zero',snapshot['committed_bytes']==0)
    @report[:observations][:child_lifecycle]={initial:initial,granted:granted,recovered:recovered,held:retained,released:released,recipient:received}
  end
end
probe=ChildProbe.new(ARGV.fetch(0))
begin
  probe.transfer
  probe.scale_and_recovery
  probe.benchmarks unless ENV['KURA_BORROWED_SKIP_BENCH']=='true'
rescue Exception=>e
  probe.report[:failure]="#{e.class}: #{e.message}"
  raise
ensure
  begin;probe.cleanup;ensure
    File.write(ENV.fetch('KURA_BORROWED_REPORT','/tmp/kura-borrowed-results.json'),JSON.pretty_generate(probe.report))
    puts JSON.generate(probe.report.reject{|k,_|k==:runtime_logs})
  end
end
