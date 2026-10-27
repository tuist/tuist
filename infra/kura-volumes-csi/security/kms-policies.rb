# Generate reviewable AWS policies from explicit, non-secret environment data.
# This script prints JSON only; it makes no cloud changes.
require 'json'
account=ENV.fetch('KURA_AWS_ACCOUNT_ID')
region=ENV.fetch('KURA_AWS_REGION')
issuer=ENV.fetch('KURA_OIDC_ISSUER').sub(%r{\Ahttps://},'').sub(%r{/\z},'')
namespace=ENV.fetch('KURA_SERVER_NAMESPACE')
role=ENV.fetch('KURA_KMS_ROLE_NAME')
admin=ENV.fetch('KURA_KMS_ADMIN_ROLE_ARN')
raise 'invalid account' unless account.match?(/\A[0-9]{12}\z/)
raise 'invalid region' unless region.match?(/\A[a-z]{2}-[a-z]+-[0-9]\z/)
raise 'issuer must be a public HTTPS issuer' unless ENV.fetch('KURA_OIDC_ISSUER').start_with?('https://') && issuer.match?(/\A[a-zA-Z0-9.-]+(?:\/[a-zA-Z0-9._\/-]+)?\z/)
raise 'invalid role or namespace' unless role.match?(/\A[A-Za-z0-9+=,.@_-]+\z/) && namespace.match?(/\A[a-z0-9-]+\z/)
raise 'admin must be a separate IAM role in the account' unless admin.start_with?("arn:aws:iam::#{account}:role/") && admin != "arn:aws:iam::#{account}:role/#{role}"
trust={Version:'2012-10-17',Statement:[{Effect:'Allow',Principal:{Federated:"arn:aws:iam::#{account}:oidc-provider/#{issuer}"},Action:'sts:AssumeRoleWithWebIdentity',Condition:{StringEquals:{"#{issuer}:aud"=>'sts.amazonaws.com',"#{issuer}:sub"=>"system:serviceaccount:#{namespace}:tuist-server"}}}]}
key_policy={Version:'2012-10-17',Statement:[
 {Sid:'SeparateKeyAdministration',Effect:'Allow',Principal:{AWS:admin},Action:%w(kms:Create* kms:Describe* kms:Enable* kms:List* kms:Put* kms:Update* kms:Revoke* kms:Disable* kms:Get* kms:Delete* kms:TagResource kms:UntagResource kms:ScheduleKeyDeletion kms:CancelKeyDeletion kms:RotateKeyOnDemand),Resource:'*'},
 {Sid:'WorkloadWrapAndUnwrapOnly',Effect:'Allow',Principal:{AWS:"arn:aws:iam::#{account}:role/#{role}"},Action:%w(kms:Encrypt kms:Decrypt),Resource:'*',Condition:{StringEquals:{'kms:EncryptionContext:purpose'=>'kura-volume-share'},Null:{'kms:EncryptionContext:aad'=>'false'}}}
]}
puts JSON.pretty_generate(region:region,role_name:role,trust_policy:trust,key_policy:key_policy,key_configuration:{KeySpec:'SYMMETRIC_DEFAULT',KeyUsage:'ENCRYPT_DECRYPT',Origin:'AWS_KMS',MultiRegion:false},rotation:{EnableKeyRotation:true,RotationPeriodInDays:90},deletion_policy:'Retain',required_audit:'Durable CloudTrail management events including kms.amazonaws.com; do not exclude KMS events')
