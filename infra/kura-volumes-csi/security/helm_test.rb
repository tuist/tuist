require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'
root=File.expand_path('../../helm/tuist', __dir__)
Dir.mktmpdir('kura-security-chart') do |chart|
  FileUtils.mkdir_p("#{chart}/templates")
  File.write("#{chart}/Chart.yaml", "apiVersion: v2\nname: tuist\nversion: 0.1.0\n")
  %w(values.yaml templates/_helpers.tpl templates/kura-volumes-csi.yaml templates/kura-volumes-csi-admission.yaml templates/server-deployment.yaml templates/server-config-external-secrets.yaml).each { |p| FileUtils.cp("#{root}/#{p}", "#{chart}/#{p}") }
  args=['helm','template','tuist',chart,'--set','server.license.key=render-test-only','--set','server.config.managedSecrets=true','--set','server.hosted=true','--set','server.image.tag=test','--set','kuraFleet.enabled=true','--set','kuraVolumesCSI.enabled=true','--set','kuraVolumesCSI.image.tag=test','--set','server.managedSecrets=true','--set','server.config.kuraVolumeOpenBao.enabled=true','--set','server.config.kuraVolumeOpenBao.address=https://openbao.example.test:8200','--set','server.config.kuraVolumeOpenBao.role=kura-test']
  out,err,status=Open3.capture3(*args); raise err unless status.success?
  docs=YAML.load_stream(out).compact
  server=docs.find { |d| d['kind']=='Deployment' }
  pod=server.dig('spec','template','spec')
  identity=pod['volumes'].find { |v| v['name']=='kura-openbao-identity' }
  raise 'missing bounded OpenBao token' unless identity.dig('projected','sources',0,'serviceAccountToken') == {'audience'=>'openbao.kura.tuist.dev','expirationSeconds'=>3600,'path'=>'token'}
  raise 'missing OpenBao mount' unless pod['containers'][0]['volumeMounts'].any? { |v| v['name']=='kura-openbao-identity' && v['readOnly'] }
  raise 'exportable root still synced' if out.include?('TUIST_KURA_VOLUME_ROOT_KEYS')
  raise 'missing fail-closed policies' unless docs.count { |d| d['kind']=='ValidatingAdmissionPolicy' && d.dig('spec','failurePolicy')=='Fail' } == 3
  cluster_role=docs.find { |d| d['kind']=='ClusterRole' && d.dig('metadata','name')=='kura-volumes-csi-node' }
  raise 'cluster-wide PVC writes' if cluster_role['rules'].any? { |r| r['resources'].include?('persistentvolumeclaims') && (r['verbs'] & %w(update patch create delete)).any? }
  raise 'CSI Secret access' if cluster_role['rules'].any? { |r| (r['resources'] & %w(secrets *)).any? }
  namespaced=docs.find { |d| d['kind']=='Role' && d.dig('metadata','name')=='kura-volumes-csi-claims' }
  raise 'claim role not scoped to kura' unless namespaced.dig('metadata','namespace')=='kura'
  _,_,status=Open3.capture3(*args,'--set','server.config.kuraVolumeOpenBao.role=')
  raise 'accepted OpenBao without role' if status.success?
  out,err,status=Open3.capture3(*args,'--set','server.config.kuraVolumeOpenBao.caConfigMap=openbao-ca')
  raise err unless status.success?
  pod=YAML.load_stream(out).compact.find { |d| d['kind']=='Deployment' }.dig('spec','template','spec')
  identity=pod['volumes'].find { |v| v['name']=='kura-openbao-identity' }
  raise 'private CA not projected' unless identity.dig('projected','sources',1,'configMap') == {'name'=>'openbao-ca','items'=>[{'key'=>'ca.crt','path'=>'ca.crt'}]}
  ca=pod['containers'][0]['env'].find { |e| e['name']=='TUIST_KURA_VOLUME_OPENBAO_CA_CERT_FILE' }
  raise 'private CA not configured' unless ca['value']=='/var/run/tuist/kura-openbao/ca.crt'
  raise 'stale AWS KMS configuration' if out.include?('KURA_VOLUME_KMS_') || out.include?('sts.amazonaws.com')
  out,err,status=Open3.capture3(*args,'--set','server.config.kuraVolumeOpenBao.enabled=false')
  raise err unless status.success?
  raise 'disabled provider still mounts identity' if out.include?('kura-openbao-identity') || out.include?('TUIST_KURA_VOLUME_OPENBAO_')
  puts 'PASS: projected identity, private CA, disabled defaults, root removal, OpenBao fail-closed config, CSI admission and namespaced RBAC'

end
