# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'date'
require 'google/apis/core/base_service'
require 'google/apis/core/json_representation'
require 'google/apis/core/hashable'
require 'google/apis/errors'

module Google
  module Apis
    module StorageV1
      
      class Bucket
        class Representation < Google::Apis::Core::JsonRepresentation; end
        
        class Autoclass
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class Billing
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class CorsConfiguration
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class CustomPlacementConfig
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class Encryption
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class IamConfiguration
          class Representation < Google::Apis::Core::JsonRepresentation; end
          
          class BucketPolicyOnly
            class Representation < Google::Apis::Core::JsonRepresentation; end
          
            include Google::Apis::Core::JsonObjectSupport
          end
          
          class UniformBucketLevelAccess
            class Representation < Google::Apis::Core::JsonRepresentation; end
          
            include Google::Apis::Core::JsonObjectSupport
          end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class Lifecycle
          class Representation < Google::Apis::Core::JsonRepresentation; end
          
          class Rule
            class Representation < Google::Apis::Core::JsonRepresentation; end
            
            class Action
              class Representation < Google::Apis::Core::JsonRepresentation; end
            
              include Google::Apis::Core::JsonObjectSupport
            end
            
            class Condition
              class Representation < Google::Apis::Core::JsonRepresentation; end
            
              include Google::Apis::Core::JsonObjectSupport
            end
          
            include Google::Apis::Core::JsonObjectSupport
          end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class Logging
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class Owner
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class RetentionPolicy
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class Versioning
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class Website
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class BucketAccessControl
        class Representation < Google::Apis::Core::JsonRepresentation; end
        
        class ProjectTeam
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class BucketAccessControls
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class Buckets
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class Channel
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class ComposeRequest
        class Representation < Google::Apis::Core::JsonRepresentation; end
        
        class SourceObject
          class Representation < Google::Apis::Core::JsonRepresentation; end
          
          class ObjectPreconditions
            class Representation < Google::Apis::Core::JsonRepresentation; end
          
            include Google::Apis::Core::JsonObjectSupport
          end
        
          include Google::Apis::Core::JsonObjectSupport
        end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class Expr
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class HmacKey
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class HmacKeyMetadata
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class HmacKeysMetadata
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class Notification
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class Notifications
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class Object
        class Representation < Google::Apis::Core::JsonRepresentation; end
        
        class CustomerEncryption
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
        
        class Owner
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class ObjectAccessControl
        class Representation < Google::Apis::Core::JsonRepresentation; end
        
        class ProjectTeam
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class ObjectAccessControls
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class Objects
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class Policy
        class Representation < Google::Apis::Core::JsonRepresentation; end
        
        class Binding
          class Representation < Google::Apis::Core::JsonRepresentation; end
        
          include Google::Apis::Core::JsonObjectSupport
        end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class RewriteResponse
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class ServiceAccount
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class TestIamPermissionsResponse
        class Representation < Google::Apis::Core::JsonRepresentation; end
      
        include Google::Apis::Core::JsonObjectSupport
      end
      
      class Bucket
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          collection :acl, as: 'acl', class: Google::Apis::StorageV1::BucketAccessControl, decorator: Google::Apis::StorageV1::BucketAccessControl::Representation
      
          property :autoclass, as: 'autoclass', class: Google::Apis::StorageV1::Bucket::Autoclass, decorator: Google::Apis::StorageV1::Bucket::Autoclass::Representation
      
          property :billing, as: 'billing', class: Google::Apis::StorageV1::Bucket::Billing, decorator: Google::Apis::StorageV1::Bucket::Billing::Representation
      
          collection :cors_configurations, as: 'cors', class: Google::Apis::StorageV1::Bucket::CorsConfiguration, decorator: Google::Apis::StorageV1::Bucket::CorsConfiguration::Representation
      
          property :custom_placement_config, as: 'customPlacementConfig', class: Google::Apis::StorageV1::Bucket::CustomPlacementConfig, decorator: Google::Apis::StorageV1::Bucket::CustomPlacementConfig::Representation
      
          property :default_event_based_hold, as: 'defaultEventBasedHold'
          collection :default_object_acl, as: 'defaultObjectAcl', class: Google::Apis::StorageV1::ObjectAccessControl, decorator: Google::Apis::StorageV1::ObjectAccessControl::Representation
      
          property :encryption, as: 'encryption', class: Google::Apis::StorageV1::Bucket::Encryption, decorator: Google::Apis::StorageV1::Bucket::Encryption::Representation
      
          property :etag, as: 'etag'
          property :iam_configuration, as: 'iamConfiguration', class: Google::Apis::StorageV1::Bucket::IamConfiguration, decorator: Google::Apis::StorageV1::Bucket::IamConfiguration::Representation
      
          property :id, as: 'id'
          property :kind, as: 'kind'
          hash :labels, as: 'labels'
          property :lifecycle, as: 'lifecycle', class: Google::Apis::StorageV1::Bucket::Lifecycle, decorator: Google::Apis::StorageV1::Bucket::Lifecycle::Representation
      
          property :location, as: 'location'
          property :location_type, as: 'locationType'
          property :logging, as: 'logging', class: Google::Apis::StorageV1::Bucket::Logging, decorator: Google::Apis::StorageV1::Bucket::Logging::Representation
      
          property :metageneration, :numeric_string => true, as: 'metageneration'
          property :name, as: 'name'
          property :owner, as: 'owner', class: Google::Apis::StorageV1::Bucket::Owner, decorator: Google::Apis::StorageV1::Bucket::Owner::Representation
      
          property :project_number, :numeric_string => true, as: 'projectNumber'
          property :retention_policy, as: 'retentionPolicy', class: Google::Apis::StorageV1::Bucket::RetentionPolicy, decorator: Google::Apis::StorageV1::Bucket::RetentionPolicy::Representation
      
          property :rpo, as: 'rpo'
          property :satisfies_pzs, as: 'satisfiesPZS'
          property :self_link, as: 'selfLink'
          property :storage_class, as: 'storageClass'
          property :time_created, as: 'timeCreated', type: DateTime
      
          property :updated, as: 'updated', type: DateTime
      
          property :versioning, as: 'versioning', class: Google::Apis::StorageV1::Bucket::Versioning, decorator: Google::Apis::StorageV1::Bucket::Versioning::Representation
      
          property :website, as: 'website', class: Google::Apis::StorageV1::Bucket::Website, decorator: Google::Apis::StorageV1::Bucket::Website::Representation
      
        end
        
        class Autoclass
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :enabled, as: 'enabled'
            property :toggle_time, as: 'toggleTime', type: DateTime
        
          end
        end
        
        class Billing
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :requester_pays, as: 'requesterPays'
          end
        end
        
        class CorsConfiguration
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :max_age_seconds, as: 'maxAgeSeconds'
            collection :http_method, as: 'method'
            collection :origin, as: 'origin'
            collection :response_header, as: 'responseHeader'
          end
        end
        
        class CustomPlacementConfig
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            collection :data_locations, as: 'dataLocations'
          end
        end
        
        class Encryption
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :default_kms_key_name, as: 'defaultKmsKeyName'
          end
        end
        
        class IamConfiguration
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :bucket_policy_only, as: 'bucketPolicyOnly', class: Google::Apis::StorageV1::Bucket::IamConfiguration::BucketPolicyOnly, decorator: Google::Apis::StorageV1::Bucket::IamConfiguration::BucketPolicyOnly::Representation
        
            property :public_access_prevention, as: 'publicAccessPrevention'
            property :uniform_bucket_level_access, as: 'uniformBucketLevelAccess', class: Google::Apis::StorageV1::Bucket::IamConfiguration::UniformBucketLevelAccess, decorator: Google::Apis::StorageV1::Bucket::IamConfiguration::UniformBucketLevelAccess::Representation
        
          end
          
          class BucketPolicyOnly
            # @private
            class Representation < Google::Apis::Core::JsonRepresentation
              property :enabled, as: 'enabled'
              property :locked_time, as: 'lockedTime', type: DateTime
          
            end
          end
          
          class UniformBucketLevelAccess
            # @private
            class Representation < Google::Apis::Core::JsonRepresentation
              property :enabled, as: 'enabled'
              property :locked_time, as: 'lockedTime', type: DateTime
          
            end
          end
        end
        
        class Lifecycle
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            collection :rule, as: 'rule', class: Google::Apis::StorageV1::Bucket::Lifecycle::Rule, decorator: Google::Apis::StorageV1::Bucket::Lifecycle::Rule::Representation
        
          end
          
          class Rule
            # @private
            class Representation < Google::Apis::Core::JsonRepresentation
              property :action, as: 'action', class: Google::Apis::StorageV1::Bucket::Lifecycle::Rule::Action, decorator: Google::Apis::StorageV1::Bucket::Lifecycle::Rule::Action::Representation
          
              property :condition, as: 'condition', class: Google::Apis::StorageV1::Bucket::Lifecycle::Rule::Condition, decorator: Google::Apis::StorageV1::Bucket::Lifecycle::Rule::Condition::Representation
          
            end
            
            class Action
              # @private
              class Representation < Google::Apis::Core::JsonRepresentation
                property :storage_class, as: 'storageClass'
                property :type, as: 'type'
              end
            end
            
            class Condition
              # @private
              class Representation < Google::Apis::Core::JsonRepresentation
                property :age, as: 'age'
                property :created_before, as: 'createdBefore', type: Date
            
                property :custom_time_before, as: 'customTimeBefore', type: Date
            
                property :days_since_custom_time, as: 'daysSinceCustomTime'
                property :days_since_noncurrent_time, as: 'daysSinceNoncurrentTime'
                property :is_live, as: 'isLive'
                property :matches_pattern, as: 'matchesPattern'
                collection :matches_storage_class, as: 'matchesStorageClass'
                property :noncurrent_time_before, as: 'noncurrentTimeBefore', type: Date
            
                property :num_newer_versions, as: 'numNewerVersions'
              end
            end
          end
        end
        
        class Logging
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :log_bucket, as: 'logBucket'
            property :log_object_prefix, as: 'logObjectPrefix'
          end
        end
        
        class Owner
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :entity, as: 'entity'
            property :entity_id, as: 'entityId'
          end
        end
        
        class RetentionPolicy
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :effective_time, as: 'effectiveTime', type: DateTime
        
            property :is_locked, as: 'isLocked'
            property :retention_period, :numeric_string => true, as: 'retentionPeriod'
          end
        end
        
        class Versioning
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :enabled, as: 'enabled'
          end
        end
        
        class Website
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :main_page_suffix, as: 'mainPageSuffix'
            property :not_found_page, as: 'notFoundPage'
          end
        end
      end
      
      class BucketAccessControl
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :bucket, as: 'bucket'
          property :domain, as: 'domain'
          property :email, as: 'email'
          property :entity, as: 'entity'
          property :entity_id, as: 'entityId'
          property :etag, as: 'etag'
          property :id, as: 'id'
          property :kind, as: 'kind'
          property :project_team, as: 'projectTeam', class: Google::Apis::StorageV1::BucketAccessControl::ProjectTeam, decorator: Google::Apis::StorageV1::BucketAccessControl::ProjectTeam::Representation
      
          property :role, as: 'role'
          property :self_link, as: 'selfLink'
        end
        
        class ProjectTeam
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :project_number, as: 'projectNumber'
            property :team, as: 'team'
          end
        end
      end
      
      class BucketAccessControls
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          collection :items, as: 'items', class: Google::Apis::StorageV1::BucketAccessControl, decorator: Google::Apis::StorageV1::BucketAccessControl::Representation
      
          property :kind, as: 'kind'
        end
      end
      
      class Buckets
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          collection :items, as: 'items', class: Google::Apis::StorageV1::Bucket, decorator: Google::Apis::StorageV1::Bucket::Representation
      
          property :kind, as: 'kind'
          property :next_page_token, as: 'nextPageToken'
        end
      end
      
      class Channel
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :address, as: 'address'
          property :expiration, :numeric_string => true, as: 'expiration'
          property :id, as: 'id'
          property :kind, as: 'kind'
          hash :params, as: 'params'
          property :payload, as: 'payload'
          property :resource_id, as: 'resourceId'
          property :resource_uri, as: 'resourceUri'
          property :token, as: 'token'
          property :type, as: 'type'
        end
      end
      
      class ComposeRequest
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :destination, as: 'destination', class: Google::Apis::StorageV1::Object, decorator: Google::Apis::StorageV1::Object::Representation
      
          property :kind, as: 'kind'
          collection :source_objects, as: 'sourceObjects', class: Google::Apis::StorageV1::ComposeRequest::SourceObject, decorator: Google::Apis::StorageV1::ComposeRequest::SourceObject::Representation
      
        end
        
        class SourceObject
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :generation, :numeric_string => true, as: 'generation'
            property :name, as: 'name'
            property :object_preconditions, as: 'objectPreconditions', class: Google::Apis::StorageV1::ComposeRequest::SourceObject::ObjectPreconditions, decorator: Google::Apis::StorageV1::ComposeRequest::SourceObject::ObjectPreconditions::Representation
        
          end
          
          class ObjectPreconditions
            # @private
            class Representation < Google::Apis::Core::JsonRepresentation
              property :if_generation_match, :numeric_string => true, as: 'ifGenerationMatch'
            end
          end
        end
      end
      
      class Expr
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :description, as: 'description'
          property :expression, as: 'expression'
          property :location, as: 'location'
          property :title, as: 'title'
        end
      end
      
      class HmacKey
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :kind, as: 'kind'
          property :metadata, as: 'metadata', class: Google::Apis::StorageV1::HmacKeyMetadata, decorator: Google::Apis::StorageV1::HmacKeyMetadata::Representation
      
          property :secret, as: 'secret'
        end
      end
      
      class HmacKeyMetadata
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :access_id, as: 'accessId'
          property :etag, as: 'etag'
          property :id, as: 'id'
          property :kind, as: 'kind'
          property :project_id, as: 'projectId'
          property :self_link, as: 'selfLink'
          property :service_account_email, as: 'serviceAccountEmail'
          property :state, as: 'state'
          property :time_created, as: 'timeCreated', type: DateTime
      
          property :updated, as: 'updated', type: DateTime
      
        end
      end
      
      class HmacKeysMetadata
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          collection :items, as: 'items', class: Google::Apis::StorageV1::HmacKeyMetadata, decorator: Google::Apis::StorageV1::HmacKeyMetadata::Representation
      
          property :kind, as: 'kind'
          property :next_page_token, as: 'nextPageToken'
        end
      end
      
      class Notification
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          hash :custom_attributes, as: 'custom_attributes'
          property :etag, as: 'etag'
          collection :event_types, as: 'event_types'
          property :id, as: 'id'
          property :kind, as: 'kind'
          property :object_name_prefix, as: 'object_name_prefix'
          property :payload_format, as: 'payload_format'
          property :self_link, as: 'selfLink'
          property :topic, as: 'topic'
        end
      end
      
      class Notifications
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          collection :items, as: 'items', class: Google::Apis::StorageV1::Notification, decorator: Google::Apis::StorageV1::Notification::Representation
      
          property :kind, as: 'kind'
        end
      end
      
      class Object
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          collection :acl, as: 'acl', class: Google::Apis::StorageV1::ObjectAccessControl, decorator: Google::Apis::StorageV1::ObjectAccessControl::Representation
      
          property :bucket, as: 'bucket'
          property :cache_control, as: 'cacheControl'
          property :component_count, as: 'componentCount'
          property :content_disposition, as: 'contentDisposition'
          property :content_encoding, as: 'contentEncoding'
          property :content_language, as: 'contentLanguage'
          property :content_type, as: 'contentType'
          property :crc32c, as: 'crc32c'
          property :custom_time, as: 'customTime', type: DateTime
      
          property :customer_encryption, as: 'customerEncryption', class: Google::Apis::StorageV1::Object::CustomerEncryption, decorator: Google::Apis::StorageV1::Object::CustomerEncryption::Representation
      
          property :etag, as: 'etag'
          property :event_based_hold, as: 'eventBasedHold'
          property :generation, :numeric_string => true, as: 'generation'
          property :id, as: 'id'
          property :kind, as: 'kind'
          property :kms_key_name, as: 'kmsKeyName'
          property :md5_hash, as: 'md5Hash'
          property :media_link, as: 'mediaLink'
          hash :metadata, as: 'metadata'
          property :metageneration, :numeric_string => true, as: 'metageneration'
          property :name, as: 'name'
          property :owner, as: 'owner', class: Google::Apis::StorageV1::Object::Owner, decorator: Google::Apis::StorageV1::Object::Owner::Representation
      
          property :retention_expiration_time, as: 'retentionExpirationTime', type: DateTime
      
          property :self_link, as: 'selfLink'
          property :size, :numeric_string => true, as: 'size'
          property :storage_class, as: 'storageClass'
          property :temporary_hold, as: 'temporaryHold'
          property :time_created, as: 'timeCreated', type: DateTime
      
          property :time_deleted, as: 'timeDeleted', type: DateTime
      
          property :time_storage_class_updated, as: 'timeStorageClassUpdated', type: DateTime
      
          property :updated, as: 'updated', type: DateTime
      
        end
        
        class CustomerEncryption
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :encryption_algorithm, as: 'encryptionAlgorithm'
            property :key_sha256, as: 'keySha256'
          end
        end
        
        class Owner
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :entity, as: 'entity'
            property :entity_id, as: 'entityId'
          end
        end
      end
      
      class ObjectAccessControl
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :bucket, as: 'bucket'
          property :domain, as: 'domain'
          property :email, as: 'email'
          property :entity, as: 'entity'
          property :entity_id, as: 'entityId'
          property :etag, as: 'etag'
          property :generation, :numeric_string => true, as: 'generation'
          property :id, as: 'id'
          property :kind, as: 'kind'
          property :object, as: 'object'
          property :project_team, as: 'projectTeam', class: Google::Apis::StorageV1::ObjectAccessControl::ProjectTeam, decorator: Google::Apis::StorageV1::ObjectAccessControl::ProjectTeam::Representation
      
          property :role, as: 'role'
          property :self_link, as: 'selfLink'
        end
        
        class ProjectTeam
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :project_number, as: 'projectNumber'
            property :team, as: 'team'
          end
        end
      end
      
      class ObjectAccessControls
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          collection :items, as: 'items', class: Google::Apis::StorageV1::ObjectAccessControl, decorator: Google::Apis::StorageV1::ObjectAccessControl::Representation
      
          property :kind, as: 'kind'
        end
      end
      
      class Objects
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          collection :items, as: 'items', class: Google::Apis::StorageV1::Object, decorator: Google::Apis::StorageV1::Object::Representation
      
          property :kind, as: 'kind'
          property :next_page_token, as: 'nextPageToken'
          collection :prefixes, as: 'prefixes'
        end
      end
      
      class Policy
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          collection :bindings, as: 'bindings', class: Google::Apis::StorageV1::Policy::Binding, decorator: Google::Apis::StorageV1::Policy::Binding::Representation
      
          property :etag, :base64 => true, as: 'etag'
          property :kind, as: 'kind'
          property :resource_id, as: 'resourceId'
          property :version, as: 'version'
        end
        
        class Binding
          # @private
          class Representation < Google::Apis::Core::JsonRepresentation
            property :condition, as: 'condition', class: Google::Apis::StorageV1::Expr, decorator: Google::Apis::StorageV1::Expr::Representation
        
            collection :members, as: 'members'
            property :role, as: 'role'
          end
        end
      end
      
      class RewriteResponse
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :done, as: 'done'
          property :kind, as: 'kind'
          property :object_size, :numeric_string => true, as: 'objectSize'
          property :resource, as: 'resource', class: Google::Apis::StorageV1::Object, decorator: Google::Apis::StorageV1::Object::Representation
      
          property :rewrite_token, as: 'rewriteToken'
          property :total_bytes_rewritten, :numeric_string => true, as: 'totalBytesRewritten'
        end
      end
      
      class ServiceAccount
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :email_address, as: 'email_address'
          property :kind, as: 'kind'
        end
      end
      
      class TestIamPermissionsResponse
        # @private
        class Representation < Google::Apis::Core::JsonRepresentation
          property :kind, as: 'kind'
          collection :permissions, as: 'permissions'
        end
      end
    end
  end
end
