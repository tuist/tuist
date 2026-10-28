#!/usr/bin/env ruby
require_relative 'stack'

# Exercises the actual parent/child API; no direct fixture control-file writes.
class ChildProbe < BorrowedProbe
  def parent(n);snapshot.fetch('volumes').find{|v|v.fetch('volume_id')==id(n)};end
  def request_for(n,unit,action,bytes:0)
    parent(n).slice('volume_id','lv_uuid','pool_uuid','pod_uid','generation').merge('operation_id'=>SecureRandom.uuid,'unit_id'=>unit,'action'=>action,'cache_bytes'=>bytes)
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
  probe.benchmarks
rescue Exception=>e
  probe.report[:failure]="#{e.class}: #{e.message}"
  raise
ensure
  begin;probe.cleanup;ensure
    File.write(ENV.fetch('KURA_BORROWED_REPORT','/tmp/kura-borrowed-results.json'),JSON.pretty_generate(probe.report))
    puts JSON.generate(probe.report.reject{|k,_|k==:runtime_logs})
  end
end
