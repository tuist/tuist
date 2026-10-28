#!/usr/bin/env ruby
require 'json'
require 'open3'
require 'fileutils'
require 'securerandom'
require 'net/http'
require 'openssl'
require 'base64'
require 'digest'
abort 'private disposable Linux VM only' unless RUBY_PLATFORM.include?('linux') && Process.uid.zero? && ENV['KURA_BORROWED_DISPOSABLE_VM']=='1'
class BorrowedProbe
  GIB=1<<30
  attr_reader :report
  def initialize(config)
    @cfg=JSON.parse(File.read(config)); @root=@cfg.fetch('root'); @exports=@cfg.fetch('exports')
    @containers={}; @generation=0; @report={assertions:[],observations:{},benchmarks:[]}
    @image=ENV.fetch('KURA_BORROWED_IMAGE','kura:borrowed-prototype')
    @bench=ENV.fetch('KURA_BORROWED_BENCH')
    secret=SecureRandom.hex(32)
    b64=->(o){Base64.urlsafe_encode64(JSON.generate(o),padding:false)}
    unsigned=[b64.call(alg:'HS256',typ:'JWT'),b64.call(sub:'disposable-probe',type:'user',scopes:['project_cache_write'],cache_grants:{project:{read:['default/shared'],write:['default/shared']}},exp:Time.now.to_i+14400)].join('.')
    @token=unsigned+'.'+Base64.urlsafe_encode64(OpenSSL::HMAC.digest('sha256',secret,unsigned),padding:false)
    @token_file=File.join(@root,'cache-token'); File.write(@token_file,@token,perm:0600)
    @env_file=File.join(@root,'runtime-env')
    env={KURA_PORT:4000,KURA_INTERNAL_PORT:7443,KURA_NODE_URL:'http://127.0.0.1:7443',KURA_PEERS:'http://127.0.0.1:7443',KURA_TENANT_ID:'default',KURA_REGION:'qualification',KURA_DATA_DIR:'/fixture/base',KURA_TMP_DIR:'/fixture/base/tmp',KURA_TMP_DIR_MAX_BYTES:2*GIB,KURA_AUTH_JWT_SECRET:secret,RUST_LOG:'warn',KURA_OTEL_SERVICE_NAME:'borrowed-qualification',KURA_OTEL_DEPLOYMENT_ENVIRONMENT:'qualification'}
    File.write(@env_file,env.map{|k,v|"#{k}=#{v}"}.join("\n")+"\n",perm:0600)
    @report[:environment]={kernel:run('uname','-r').strip,image:@image,cpu_limit:1,memory_bytes:768<<20,chunk_bytes:512<<10,keys:'fixture HMAC per-volume keys; no OpenBao/Kubernetes authorization qualification'}
  end
  def cmd(*args)
    out,err,s=Open3.capture3(*args); [out,err,s.success?]
  end
  def run(*args)
    out,err,ok=cmd(*args); raise "#{args.first} failed: #{err}\n#{out}" unless ok; out
  end
  def check(name,ok,details={})
    @report[:assertions]<<{name:name,passed:!!ok,details:details};raise "FAIL #{name}: #{details}" unless ok
    warn "PASS #{name}"
  end
  def rpc(op,**q)
    uri=URI(@cfg.fetch('endpoint')); req=Net::HTTP::Post.new(uri);req['Authorization']='Bearer '+@cfg.fetch('token');req['Content-Type']='application/json';req.body=JSON.generate(q.merge(op:op))
    res=Net::HTTP.start(uri.host,uri.port,read_timeout:120){|h|h.request(req)}
    [JSON.parse(res.body),res.code=='200']
  end
  def call(op,**q)
    value,ok=rpc(op,**q);raise "fixture #{op}: #{value}" unless ok; value
  end
  def snapshot; s=call('observe');check('pool observations remain healthy',s.fetch('healthy'),s.slice('reason'));s;end
  def id(n);format('pvc-00000000-0000-0000-0001-%012d',n);end
  def create(n,owner,kind,bytes=4*GIB);call('create',id:n,owner:owner,kind:kind,bytes:bytes);end
  def observe(s,n);s.fetch('volumes').find{|v|v.fetch('volume_id')==id(n)};end
  def control(owner,placements,drain=[])
    path=File.join(@exports,owner);FileUtils.mkdir_p(File.join(path,'units'));File.chmod(0755,path)
    @generation+=1
    pending=File.join(path,'control.new'); File.write(pending,JSON.generate(generation:@generation,placements:placements,drain:drain),perm:0644)
    File.open(pending){|f|f.fsync};File.rename(pending,File.join(path,'control.json'));File.open(path){|f|f.fsync}
  end
  def start(owner,prototype:true,cache:8*GIB)
    name='kura-borrowed-'+SecureRandom.hex(5);@containers[owner]=name
    args=['docker','run','-d','--name',name,'--user','1000:1000','--cap-drop=ALL','--security-opt=no-new-privileges','--cpus=1','--memory=768m','--memory-swap=768m','--pids-limit=256','--env-file',@env_file,'-e',"KURA_CAS_CAPACITY_BYTES=#{cache}",'-p','127.0.0.1::4000','--mount',"type=bind,src=#{@exports}/#{owner},dst=/fixture,bind-propagation=rslave"]
    args+=['-e','KURA_BORROWED_PROTOTYPE=/fixture'] if prototype
    run(*args,@image);ready(owner)
  end
  def ready(owner)
    name=@containers.fetch(owner);endpoint='http://'+run('docker','port',name,'4000/tcp').strip
    wait('runtime readiness',90){begin Net::HTTP.get_response(URI(endpoint+'/ready')).code=='200';rescue SystemCallError,EOFError;false;end}
    @endpoints||={};@endpoints[owner]=endpoint
  end
  def stop(owner)
    name=@containers.fetch(owner);run('docker','stop','-t','30',name);run('docker','rm',name);@containers.delete(owner)
  end
  def wait(label,seconds=60)
    deadline=Process.clock_gettime(Process::CLOCK_MONOTONIC)+seconds
    until yield
      raise "timeout: #{label}" if Process.clock_gettime(Process::CLOCK_MONOTONIC)>deadline
      sleep 0.5
    end
  end
  def bench(owner,working:false,corpus:nil,verify:false)
    out=File.join(@root,"bench-#{SecureRandom.hex(4)}.json")
    args=[@bench,'-base',@endpoints.fetch(owner),'-token-file',@token_file,'-account','default','-out',out]
    args+=['-working-set'] if working;args+=['-verify-corpus'] if verify;args+=['-corpus',corpus] if corpus
    run(*args);r=JSON.parse(File.read(out));check('cache responses and checksums passed',r.all?{|m|m.fetch('failures')==0});r
  end
  def stats(owner)
    run('docker','exec',@containers.fetch(owner),'sh','-c','cat /sys/fs/cgroup/cpu.stat /sys/fs/cgroup/memory.events /sys/fs/cgroup/io.stat /sys/fs/cgroup/memory.peak /sys/fs/cgroup/memory.stat')
  end
  def transfer
    create(1,'a','base');create(2,'b','base')
    %w[a b].each{|o|control(o,['base']);start(o)}
    base_before=snapshot
    corpus=File.join(@root,'a-base-corpus.json');bench('a',working:true,corpus:corpus)
    create(3,'a','unit') # Hot-published after both runtimes are running.
    control('a',[id(3)])
    borrowed=File.join(@exports,'a','units',id(3),'segments')
    bench('a',working:true)
    check('runtime placed real segments in borrowed filesystem',Dir.glob(borrowed+'/*.seg').any?)
    file=Dir.glob(borrowed+'/*.seg').first;@held=File.open(file,'rb');held_prefix=@held.read(4096);@held.rewind
    charged=snapshot;denied,ok=rpc('create',id:4,owner:'b',kind:'unit',bytes:4*GIB)
    check('recipient cannot spend outstanding donor backing',!ok,denied)
    check('logical ceilings exceed physical capacity',32*GIB>charged.fetch('usable_bytes'))
    call('fail-trim',fail:true)
    failure,ok=rpc('reclaim',id:3)
    check('injected discard failure is exercised',!ok,failure)
    control('a',['base'],[id(3)])
    # A normal write rotates away from the drained unit; the prototype worker
    # retires its sealed segments via the real ring/index/handle cleanup.
    bench('a',working:true)
    wait('targeted runtime retirement'){Dir.glob(borrowed+'/*.seg').empty?}
    held_state=snapshot
    check('runtime unlink does not release the unit commitment',held_state['committed_bytes']==charged['committed_bytes'])
    check('open unlinked segment retains mapped allocation',observe(held_state,3).fetch('mapped_bytes')>=@held.stat.size)
    failed,ok=rpc('delete',id:3)
    check('normal CSI cleanup refuses held-open filesystem',!ok,failed)
    restarted=call('restart')
    check('CSI restart retains pending unit charge',restarted['committed_bytes']==charged['committed_bytes'])
    run('docker','restart',@containers.fetch('a'));ready('a')
    bench('a',verify:true,corpus:corpus)
    check('reader survives unlink and runtime restart',@held.read(4096)==held_prefix)
    @held.close;@held=nil
    started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    wait('normal CSI unit deletion after final close'){_,ok=rpc('delete',id:3);ok}
    released=snapshot
    check('confirmed deletion releases full unit commitment',charged['committed_bytes']-released['committed_bytes']==observe(charged,3).fetch('virtual_bytes'))
    check('deleted unit absent from authoritative inventory',observe(released,3).nil?)
    create(4,'b','unit');control('b',['base',id(4)])
    before=stats('b');phases=bench('b');after=stats('b');received=snapshot
    check('recipient uses transferred backing',observe(received,4).fetch('mapped_bytes')>GIB)
    [1,2].each{|n|check('base identity survives transfer',observe(base_before,n).fetch('lv_uuid')==observe(received,n).fetch('lv_uuid'))}
    @report[:observations][:transfer]={charged:charged,held:held_state,released:released,received:received,delete_and_recipient_seconds:Process.clock_gettime(Process::CLOCK_MONOTONIC)-started,recipient_phases:phases,cpu_before:before,cpu_after:after}
    %w[a b].each{|o|stop(o)}
    [1,2,4].each{|n|call('delete',id:n)}
    call('fail-trim',fail:false)
    check('all transfer commitments released',snapshot.fetch('committed_bytes')==0)
  end
  def benchmarks
    # All runs use the same experimental binary, 4 GiB ring, 1 CPU, 768 MiB,
    # authenticated client and workload. Production mode simply omits opt-in.
    %w[plain mono multi multi mono plain].each_with_index do |layout,round|
      warn "BENCH #{round+1}/6 #{layout}"
      owner='bench';n=5+round
      FileUtils.mkdir_p(File.join(@exports,owner,'units'))
      if layout=='plain'
        @plain_file=File.join(@root,'plain.img');File.open(@plain_file,'wb'){|f|f.truncate(13*GIB)}
        @plain_loop=run('losetup','--direct-io=on','--find','--show',@plain_file).strip
        run('mkfs.xfs','-f','-m','reflink=0','-l','size=64m',@plain_loop)
        @plain_mount=File.join(@exports,owner,'base');FileUtils.mkdir_p(@plain_mount)
        run('mount','-o','nodev,nosuid,noatime',@plain_loop,@plain_mount);File.chown(1000,1000,@plain_mount)
      else
        create(n,owner,'base',layout=='mono' ? 8*GIB : 4*GIB)
        create(11+round%2,owner,'unit') if layout=='multi'
      end
      control(owner,layout=='multi' ? ['base',id(11+round%2)] : ['base'])
      start(owner,prototype:layout=='multi',cache:4*GIB)
      before=stats(owner);phases=bench(owner);after=stats(owner)
      @report[:benchmarks]<<{layout:layout,round:round,phases:phases,before:before,after:after,physical:snapshot}
      @report[:benchmarks].last[:working_set]=bench(owner,working:true)
      stop(owner)
      if layout=='plain'
        cleanup_plain
      else
        call('delete',id:n);call('delete',id:11+round%2) if layout=='multi'
      end
    end
  end
  def cleanup_plain
    return unless @plain_loop
    run('umount',@plain_mount);run('losetup','-d',@plain_loop)
    wait('private plain loop detach'){run('losetup','-j',@plain_file).strip.empty?}
    File.unlink(@plain_file);@plain_loop=nil
  end
  def cleanup
    @held&.close
    @containers.each_value do |name|
      @report[:runtime_logs]||={};@report[:runtime_logs][name]=cmd('docker','logs',name)[0..1].join
      run('docker','rm','-f',name)
    end
    @containers.clear
    cleanup_plain
    @report[:containers_cleaned]=true
  end
end
probe=BorrowedProbe.new(ARGV.fetch(0))
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
