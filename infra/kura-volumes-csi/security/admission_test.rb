require 'json'
require 'yaml'
require 'open3'
require 'tempfile'
CFG=ENV.fetch('KURA_SECURITY_KUBECONFIG')
raise 'Use only the disposable kind-kura-key-security cluster' unless YAML.load_file(CFG)['current-context'] == 'kind-kura-key-security'
def kube(*args, input: nil, config: CFG)
  out,err,status=Open3.capture3('kubectl','--kubeconfig',config,*args,stdin_data:input.to_s)
  [out,err,status.success?]
end
def apply(obj)
  out,err,ok=kube('apply','-f','-',input:JSON.generate(obj)); raise err unless ok
end
policy=File.read(File.expand_path('../../helm/tuist/templates/kura-volumes-csi-admission.yaml', __dir__)).lines[1...-1].join
_,err,ok=kube('apply','-f','-',input:policy); raise err unless ok
%w(kura kura-volumes outside).each { |n| apply({'apiVersion'=>'v1','kind'=>'Namespace','metadata'=>{'name'=>n}}) }
apply({'apiVersion'=>'v1','kind'=>'ServiceAccount','metadata'=>{'name'=>'kura-volumes-csi-node','namespace'=>'kura-volumes'}})
# Deliberately broad local test role: the admission layer must reject even
# requests which RBAC alone permits. This is never installed on a hosted env.
apply({'apiVersion'=>'rbac.authorization.k8s.io/v1','kind'=>'ClusterRoleBinding','metadata'=>{'name'=>'kura-test-csi'},'roleRef'=>{'apiGroup'=>'rbac.authorization.k8s.io','kind'=>'ClusterRole','name'=>'cluster-admin'},'subjects'=>[{'kind'=>'ServiceAccount','name'=>'kura-volumes-csi-node','namespace'=>'kura-volumes'}]})
node='kura-key-security-control-plane'
# Only named fixtures in this explicitly disposable cluster are reset.
%w(11111111-1111-4111-8111-111111111111 22222222-2222-4222-8222-222222222222).each do |id|
  kube('patch','pv',"pvc-#{id}",'--type=merge','-p','{"metadata":{"finalizers":[]}}')
  kube('delete','pv',"pvc-#{id}",'--ignore-not-found','--wait=false')
end
kube('delete','pvc','test-claim','-n','kura','--ignore-not-found','--wait=false')
apply({'apiVersion'=>'v1','kind'=>'Node','metadata'=>{'name'=>'other-node'}})

apply({'apiVersion'=>'v1','kind'=>'Pod','metadata'=>{'name'=>'identity','namespace'=>'kura-volumes'},'spec'=>{'serviceAccountName'=>'kura-volumes-csi-node','nodeName'=>node,'containers'=>[{'name'=>'pause','image'=>'registry.k8s.io/pause:3.10'}]}})
uid=JSON.parse(kube('get','pod','identity','-n','kura-volumes','-o','json')[0]).dig('metadata','uid')
token,err,ok=kube('create','token','kura-volumes-csi-node','-n','kura-volumes','--bound-object-kind=Pod',"--bound-object-name=identity","--bound-object-uid=#{uid}"); raise err unless ok
config=YAML.load_file(CFG); config['users']=[{'name'=>'test-csi','user'=>{'token'=>token.strip}}]; config['contexts'].each { |c| c['context']['user']='test-csi' }
file=Tempfile.new('kura-admission-identity'); File.chmod(0600,file.path); file.write(config.to_yaml); file.close
results=[]
check=lambda do |name,allow,*args,input: nil|
  out,err,ok=kube(*args,input: input,config:file.path)
  raise "#{name}: expected #{allow}, got #{ok}: #{err}" unless ok==allow
  raise "#{name}: denied for wrong reason: #{err}" if !allow && !err.include?('ValidatingAdmissionPolicy')
  results << {name:name,result:allow ? 'allowed' : 'denied'}
