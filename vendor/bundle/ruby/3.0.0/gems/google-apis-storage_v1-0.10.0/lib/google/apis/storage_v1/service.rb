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

require 'google/apis/core/base_service'
require 'google/apis/core/json_representation'
require 'google/apis/core/hashable'
require 'google/apis/errors'

module Google
  module Apis
    module StorageV1
      # Cloud Storage JSON API
      #
      # Stores and retrieves potentially large, immutable data objects.
      #
      # @example
      #    require 'google/apis/storage_v1'
      #
      #    Storage = Google::Apis::StorageV1 # Alias the module
      #    service = Storage::StorageService.new
      #
      # @see https://developers.google.com/storage/docs/json_api/
      class StorageService < Google::Apis::Core::BaseService
        # @return [String]
        #  API key. Your API key identifies your project and provides you with API access,
        #  quota, and reports. Required unless you provide an OAuth 2.0 token.
        attr_accessor :key

        # @return [String]
        #  An opaque string that represents a user for quota purposes. Must not exceed 40
        #  characters.
        attr_accessor :quota_user

        # @return [String]
        #  Deprecated. Please use quotaUser instead.
        attr_accessor :user_ip

        def initialize
          super('https://storage.googleapis.com/', 'storage/v1/',
                client_name: 'google-apis-storage_v1',
                client_version: Google::Apis::StorageV1::GEM_VERSION)
          @batch_path = 'batch/storage/v1'
        end
        
        # Permanently deletes the ACL entry for the specified entity on the specified
        # bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [NilClass] No result returned for this method
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [void]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def delete_bucket_access_control(bucket, entity, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:delete, 'b/{bucket}/acl/{entity}', options)
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Returns the ACL entry for the specified entity on the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::BucketAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::BucketAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_bucket_access_control(bucket, entity, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/acl/{entity}', options)
          command.response_representation = Google::Apis::StorageV1::BucketAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::BucketAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Creates a new ACL entry on the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Google::Apis::StorageV1::BucketAccessControl] bucket_access_control_object
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::BucketAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::BucketAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def insert_bucket_access_control(bucket, bucket_access_control_object = nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b/{bucket}/acl', options)
          command.request_representation = Google::Apis::StorageV1::BucketAccessControl::Representation
          command.request_object = bucket_access_control_object
          command.response_representation = Google::Apis::StorageV1::BucketAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::BucketAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Retrieves ACL entries on the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::BucketAccessControls] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::BucketAccessControls]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def list_bucket_access_controls(bucket, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/acl', options)
          command.response_representation = Google::Apis::StorageV1::BucketAccessControls::Representation
          command.response_class = Google::Apis::StorageV1::BucketAccessControls
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Patches an ACL entry on the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [Google::Apis::StorageV1::BucketAccessControl] bucket_access_control_object
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::BucketAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::BucketAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def patch_bucket_access_control(bucket, entity, bucket_access_control_object = nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:patch, 'b/{bucket}/acl/{entity}', options)
          command.request_representation = Google::Apis::StorageV1::BucketAccessControl::Representation
          command.request_object = bucket_access_control_object
          command.response_representation = Google::Apis::StorageV1::BucketAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::BucketAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Updates an ACL entry on the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [Google::Apis::StorageV1::BucketAccessControl] bucket_access_control_object
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::BucketAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::BucketAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def update_bucket_access_control(bucket, entity, bucket_access_control_object = nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:put, 'b/{bucket}/acl/{entity}', options)
          command.request_representation = Google::Apis::StorageV1::BucketAccessControl::Representation
          command.request_object = bucket_access_control_object
          command.response_representation = Google::Apis::StorageV1::BucketAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::BucketAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Permanently deletes an empty bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Fixnum] if_metageneration_match
        #   If set, only deletes the bucket if its metageneration matches this value.
        # @param [Fixnum] if_metageneration_not_match
        #   If set, only deletes the bucket if its metageneration does not match this
        #   value.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [NilClass] No result returned for this method
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [void]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def delete_bucket(bucket, if_metageneration_match: nil, if_metageneration_not_match: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:delete, 'b/{bucket}', options)
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Returns metadata for the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Fixnum] if_metageneration_match
        #   Makes the return of the bucket metadata conditional on whether the bucket's
        #   current metageneration matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the return of the bucket metadata conditional on whether the bucket's
        #   current metageneration does not match the given value.
        # @param [String] projection
        #   Set of properties to return. Defaults to noAcl.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Bucket] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Bucket]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_bucket(bucket, if_metageneration_match: nil, if_metageneration_not_match: nil, projection: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}', options)
          command.response_representation = Google::Apis::StorageV1::Bucket::Representation
          command.response_class = Google::Apis::StorageV1::Bucket
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Returns an IAM policy for the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Fixnum] options_requested_policy_version
        #   The IAM policy format version to be returned. If the
        #   optionsRequestedPolicyVersion is for an older version that doesn't support
        #   part of the requested IAM policy, the request fails.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Policy] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Policy]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_bucket_iam_policy(bucket, options_requested_policy_version: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/iam', options)
          command.response_representation = Google::Apis::StorageV1::Policy::Representation
          command.response_class = Google::Apis::StorageV1::Policy
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['optionsRequestedPolicyVersion'] = options_requested_policy_version unless options_requested_policy_version.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Creates a new bucket.
        # @param [String] project
        #   A valid API project identifier.
        # @param [Google::Apis::StorageV1::Bucket] bucket_object
        # @param [String] predefined_acl
        #   Apply a predefined set of access controls to this bucket.
        # @param [String] predefined_default_object_acl
        #   Apply a predefined set of default object access controls to this bucket.
        # @param [String] projection
        #   Set of properties to return. Defaults to noAcl, unless the bucket resource
        #   specifies acl or defaultObjectAcl properties, when it defaults to full.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Bucket] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Bucket]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def insert_bucket(project, bucket_object = nil, predefined_acl: nil, predefined_default_object_acl: nil, projection: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b', options)
          command.request_representation = Google::Apis::StorageV1::Bucket::Representation
          command.request_object = bucket_object
          command.response_representation = Google::Apis::StorageV1::Bucket::Representation
          command.response_class = Google::Apis::StorageV1::Bucket
          command.query['predefinedAcl'] = predefined_acl unless predefined_acl.nil?
          command.query['predefinedDefaultObjectAcl'] = predefined_default_object_acl unless predefined_default_object_acl.nil?
          command.query['project'] = project unless project.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Retrieves a list of buckets for a given project.
        # @param [String] project
        #   A valid API project identifier.
        # @param [Fixnum] max_results
        #   Maximum number of buckets to return in a single response. The service will use
        #   this parameter or 1,000 items, whichever is smaller.
        # @param [String] page_token
        #   A previously-returned page token representing part of the larger set of
        #   results to view.
        # @param [String] prefix
        #   Filter results to buckets whose names begin with this prefix.
        # @param [String] projection
        #   Set of properties to return. Defaults to noAcl.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Buckets] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Buckets]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def list_buckets(project, max_results: nil, page_token: nil, prefix: nil, projection: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b', options)
          command.response_representation = Google::Apis::StorageV1::Buckets::Representation
          command.response_class = Google::Apis::StorageV1::Buckets
          command.query['maxResults'] = max_results unless max_results.nil?
          command.query['pageToken'] = page_token unless page_token.nil?
          command.query['prefix'] = prefix unless prefix.nil?
          command.query['project'] = project unless project.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Locks retention policy on a bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Fixnum] if_metageneration_match
        #   Makes the operation conditional on whether bucket's current metageneration
        #   matches the given value.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Bucket] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Bucket]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def lock_bucket_retention_policy(bucket, if_metageneration_match, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b/{bucket}/lockRetentionPolicy', options)
          command.response_representation = Google::Apis::StorageV1::Bucket::Representation
          command.response_class = Google::Apis::StorageV1::Bucket
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Patches a bucket. Changes to the bucket will be readable immediately after
        # writing, but configuration changes may take time to propagate.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Google::Apis::StorageV1::Bucket] bucket_object
        # @param [Fixnum] if_metageneration_match
        #   Makes the return of the bucket metadata conditional on whether the bucket's
        #   current metageneration matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the return of the bucket metadata conditional on whether the bucket's
        #   current metageneration does not match the given value.
        # @param [String] predefined_acl
        #   Apply a predefined set of access controls to this bucket.
        # @param [String] predefined_default_object_acl
        #   Apply a predefined set of default object access controls to this bucket.
        # @param [String] projection
        #   Set of properties to return. Defaults to full.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Bucket] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Bucket]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def patch_bucket(bucket, bucket_object = nil, if_metageneration_match: nil, if_metageneration_not_match: nil, predefined_acl: nil, predefined_default_object_acl: nil, projection: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:patch, 'b/{bucket}', options)
          command.request_representation = Google::Apis::StorageV1::Bucket::Representation
          command.request_object = bucket_object
          command.response_representation = Google::Apis::StorageV1::Bucket::Representation
          command.response_class = Google::Apis::StorageV1::Bucket
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['predefinedAcl'] = predefined_acl unless predefined_acl.nil?
          command.query['predefinedDefaultObjectAcl'] = predefined_default_object_acl unless predefined_default_object_acl.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Updates an IAM policy for the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Google::Apis::StorageV1::Policy] policy_object
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Policy] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Policy]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def set_bucket_iam_policy(bucket, policy_object = nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:put, 'b/{bucket}/iam', options)
          command.request_representation = Google::Apis::StorageV1::Policy::Representation
          command.request_object = policy_object
          command.response_representation = Google::Apis::StorageV1::Policy::Representation
          command.response_class = Google::Apis::StorageV1::Policy
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Tests a set of permissions on the given bucket to see which, if any, are held
        # by the caller.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Array<String>, String] permissions
        #   Permissions to test.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::TestIamPermissionsResponse] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::TestIamPermissionsResponse]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def test_bucket_iam_permissions(bucket, permissions, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/iam/testPermissions', options)
          command.response_representation = Google::Apis::StorageV1::TestIamPermissionsResponse::Representation
          command.response_class = Google::Apis::StorageV1::TestIamPermissionsResponse
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['permissions'] = permissions unless permissions.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Updates a bucket. Changes to the bucket will be readable immediately after
        # writing, but configuration changes may take time to propagate.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Google::Apis::StorageV1::Bucket] bucket_object
        # @param [Fixnum] if_metageneration_match
        #   Makes the return of the bucket metadata conditional on whether the bucket's
        #   current metageneration matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the return of the bucket metadata conditional on whether the bucket's
        #   current metageneration does not match the given value.
        # @param [String] predefined_acl
        #   Apply a predefined set of access controls to this bucket.
        # @param [String] predefined_default_object_acl
        #   Apply a predefined set of default object access controls to this bucket.
        # @param [String] projection
        #   Set of properties to return. Defaults to full.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Bucket] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Bucket]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def update_bucket(bucket, bucket_object = nil, if_metageneration_match: nil, if_metageneration_not_match: nil, predefined_acl: nil, predefined_default_object_acl: nil, projection: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:put, 'b/{bucket}', options)
          command.request_representation = Google::Apis::StorageV1::Bucket::Representation
          command.request_object = bucket_object
          command.response_representation = Google::Apis::StorageV1::Bucket::Representation
          command.response_class = Google::Apis::StorageV1::Bucket
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['predefinedAcl'] = predefined_acl unless predefined_acl.nil?
          command.query['predefinedDefaultObjectAcl'] = predefined_default_object_acl unless predefined_default_object_acl.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Stop watching resources through this channel
        # @param [Google::Apis::StorageV1::Channel] channel_object
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [NilClass] No result returned for this method
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [void]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def stop_channel(channel_object = nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'channels/stop', options)
          command.request_representation = Google::Apis::StorageV1::Channel::Representation
          command.request_object = channel_object
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Permanently deletes the default object ACL entry for the specified entity on
        # the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [NilClass] No result returned for this method
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [void]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def delete_default_object_access_control(bucket, entity, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:delete, 'b/{bucket}/defaultObjectAcl/{entity}', options)
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Returns the default object ACL entry for the specified entity on the specified
        # bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_default_object_access_control(bucket, entity, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/defaultObjectAcl/{entity}', options)
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Creates a new default object ACL entry on the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Google::Apis::StorageV1::ObjectAccessControl] object_access_control_object
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def insert_default_object_access_control(bucket, object_access_control_object = nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b/{bucket}/defaultObjectAcl', options)
          command.request_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.request_object = object_access_control_object
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Retrieves default object ACL entries on the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [Fixnum] if_metageneration_match
        #   If present, only return default ACL listing if the bucket's current
        #   metageneration matches this value.
        # @param [Fixnum] if_metageneration_not_match
        #   If present, only return default ACL listing if the bucket's current
        #   metageneration does not match the given value.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControls] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControls]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def list_default_object_access_controls(bucket, if_metageneration_match: nil, if_metageneration_not_match: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/defaultObjectAcl', options)
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControls::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControls
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Patches a default object ACL entry on the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [Google::Apis::StorageV1::ObjectAccessControl] object_access_control_object
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def patch_default_object_access_control(bucket, entity, object_access_control_object = nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:patch, 'b/{bucket}/defaultObjectAcl/{entity}', options)
          command.request_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.request_object = object_access_control_object
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Updates a default object ACL entry on the specified bucket.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [Google::Apis::StorageV1::ObjectAccessControl] object_access_control_object
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def update_default_object_access_control(bucket, entity, object_access_control_object = nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:put, 'b/{bucket}/defaultObjectAcl/{entity}', options)
          command.request_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.request_object = object_access_control_object
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Permanently deletes a notification subscription.
        # @param [String] bucket
        #   The parent bucket of the notification.
        # @param [String] notification
        #   ID of the notification to delete.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [NilClass] No result returned for this method
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [void]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def delete_notification(bucket, notification, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:delete, 'b/{bucket}/notificationConfigs/{notification}', options)
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['notification'] = notification unless notification.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # View a notification configuration.
        # @param [String] bucket
        #   The parent bucket of the notification.
        # @param [String] notification
        #   Notification ID
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Notification] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Notification]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_notification(bucket, notification, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/notificationConfigs/{notification}', options)
          command.response_representation = Google::Apis::StorageV1::Notification::Representation
          command.response_class = Google::Apis::StorageV1::Notification
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['notification'] = notification unless notification.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Creates a notification subscription for a given bucket.
        # @param [String] bucket
        #   The parent bucket of the notification.
        # @param [Google::Apis::StorageV1::Notification] notification_object
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Notification] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Notification]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def insert_notification(bucket, notification_object = nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b/{bucket}/notificationConfigs', options)
          command.request_representation = Google::Apis::StorageV1::Notification::Representation
          command.request_object = notification_object
          command.response_representation = Google::Apis::StorageV1::Notification::Representation
          command.response_class = Google::Apis::StorageV1::Notification
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Retrieves a list of notification subscriptions for a given bucket.
        # @param [String] bucket
        #   Name of a Google Cloud Storage bucket.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Notifications] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Notifications]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def list_notifications(bucket, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/notificationConfigs', options)
          command.response_representation = Google::Apis::StorageV1::Notifications::Representation
          command.response_class = Google::Apis::StorageV1::Notifications
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Permanently deletes the ACL entry for the specified entity on the specified
        # object.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [NilClass] No result returned for this method
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [void]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def delete_object_access_control(bucket, object, entity, generation: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:delete, 'b/{bucket}/o/{object}/acl/{entity}', options)
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Returns the ACL entry for the specified entity on the specified object.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_object_access_control(bucket, object, entity, generation: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/o/{object}/acl/{entity}', options)
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Creates a new ACL entry on the specified object.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [Google::Apis::StorageV1::ObjectAccessControl] object_access_control_object
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def insert_object_access_control(bucket, object, object_access_control_object = nil, generation: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b/{bucket}/o/{object}/acl', options)
          command.request_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.request_object = object_access_control_object
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Retrieves ACL entries on the specified object.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControls] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControls]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def list_object_access_controls(bucket, object, generation: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/o/{object}/acl', options)
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControls::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControls
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Patches an ACL entry on the specified object.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [Google::Apis::StorageV1::ObjectAccessControl] object_access_control_object
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def patch_object_access_control(bucket, object, entity, object_access_control_object = nil, generation: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:patch, 'b/{bucket}/o/{object}/acl/{entity}', options)
          command.request_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.request_object = object_access_control_object
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Updates an ACL entry on the specified object.
        # @param [String] bucket
        #   Name of a bucket.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [String] entity
        #   The entity holding the permission. Can be user-userId, user-emailAddress,
        #   group-groupId, group-emailAddress, allUsers, or allAuthenticatedUsers.
        # @param [Google::Apis::StorageV1::ObjectAccessControl] object_access_control_object
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ObjectAccessControl] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ObjectAccessControl]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def update_object_access_control(bucket, object, entity, object_access_control_object = nil, generation: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:put, 'b/{bucket}/o/{object}/acl/{entity}', options)
          command.request_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.request_object = object_access_control_object
          command.response_representation = Google::Apis::StorageV1::ObjectAccessControl::Representation
          command.response_class = Google::Apis::StorageV1::ObjectAccessControl
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.params['entity'] = entity unless entity.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Concatenates a list of existing objects into a new object in the same bucket.
        # @param [String] destination_bucket
        #   Name of the bucket containing the source objects. The destination object is
        #   stored in this bucket.
        # @param [String] destination_object
        #   Name of the new object. For information about how to URL encode object names
        #   to be path safe, see Encoding URI Path Parts.
        # @param [Google::Apis::StorageV1::ComposeRequest] compose_request_object
        # @param [String] destination_predefined_acl
        #   Apply a predefined set of access controls to the destination object.
        # @param [Fixnum] if_generation_match
        #   Makes the operation conditional on whether the object's current generation
        #   matches the given value. Setting to 0 makes the operation succeed only if
        #   there are no live versions of the object.
        # @param [Fixnum] if_metageneration_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   matches the given value.
        # @param [String] kms_key_name
        #   Resource name of the Cloud KMS key, of the form projects/my-project/locations/
        #   global/keyRings/my-kr/cryptoKeys/my-key, that will be used to encrypt the
        #   object. Overrides the object metadata's kms_key_name value, if any.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Object] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Object]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def compose_object(destination_bucket, destination_object, compose_request_object = nil, destination_predefined_acl: nil, if_generation_match: nil, if_metageneration_match: nil, kms_key_name: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b/{destinationBucket}/o/{destinationObject}/compose', options)
          command.request_representation = Google::Apis::StorageV1::ComposeRequest::Representation
          command.request_object = compose_request_object
          command.response_representation = Google::Apis::StorageV1::Object::Representation
          command.response_class = Google::Apis::StorageV1::Object
          command.params['destinationBucket'] = destination_bucket unless destination_bucket.nil?
          command.params['destinationObject'] = destination_object unless destination_object.nil?
          command.query['destinationPredefinedAcl'] = destination_predefined_acl unless destination_predefined_acl.nil?
          command.query['ifGenerationMatch'] = if_generation_match unless if_generation_match.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['kmsKeyName'] = kms_key_name unless kms_key_name.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Copies a source object to a destination object. Optionally overrides metadata.
        # @param [String] source_bucket
        #   Name of the bucket in which to find the source object.
        # @param [String] source_object
        #   Name of the source object. For information about how to URL encode object
        #   names to be path safe, see Encoding URI Path Parts.
        # @param [String] destination_bucket
        #   Name of the bucket in which to store the new object. Overrides the provided
        #   object metadata's bucket value, if any.For information about how to URL encode
        #   object names to be path safe, see Encoding URI Path Parts.
        # @param [String] destination_object
        #   Name of the new object. Required when the object metadata is not otherwise
        #   provided. Overrides the object metadata's name value, if any.
        # @param [Google::Apis::StorageV1::Object] object_object
        # @param [String] destination_kms_key_name
        #   Resource name of the Cloud KMS key, of the form projects/my-project/locations/
        #   global/keyRings/my-kr/cryptoKeys/my-key, that will be used to encrypt the
        #   object. Overrides the object metadata's kms_key_name value, if any.
        # @param [String] destination_predefined_acl
        #   Apply a predefined set of access controls to the destination object.
        # @param [Fixnum] if_generation_match
        #   Makes the operation conditional on whether the destination object's current
        #   generation matches the given value. Setting to 0 makes the operation succeed
        #   only if there are no live versions of the object.
        # @param [Fixnum] if_generation_not_match
        #   Makes the operation conditional on whether the destination object's current
        #   generation does not match the given value. If no live object exists, the
        #   precondition fails. Setting to 0 makes the operation succeed only if there is
        #   a live version of the object.
        # @param [Fixnum] if_metageneration_match
        #   Makes the operation conditional on whether the destination object's current
        #   metageneration matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the operation conditional on whether the destination object's current
        #   metageneration does not match the given value.
        # @param [Fixnum] if_source_generation_match
        #   Makes the operation conditional on whether the source object's current
        #   generation matches the given value.
        # @param [Fixnum] if_source_generation_not_match
        #   Makes the operation conditional on whether the source object's current
        #   generation does not match the given value.
        # @param [Fixnum] if_source_metageneration_match
        #   Makes the operation conditional on whether the source object's current
        #   metageneration matches the given value.
        # @param [Fixnum] if_source_metageneration_not_match
        #   Makes the operation conditional on whether the source object's current
        #   metageneration does not match the given value.
        # @param [String] projection
        #   Set of properties to return. Defaults to noAcl, unless the object resource
        #   specifies the acl property, when it defaults to full.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [Fixnum] source_generation
        #   If present, selects a specific revision of the source object (as opposed to
        #   the latest version, the default).
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Object] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Object]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def copy_object(source_bucket, source_object, destination_bucket, destination_object, object_object = nil, destination_kms_key_name: nil, destination_predefined_acl: nil, if_generation_match: nil, if_generation_not_match: nil, if_metageneration_match: nil, if_metageneration_not_match: nil, if_source_generation_match: nil, if_source_generation_not_match: nil, if_source_metageneration_match: nil, if_source_metageneration_not_match: nil, projection: nil, provisional_user_project: nil, source_generation: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b/{sourceBucket}/o/{sourceObject}/copyTo/b/{destinationBucket}/o/{destinationObject}', options)
          command.request_representation = Google::Apis::StorageV1::Object::Representation
          command.request_object = object_object
          command.response_representation = Google::Apis::StorageV1::Object::Representation
          command.response_class = Google::Apis::StorageV1::Object
          command.params['sourceBucket'] = source_bucket unless source_bucket.nil?
          command.params['sourceObject'] = source_object unless source_object.nil?
          command.params['destinationBucket'] = destination_bucket unless destination_bucket.nil?
          command.params['destinationObject'] = destination_object unless destination_object.nil?
          command.query['destinationKmsKeyName'] = destination_kms_key_name unless destination_kms_key_name.nil?
          command.query['destinationPredefinedAcl'] = destination_predefined_acl unless destination_predefined_acl.nil?
          command.query['ifGenerationMatch'] = if_generation_match unless if_generation_match.nil?
          command.query['ifGenerationNotMatch'] = if_generation_not_match unless if_generation_not_match.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['ifSourceGenerationMatch'] = if_source_generation_match unless if_source_generation_match.nil?
          command.query['ifSourceGenerationNotMatch'] = if_source_generation_not_match unless if_source_generation_not_match.nil?
          command.query['ifSourceMetagenerationMatch'] = if_source_metageneration_match unless if_source_metageneration_match.nil?
          command.query['ifSourceMetagenerationNotMatch'] = if_source_metageneration_not_match unless if_source_metageneration_not_match.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['sourceGeneration'] = source_generation unless source_generation.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Deletes an object and its metadata. Deletions are permanent if versioning is
        # not enabled for the bucket, or if the generation parameter is used.
        # @param [String] bucket
        #   Name of the bucket in which the object resides.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [Fixnum] generation
        #   If present, permanently deletes a specific revision of this object (as opposed
        #   to the latest version, the default).
        # @param [Fixnum] if_generation_match
        #   Makes the operation conditional on whether the object's current generation
        #   matches the given value. Setting to 0 makes the operation succeed only if
        #   there are no live versions of the object.
        # @param [Fixnum] if_generation_not_match
        #   Makes the operation conditional on whether the object's current generation
        #   does not match the given value. If no live object exists, the precondition
        #   fails. Setting to 0 makes the operation succeed only if there is a live
        #   version of the object.
        # @param [Fixnum] if_metageneration_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   does not match the given value.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [NilClass] No result returned for this method
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [void]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def delete_object(bucket, object, generation: nil, if_generation_match: nil, if_generation_not_match: nil, if_metageneration_match: nil, if_metageneration_not_match: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:delete, 'b/{bucket}/o/{object}', options)
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['ifGenerationMatch'] = if_generation_match unless if_generation_match.nil?
          command.query['ifGenerationNotMatch'] = if_generation_not_match unless if_generation_not_match.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Retrieves an object or its metadata.
        # @param [String] bucket
        #   Name of the bucket in which the object resides.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [Fixnum] if_generation_match
        #   Makes the operation conditional on whether the object's current generation
        #   matches the given value. Setting to 0 makes the operation succeed only if
        #   there are no live versions of the object.
        # @param [Fixnum] if_generation_not_match
        #   Makes the operation conditional on whether the object's current generation
        #   does not match the given value. If no live object exists, the precondition
        #   fails. Setting to 0 makes the operation succeed only if there is a live
        #   version of the object.
        # @param [Fixnum] if_metageneration_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   does not match the given value.
        # @param [String] projection
        #   Set of properties to return. Defaults to noAcl.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [IO, String] download_dest
        #   IO stream or filename to receive content download
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Object] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Object]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_object(bucket, object, generation: nil, if_generation_match: nil, if_generation_not_match: nil, if_metageneration_match: nil, if_metageneration_not_match: nil, projection: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, download_dest: nil, options: nil, &block)
          if download_dest.nil?
            command = make_simple_command(:get, 'b/{bucket}/o/{object}', options)
          else
            command = make_download_command(:get, 'b/{bucket}/o/{object}', options)
            command.download_dest = download_dest
          end
          command.response_representation = Google::Apis::StorageV1::Object::Representation
          command.response_class = Google::Apis::StorageV1::Object
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['ifGenerationMatch'] = if_generation_match unless if_generation_match.nil?
          command.query['ifGenerationNotMatch'] = if_generation_not_match unless if_generation_not_match.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Returns an IAM policy for the specified object.
        # @param [String] bucket
        #   Name of the bucket in which the object resides.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Policy] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Policy]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_object_iam_policy(bucket, object, generation: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/o/{object}/iam', options)
          command.response_representation = Google::Apis::StorageV1::Policy::Representation
          command.response_class = Google::Apis::StorageV1::Policy
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Stores a new object and metadata.
        # @param [String] bucket
        #   Name of the bucket in which to store the new object. Overrides the provided
        #   object metadata's bucket value, if any.
        # @param [Google::Apis::StorageV1::Object] object_object
        # @param [String] content_encoding
        #   If set, sets the contentEncoding property of the final object to this value.
        #   Setting this parameter is equivalent to setting the contentEncoding metadata
        #   property. This can be useful when uploading an object with uploadType=media to
        #   indicate the encoding of the content being uploaded.
        # @param [Fixnum] if_generation_match
        #   Makes the operation conditional on whether the object's current generation
        #   matches the given value. Setting to 0 makes the operation succeed only if
        #   there are no live versions of the object.
        # @param [Fixnum] if_generation_not_match
        #   Makes the operation conditional on whether the object's current generation
        #   does not match the given value. If no live object exists, the precondition
        #   fails. Setting to 0 makes the operation succeed only if there is a live
        #   version of the object.
        # @param [Fixnum] if_metageneration_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   does not match the given value.
        # @param [String] kms_key_name
        #   Resource name of the Cloud KMS key, of the form projects/my-project/locations/
        #   global/keyRings/my-kr/cryptoKeys/my-key, that will be used to encrypt the
        #   object. Overrides the object metadata's kms_key_name value, if any.
        # @param [String] name
        #   Name of the object. Required when the object metadata is not otherwise
        #   provided. Overrides the object metadata's name value, if any. For information
        #   about how to URL encode object names to be path safe, see Encoding URI Path
        #   Parts.
        # @param [String] predefined_acl
        #   Apply a predefined set of access controls to this object.
        # @param [String] projection
        #   Set of properties to return. Defaults to noAcl, unless the object resource
        #   specifies the acl property, when it defaults to full.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [IO, String] upload_source
        #   IO stream or filename containing content to upload
        # @param [String] content_type
        #   Content type of the uploaded content.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Object] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Object]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def insert_object(bucket, object_object = nil, content_encoding: nil, if_generation_match: nil, if_generation_not_match: nil, if_metageneration_match: nil, if_metageneration_not_match: nil, kms_key_name: nil, name: nil, predefined_acl: nil, projection: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, upload_source: nil, content_type: nil, options: nil, &block)
          if upload_source.nil?
            command = make_simple_command(:post, 'b/{bucket}/o', options)
          else
            command = make_upload_command(:post, 'b/{bucket}/o', options)
            command.upload_source = upload_source
            command.upload_content_type = content_type
          end
          command.request_representation = Google::Apis::StorageV1::Object::Representation
          command.request_object = object_object
          command.response_representation = Google::Apis::StorageV1::Object::Representation
          command.response_class = Google::Apis::StorageV1::Object
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['contentEncoding'] = content_encoding unless content_encoding.nil?
          command.query['ifGenerationMatch'] = if_generation_match unless if_generation_match.nil?
          command.query['ifGenerationNotMatch'] = if_generation_not_match unless if_generation_not_match.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['kmsKeyName'] = kms_key_name unless kms_key_name.nil?
          command.query['name'] = name unless name.nil?
          command.query['predefinedAcl'] = predefined_acl unless predefined_acl.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Retrieves a list of objects matching the criteria.
        # @param [String] bucket
        #   Name of the bucket in which to look for objects.
        # @param [String] delimiter
        #   Returns results in a directory-like mode. items will contain only objects
        #   whose names, aside from the prefix, do not contain delimiter. Objects whose
        #   names, aside from the prefix, contain delimiter will have their name,
        #   truncated after the delimiter, returned in prefixes. Duplicate prefixes are
        #   omitted.
        # @param [String] end_offset
        #   Filter results to objects whose names are lexicographically before endOffset.
        #   If startOffset is also set, the objects listed will have names between
        #   startOffset (inclusive) and endOffset (exclusive).
        # @param [Boolean] include_trailing_delimiter
        #   If true, objects that end in exactly one instance of delimiter will have their
        #   metadata included in items in addition to prefixes.
        # @param [Fixnum] max_results
        #   Maximum number of items plus prefixes to return in a single page of responses.
        #   As duplicate prefixes are omitted, fewer total results may be returned than
        #   requested. The service will use this parameter or 1,000 items, whichever is
        #   smaller.
        # @param [String] page_token
        #   A previously-returned page token representing part of the larger set of
        #   results to view.
        # @param [String] prefix
        #   Filter results to objects whose names begin with this prefix.
        # @param [String] projection
        #   Set of properties to return. Defaults to noAcl.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] start_offset
        #   Filter results to objects whose names are lexicographically equal to or after
        #   startOffset. If endOffset is also set, the objects listed will have names
        #   between startOffset (inclusive) and endOffset (exclusive).
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [Boolean] versions
        #   If true, lists all versions of an object as distinct results. The default is
        #   false. For more information, see Object Versioning.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Objects] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Objects]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def list_objects(bucket, delimiter: nil, end_offset: nil, include_trailing_delimiter: nil, max_results: nil, page_token: nil, prefix: nil, projection: nil, provisional_user_project: nil, start_offset: nil, user_project: nil, versions: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/o', options)
          command.response_representation = Google::Apis::StorageV1::Objects::Representation
          command.response_class = Google::Apis::StorageV1::Objects
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['delimiter'] = delimiter unless delimiter.nil?
          command.query['endOffset'] = end_offset unless end_offset.nil?
          command.query['includeTrailingDelimiter'] = include_trailing_delimiter unless include_trailing_delimiter.nil?
          command.query['maxResults'] = max_results unless max_results.nil?
          command.query['pageToken'] = page_token unless page_token.nil?
          command.query['prefix'] = prefix unless prefix.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['startOffset'] = start_offset unless start_offset.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['versions'] = versions unless versions.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Patches an object's metadata.
        # @param [String] bucket
        #   Name of the bucket in which the object resides.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [Google::Apis::StorageV1::Object] object_object
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [Fixnum] if_generation_match
        #   Makes the operation conditional on whether the object's current generation
        #   matches the given value. Setting to 0 makes the operation succeed only if
        #   there are no live versions of the object.
        # @param [Fixnum] if_generation_not_match
        #   Makes the operation conditional on whether the object's current generation
        #   does not match the given value. If no live object exists, the precondition
        #   fails. Setting to 0 makes the operation succeed only if there is a live
        #   version of the object.
        # @param [Fixnum] if_metageneration_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   does not match the given value.
        # @param [String] predefined_acl
        #   Apply a predefined set of access controls to this object.
        # @param [String] projection
        #   Set of properties to return. Defaults to full.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request, for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Object] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Object]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def patch_object(bucket, object, object_object = nil, generation: nil, if_generation_match: nil, if_generation_not_match: nil, if_metageneration_match: nil, if_metageneration_not_match: nil, predefined_acl: nil, projection: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:patch, 'b/{bucket}/o/{object}', options)
          command.request_representation = Google::Apis::StorageV1::Object::Representation
          command.request_object = object_object
          command.response_representation = Google::Apis::StorageV1::Object::Representation
          command.response_class = Google::Apis::StorageV1::Object
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['ifGenerationMatch'] = if_generation_match unless if_generation_match.nil?
          command.query['ifGenerationNotMatch'] = if_generation_not_match unless if_generation_not_match.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['predefinedAcl'] = predefined_acl unless predefined_acl.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Rewrites a source object to a destination object. Optionally overrides
        # metadata.
        # @param [String] source_bucket
        #   Name of the bucket in which to find the source object.
        # @param [String] source_object
        #   Name of the source object. For information about how to URL encode object
        #   names to be path safe, see Encoding URI Path Parts.
        # @param [String] destination_bucket
        #   Name of the bucket in which to store the new object. Overrides the provided
        #   object metadata's bucket value, if any.
        # @param [String] destination_object
        #   Name of the new object. Required when the object metadata is not otherwise
        #   provided. Overrides the object metadata's name value, if any. For information
        #   about how to URL encode object names to be path safe, see Encoding URI Path
        #   Parts.
        # @param [Google::Apis::StorageV1::Object] object_object
        # @param [String] destination_kms_key_name
        #   Resource name of the Cloud KMS key, of the form projects/my-project/locations/
        #   global/keyRings/my-kr/cryptoKeys/my-key, that will be used to encrypt the
        #   object. Overrides the object metadata's kms_key_name value, if any.
        # @param [String] destination_predefined_acl
        #   Apply a predefined set of access controls to the destination object.
        # @param [Fixnum] if_generation_match
        #   Makes the operation conditional on whether the object's current generation
        #   matches the given value. Setting to 0 makes the operation succeed only if
        #   there are no live versions of the object.
        # @param [Fixnum] if_generation_not_match
        #   Makes the operation conditional on whether the object's current generation
        #   does not match the given value. If no live object exists, the precondition
        #   fails. Setting to 0 makes the operation succeed only if there is a live
        #   version of the object.
        # @param [Fixnum] if_metageneration_match
        #   Makes the operation conditional on whether the destination object's current
        #   metageneration matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the operation conditional on whether the destination object's current
        #   metageneration does not match the given value.
        # @param [Fixnum] if_source_generation_match
        #   Makes the operation conditional on whether the source object's current
        #   generation matches the given value.
        # @param [Fixnum] if_source_generation_not_match
        #   Makes the operation conditional on whether the source object's current
        #   generation does not match the given value.
        # @param [Fixnum] if_source_metageneration_match
        #   Makes the operation conditional on whether the source object's current
        #   metageneration matches the given value.
        # @param [Fixnum] if_source_metageneration_not_match
        #   Makes the operation conditional on whether the source object's current
        #   metageneration does not match the given value.
        # @param [Fixnum] max_bytes_rewritten_per_call
        #   The maximum number of bytes that will be rewritten per rewrite request. Most
        #   callers shouldn't need to specify this parameter - it is primarily in place to
        #   support testing. If specified the value must be an integral multiple of 1 MiB (
        #   1048576). Also, this only applies to requests where the source and destination
        #   span locations and/or storage classes. Finally, this value must not change
        #   across rewrite calls else you'll get an error that the rewriteToken is invalid.
        # @param [String] projection
        #   Set of properties to return. Defaults to noAcl, unless the object resource
        #   specifies the acl property, when it defaults to full.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] rewrite_token
        #   Include this field (from the previous rewrite response) on each rewrite
        #   request after the first one, until the rewrite response 'done' flag is true.
        #   Calls that provide a rewriteToken can omit all other request fields, but if
        #   included those fields must match the values provided in the first rewrite
        #   request.
        # @param [Fixnum] source_generation
        #   If present, selects a specific revision of the source object (as opposed to
        #   the latest version, the default).
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::RewriteResponse] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::RewriteResponse]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def rewrite_object(source_bucket, source_object, destination_bucket, destination_object, object_object = nil, destination_kms_key_name: nil, destination_predefined_acl: nil, if_generation_match: nil, if_generation_not_match: nil, if_metageneration_match: nil, if_metageneration_not_match: nil, if_source_generation_match: nil, if_source_generation_not_match: nil, if_source_metageneration_match: nil, if_source_metageneration_not_match: nil, max_bytes_rewritten_per_call: nil, projection: nil, provisional_user_project: nil, rewrite_token: nil, source_generation: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b/{sourceBucket}/o/{sourceObject}/rewriteTo/b/{destinationBucket}/o/{destinationObject}', options)
          command.request_representation = Google::Apis::StorageV1::Object::Representation
          command.request_object = object_object
          command.response_representation = Google::Apis::StorageV1::RewriteResponse::Representation
          command.response_class = Google::Apis::StorageV1::RewriteResponse
          command.params['sourceBucket'] = source_bucket unless source_bucket.nil?
          command.params['sourceObject'] = source_object unless source_object.nil?
          command.params['destinationBucket'] = destination_bucket unless destination_bucket.nil?
          command.params['destinationObject'] = destination_object unless destination_object.nil?
          command.query['destinationKmsKeyName'] = destination_kms_key_name unless destination_kms_key_name.nil?
          command.query['destinationPredefinedAcl'] = destination_predefined_acl unless destination_predefined_acl.nil?
          command.query['ifGenerationMatch'] = if_generation_match unless if_generation_match.nil?
          command.query['ifGenerationNotMatch'] = if_generation_not_match unless if_generation_not_match.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['ifSourceGenerationMatch'] = if_source_generation_match unless if_source_generation_match.nil?
          command.query['ifSourceGenerationNotMatch'] = if_source_generation_not_match unless if_source_generation_not_match.nil?
          command.query['ifSourceMetagenerationMatch'] = if_source_metageneration_match unless if_source_metageneration_match.nil?
          command.query['ifSourceMetagenerationNotMatch'] = if_source_metageneration_not_match unless if_source_metageneration_not_match.nil?
          command.query['maxBytesRewrittenPerCall'] = max_bytes_rewritten_per_call unless max_bytes_rewritten_per_call.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['rewriteToken'] = rewrite_token unless rewrite_token.nil?
          command.query['sourceGeneration'] = source_generation unless source_generation.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Updates an IAM policy for the specified object.
        # @param [String] bucket
        #   Name of the bucket in which the object resides.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [Google::Apis::StorageV1::Policy] policy_object
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Policy] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Policy]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def set_object_iam_policy(bucket, object, policy_object = nil, generation: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:put, 'b/{bucket}/o/{object}/iam', options)
          command.request_representation = Google::Apis::StorageV1::Policy::Representation
          command.request_object = policy_object
          command.response_representation = Google::Apis::StorageV1::Policy::Representation
          command.response_class = Google::Apis::StorageV1::Policy
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Tests a set of permissions on the given object to see which, if any, are held
        # by the caller.
        # @param [String] bucket
        #   Name of the bucket in which the object resides.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [Array<String>, String] permissions
        #   Permissions to test.
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::TestIamPermissionsResponse] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::TestIamPermissionsResponse]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def test_object_iam_permissions(bucket, object, permissions, generation: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'b/{bucket}/o/{object}/iam/testPermissions', options)
          command.response_representation = Google::Apis::StorageV1::TestIamPermissionsResponse::Representation
          command.response_class = Google::Apis::StorageV1::TestIamPermissionsResponse
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['permissions'] = permissions unless permissions.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Updates an object's metadata.
        # @param [String] bucket
        #   Name of the bucket in which the object resides.
        # @param [String] object
        #   Name of the object. For information about how to URL encode object names to be
        #   path safe, see Encoding URI Path Parts.
        # @param [Google::Apis::StorageV1::Object] object_object
        # @param [Fixnum] generation
        #   If present, selects a specific revision of this object (as opposed to the
        #   latest version, the default).
        # @param [Fixnum] if_generation_match
        #   Makes the operation conditional on whether the object's current generation
        #   matches the given value. Setting to 0 makes the operation succeed only if
        #   there are no live versions of the object.
        # @param [Fixnum] if_generation_not_match
        #   Makes the operation conditional on whether the object's current generation
        #   does not match the given value. If no live object exists, the precondition
        #   fails. Setting to 0 makes the operation succeed only if there is a live
        #   version of the object.
        # @param [Fixnum] if_metageneration_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   matches the given value.
        # @param [Fixnum] if_metageneration_not_match
        #   Makes the operation conditional on whether the object's current metageneration
        #   does not match the given value.
        # @param [String] predefined_acl
        #   Apply a predefined set of access controls to this object.
        # @param [String] projection
        #   Set of properties to return. Defaults to full.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Object] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Object]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def update_object(bucket, object, object_object = nil, generation: nil, if_generation_match: nil, if_generation_not_match: nil, if_metageneration_match: nil, if_metageneration_not_match: nil, predefined_acl: nil, projection: nil, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:put, 'b/{bucket}/o/{object}', options)
          command.request_representation = Google::Apis::StorageV1::Object::Representation
          command.request_object = object_object
          command.response_representation = Google::Apis::StorageV1::Object::Representation
          command.response_class = Google::Apis::StorageV1::Object
          command.params['bucket'] = bucket unless bucket.nil?
          command.params['object'] = object unless object.nil?
          command.query['generation'] = generation unless generation.nil?
          command.query['ifGenerationMatch'] = if_generation_match unless if_generation_match.nil?
          command.query['ifGenerationNotMatch'] = if_generation_not_match unless if_generation_not_match.nil?
          command.query['ifMetagenerationMatch'] = if_metageneration_match unless if_metageneration_match.nil?
          command.query['ifMetagenerationNotMatch'] = if_metageneration_not_match unless if_metageneration_not_match.nil?
          command.query['predefinedAcl'] = predefined_acl unless predefined_acl.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Watch for changes on all objects in a bucket.
        # @param [String] bucket
        #   Name of the bucket in which to look for objects.
        # @param [Google::Apis::StorageV1::Channel] channel_object
        # @param [String] delimiter
        #   Returns results in a directory-like mode. items will contain only objects
        #   whose names, aside from the prefix, do not contain delimiter. Objects whose
        #   names, aside from the prefix, contain delimiter will have their name,
        #   truncated after the delimiter, returned in prefixes. Duplicate prefixes are
        #   omitted.
        # @param [String] end_offset
        #   Filter results to objects whose names are lexicographically before endOffset.
        #   If startOffset is also set, the objects listed will have names between
        #   startOffset (inclusive) and endOffset (exclusive).
        # @param [Boolean] include_trailing_delimiter
        #   If true, objects that end in exactly one instance of delimiter will have their
        #   metadata included in items in addition to prefixes.
        # @param [Fixnum] max_results
        #   Maximum number of items plus prefixes to return in a single page of responses.
        #   As duplicate prefixes are omitted, fewer total results may be returned than
        #   requested. The service will use this parameter or 1,000 items, whichever is
        #   smaller.
        # @param [String] page_token
        #   A previously-returned page token representing part of the larger set of
        #   results to view.
        # @param [String] prefix
        #   Filter results to objects whose names begin with this prefix.
        # @param [String] projection
        #   Set of properties to return. Defaults to noAcl.
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] start_offset
        #   Filter results to objects whose names are lexicographically equal to or after
        #   startOffset. If endOffset is also set, the objects listed will have names
        #   between startOffset (inclusive) and endOffset (exclusive).
        # @param [String] user_project
        #   The project to be billed for this request. Required for Requester Pays buckets.
        # @param [Boolean] versions
        #   If true, lists all versions of an object as distinct results. The default is
        #   false. For more information, see Object Versioning.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::Channel] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::Channel]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def watch_all_objects(bucket, channel_object = nil, delimiter: nil, end_offset: nil, include_trailing_delimiter: nil, max_results: nil, page_token: nil, prefix: nil, projection: nil, provisional_user_project: nil, start_offset: nil, user_project: nil, versions: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'b/{bucket}/o/watch', options)
          command.request_representation = Google::Apis::StorageV1::Channel::Representation
          command.request_object = channel_object
          command.response_representation = Google::Apis::StorageV1::Channel::Representation
          command.response_class = Google::Apis::StorageV1::Channel
          command.params['bucket'] = bucket unless bucket.nil?
          command.query['delimiter'] = delimiter unless delimiter.nil?
          command.query['endOffset'] = end_offset unless end_offset.nil?
          command.query['includeTrailingDelimiter'] = include_trailing_delimiter unless include_trailing_delimiter.nil?
          command.query['maxResults'] = max_results unless max_results.nil?
          command.query['pageToken'] = page_token unless page_token.nil?
          command.query['prefix'] = prefix unless prefix.nil?
          command.query['projection'] = projection unless projection.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['startOffset'] = start_offset unless start_offset.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['versions'] = versions unless versions.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Creates a new HMAC key for the specified service account.
        # @param [String] project_id
        #   Project ID owning the service account.
        # @param [String] service_account_email
        #   Email address of the service account.
        # @param [String] user_project
        #   The project to be billed for this request.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::HmacKey] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::HmacKey]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def create_project_hmac_key(project_id, service_account_email, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:post, 'projects/{projectId}/hmacKeys', options)
          command.response_representation = Google::Apis::StorageV1::HmacKey::Representation
          command.response_class = Google::Apis::StorageV1::HmacKey
          command.params['projectId'] = project_id unless project_id.nil?
          command.query['serviceAccountEmail'] = service_account_email unless service_account_email.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Deletes an HMAC key.
        # @param [String] project_id
        #   Project ID owning the requested key
        # @param [String] access_id
        #   Name of the HMAC key to be deleted.
        # @param [String] user_project
        #   The project to be billed for this request.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [NilClass] No result returned for this method
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [void]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def delete_project_hmac_key(project_id, access_id, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:delete, 'projects/{projectId}/hmacKeys/{accessId}', options)
          command.params['projectId'] = project_id unless project_id.nil?
          command.params['accessId'] = access_id unless access_id.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Retrieves an HMAC key's metadata
        # @param [String] project_id
        #   Project ID owning the service account of the requested key.
        # @param [String] access_id
        #   Name of the HMAC key.
        # @param [String] user_project
        #   The project to be billed for this request.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::HmacKeyMetadata] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::HmacKeyMetadata]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_project_hmac_key(project_id, access_id, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'projects/{projectId}/hmacKeys/{accessId}', options)
          command.response_representation = Google::Apis::StorageV1::HmacKeyMetadata::Representation
          command.response_class = Google::Apis::StorageV1::HmacKeyMetadata
          command.params['projectId'] = project_id unless project_id.nil?
          command.params['accessId'] = access_id unless access_id.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Retrieves a list of HMAC keys matching the criteria.
        # @param [String] project_id
        #   Name of the project in which to look for HMAC keys.
        # @param [Fixnum] max_results
        #   Maximum number of items to return in a single page of responses. The service
        #   uses this parameter or 250 items, whichever is smaller. The max number of
        #   items per page will also be limited by the number of distinct service accounts
        #   in the response. If the number of service accounts in a single response is too
        #   high, the page will truncated and a next page token will be returned.
        # @param [String] page_token
        #   A previously-returned page token representing part of the larger set of
        #   results to view.
        # @param [String] service_account_email
        #   If present, only keys for the given service account are returned.
        # @param [Boolean] show_deleted_keys
        #   Whether or not to show keys in the DELETED state.
        # @param [String] user_project
        #   The project to be billed for this request.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::HmacKeysMetadata] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::HmacKeysMetadata]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def list_project_hmac_keys(project_id, max_results: nil, page_token: nil, service_account_email: nil, show_deleted_keys: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'projects/{projectId}/hmacKeys', options)
          command.response_representation = Google::Apis::StorageV1::HmacKeysMetadata::Representation
          command.response_class = Google::Apis::StorageV1::HmacKeysMetadata
          command.params['projectId'] = project_id unless project_id.nil?
          command.query['maxResults'] = max_results unless max_results.nil?
          command.query['pageToken'] = page_token unless page_token.nil?
          command.query['serviceAccountEmail'] = service_account_email unless service_account_email.nil?
          command.query['showDeletedKeys'] = show_deleted_keys unless show_deleted_keys.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Updates the state of an HMAC key. See the HMAC Key resource descriptor for
        # valid states.
        # @param [String] project_id
        #   Project ID owning the service account of the updated key.
        # @param [String] access_id
        #   Name of the HMAC key being updated.
        # @param [Google::Apis::StorageV1::HmacKeyMetadata] hmac_key_metadata_object
        # @param [String] user_project
        #   The project to be billed for this request.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::HmacKeyMetadata] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::HmacKeyMetadata]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def update_project_hmac_key(project_id, access_id, hmac_key_metadata_object = nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:put, 'projects/{projectId}/hmacKeys/{accessId}', options)
          command.request_representation = Google::Apis::StorageV1::HmacKeyMetadata::Representation
          command.request_object = hmac_key_metadata_object
          command.response_representation = Google::Apis::StorageV1::HmacKeyMetadata::Representation
          command.response_class = Google::Apis::StorageV1::HmacKeyMetadata
          command.params['projectId'] = project_id unless project_id.nil?
          command.params['accessId'] = access_id unless access_id.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end
        
        # Get the email address of this project's Google Cloud Storage service account.
        # @param [String] project_id
        #   Project ID
        # @param [String] provisional_user_project
        #   The project to be billed for this request if the target bucket is requester-
        #   pays bucket.
        # @param [String] user_project
        #   The project to be billed for this request.
        # @param [String] fields
        #   Selector specifying which fields to include in a partial response.
        # @param [String] quota_user
        #   An opaque string that represents a user for quota purposes. Must not exceed 40
        #   characters.
        # @param [String] user_ip
        #   Deprecated. Please use quotaUser instead.
        # @param [Google::Apis::RequestOptions] options
        #   Request-specific options
        #
        # @yield [result, err] Result & error if block supplied
        # @yieldparam result [Google::Apis::StorageV1::ServiceAccount] parsed result object
        # @yieldparam err [StandardError] error object if request failed
        #
        # @return [Google::Apis::StorageV1::ServiceAccount]
        #
        # @raise [Google::Apis::ServerError] An error occurred on the server and the request can be retried
        # @raise [Google::Apis::ClientError] The request is invalid and should not be retried without modification
        # @raise [Google::Apis::AuthorizationError] Authorization is required
        def get_project_service_account(project_id, provisional_user_project: nil, user_project: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)
          command = make_simple_command(:get, 'projects/{projectId}/serviceAccount', options)
          command.response_representation = Google::Apis::StorageV1::ServiceAccount::Representation
          command.response_class = Google::Apis::StorageV1::ServiceAccount
          command.params['projectId'] = project_id unless project_id.nil?
          command.query['provisionalUserProject'] = provisional_user_project unless provisional_user_project.nil?
          command.query['userProject'] = user_project unless user_project.nil?
          command.query['fields'] = fields unless fields.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
          execute_or_queue_command(command, &block)
        end

        protected

        def apply_command_defaults(command)
          command.query['key'] = key unless key.nil?
          command.query['quotaUser'] = quota_user unless quota_user.nil?
          command.query['userIp'] = user_ip unless user_ip.nil?
        end
      end
    end
  end
end
