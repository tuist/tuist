require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'
root=File.expand_path('../../helm/tuist', __dir__)
Dir.mktmpdir('kura-security-chart') do |chart|
  FileUtils.mkdir_p("#{chart}/templates")
  File.write("#{chart}/Chart.yaml", "apiVersion: v2\nname: tuist\nversion: 0.1.0\n")
  %w(values.yaml templates/_helpers.tpl templates/kura-volumes-csi.yaml templates/kura-volumes-csi-admission.yaml templates/server-deployment.yaml templates/server-config-external-secrets.yaml).each { |p| FileUtils.cp("#{root}/#{p}", "#{chart}/#{p}") }
  args=['helm','template','tuist',chart,'--set','server.license.key=render-test-only','--set','server.config.managedSecrets=true','--set','server.hosted=true','--set','server.image.tag=test','--set','kuraFleet.enabled=true','--set','kuraVolumesCSI.enabled=true','--set','kuraVolumesCSI.image.tag=test','--set','server.managedSecrets=true','--set','server.config.kuraVolumeKMS.enabled=true','--set','server.config.kuraVolumeKMS.keyArn=arn:aws:kms:eu-central-1:123456789012:key/11111111-1111-4111-8111-111111111111','--set','server.config.kuraVolumeKMS.roleArn=arn:aws:iam::123456789012:role/kura-test']
  out,err,status=Open3.capture3(*args); raise err unless status.success?
  docs=YAML.load_stream(out).compact
  server=docs.find { |d| d['kind']=='Deployment' }
  pod=server.dig('spec','template','spec')
  identity=pod['volumes'].find { |v| v['name']=='kura-kms-identity' }
  raise 'missing bounded STS token' unless identity.dig('projected','sources',0,'serviceAccountToken') == {'audience'=>'sts.amazonaws.com','expirationSeconds'=>3600,'path'=>'token'}
  raise 'missing KMS mount' unless pod['containers'][0]['volumeMounts'].any? { |v| v['name']=='kura-kms-identity' && v['readOnly'] }
  raise 'exportable root still synced' if out.include?('TUIST_KURA_VOLUME_ROOT_KEYS')
  raise 'missing fail-closed policies' unless docs.count { |d| d['kind']=='ValidatingAdmissionPolicy' && d.dig('spec','failurePolicy')=='Fail' } == 3
  cluster_role=docs.find { |d| d['kind']=='ClusterRole' && d.dig('metadata','name')=='kura-volumes-csi-node' }
  raise 'cluster-wide PVC writes' if cluster_role['rules'].any? { |r| r['resources'].include?('persistentvolumeclaims') && (r['verbs'] & %w(update patch create delete)).any? }
  raise 'CSI Secret access' if cluster_role['rules'].any? { |r| (r['resources'] & %w(secrets *)).any? }
  namespaced=docs.find { |d| d['kind']=='Role' && d.dig('metadata','name')=='kura-volumes-csi-claims' }
  raise 'claim role not scoped to kura' unless namespaced.dig('metadata','namespace')=='kura'
  _,_,status=Open3.capture3(*args,'--set','server.config.kuraVolumeKMS.roleArn=')
  raise 'accepted KMS without role' if status.success?
  puts 'PASS: projected identity, root removal, KMS fail-closed config, CSI admission and namespaced RBAC'
end