end
make_pv=lambda do |id,n|
 {'apiVersion'=>'v1','kind'=>'PersistentVolume','metadata'=>{'name'=>"pvc-#{id}"},'spec'=>{'capacity'=>{'storage'=>'1Gi'},'accessModes'=>['ReadWriteOnce'],'persistentVolumeReclaimPolicy'=>'Retain','storageClassName'=>'kura-encrypted-nvme','csi'=>{'driver'=>'kura-volumes.tuist.dev','volumeHandle'=>"pvc-#{id}"},'claimRef'=>{'namespace'=>'kura','name'=>"data-#{id}",'uid'=>id},'nodeAffinity'=>{'required'=>{'nodeSelectorTerms'=>[{'matchExpressions'=>[{'key'=>'topology.kura-volumes.tuist.dev/node','operator'=>'In','values'=>[n]}]}]}}}}
end
begin
  pv=make_pv.call('11111111-1111-4111-8111-111111111111',node)
  foreign=make_pv.call('22222222-2222-4222-8222-222222222222','other-node')
unbound,err,ok=kube('create','token','kura-volumes-csi-node','-n','kura-volumes'); raise err unless ok
config['users'][0]['user']['token']=unbound.strip
File.write(file.path,config.to_yaml)
check.call('unbound identity',false,'create','-f','-',input:JSON.generate(pv))
config['users'][0]['user']['token']=token.strip
File.write(file.path,config.to_yaml)
  check.call('create own PV',true,'create','-f','-',input:JSON.generate(pv))
  check.call('create foreign PV',false,'create','-f','-',input:JSON.generate(foreign))
  apply(foreign)
  check.call('delete foreign PV',false,'delete','pv',foreign['metadata']['name'],'--wait=false')
  check.call('change own PV claim ownership',false,'patch','pv',pv['metadata']['name'],'--type=merge','-p',JSON.generate({'spec'=>{'claimRef'=>{'uid'=>'33333333-3333-4333-8333-333333333333'}}}))
  check.call('update own PV finalizer',true,'patch','pv',pv['metadata']['name'],'--type=merge','-p',JSON.generate({'metadata'=>{'finalizers'=>['external-provisioner.volume.kubernetes.io/finalizer']}}))
  claim={'apiVersion'=>'v1','kind'=>'PersistentVolumeClaim','metadata'=>{'name'=>'test-claim','namespace'=>'kura','labels'=>{'app.kubernetes.io/instance'=>'tenant-a'}},'spec'=>{'accessModes'=>['ReadWriteOnce'],'storageClassName'=>'none','resources'=>{'requests'=>{'storage'=>'1Gi'}}}}
  apply(claim)
  check.call('select own node',true,'patch','pvc','test-claim','-n','kura','--type=merge','-p',JSON.generate({'metadata'=>{'annotations'=>{'volume.kubernetes.io/selected-node'=>node}}}))
  check.call('change claim tenant',false,'patch','pvc','test-claim','-n','kura','--type=merge','-p',JSON.generate({'metadata'=>{'labels'=>{'app.kubernetes.io/instance'=>'tenant-b'}}}))
  check.call('select foreign node',false,'patch','pvc','test-claim','-n','kura','--type=merge','-p',JSON.generate({'metadata'=>{'annotations'=>{'volume.kubernetes.io/selected-node'=>'other-node'}}}))
  check.call('release own selection',true,'patch','pvc','test-claim','-n','kura','--type=merge','-p',JSON.generate({'metadata'=>{'annotations'=>{'volume.kubernetes.io/selected-node'=>nil}}}))
  check.call('publish own capacity',true,'patch','node',node,'--subresource=status','--type=merge','-p',JSON.generate({'status'=>{'capacity'=>{'tuist.dev/kura-disk'=>'1234'}}}))
  check.call('publish foreign node capacity',false,'patch','node','other-node','--subresource=status','--type=merge','-p',JSON.generate({'status'=>{'capacity'=>{'tuist.dev/kura-disk'=>'1234'}}}))
  check.call('change CPU capacity',false,'patch','node',node,'--subresource=status','--type=merge','-p',JSON.generate({'status'=>{'capacity'=>{'cpu'=>'999'}}}))
  check.call('change readiness',false,'patch','node',node,'--subresource=status','--type=merge','-p',JSON.generate({'status'=>{'conditions'=>[{'type'=>'Ready','status'=>'False'}]}}))
  check.call('remove own capacity',true,'patch','node',node,'--subresource=status','--type=merge','-p',JSON.generate({'status'=>{'capacity'=>{'tuist.dev/kura-disk'=>nil}}}))
  check.call('delete own PV',true,'delete','pv',pv['metadata']['name'],'--wait=false')
  puts JSON.pretty_generate(results)
ensure
  file.unlink
end
