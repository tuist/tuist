import {
  ChangeRemoteCacheStorageDocument,
  ChangeRemoteCacheStorageMutation,
  CreateS3BucketDocument,
  CreateS3BucketMutation,
  S3BucketsDocument,
  S3BucketsQuery,
  UpdateS3BucketMutation,
  UpdateS3BucketDocument,
} from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { SelectOption } from '@shopify/polaris';
import { makeAutoObservable, runInAction } from 'mobx';
import ProjectStore from '@/stores/ProjectStore';
import { mapS3Bucket, S3Bucket } from '@/models';
import { copyToClipboard } from '@/utilities/copyToClipboard';

class RemoteCachePageStore {
  bucketName = '';
  accessKeyId = '';
  secretAccessKey = '';
  region = '';
  isDefaultBucket = false;
  s3Buckets: S3Bucket[] = [];
  isApplyChangesButtonLoading = false;
  isCopyProjectButtonLoading = false;

  client: ApolloClient<object>;
  projectStore: ProjectStore;

  constructor(
    client: ApolloClient<object>,
    projectStore: ProjectStore,
  ) {
    this.client = client;
    this.projectStore = projectStore;
    makeAutoObservable(this);
  }

  get isSecretAccessKeyTextFieldDisabled(): boolean {
    if (this.projectStore.project == null) {
      return true;
    }
    return (
      this.selectedOption !== 'new' &&
      this.secretAccessKey ===
        this.projectStore.project.remoteCacheStorage?.secretAccessKey
    );
  }

  get bucketOptions(): SelectOption[] {
    return [
      {
        label: 'Create new bucket',
        value: 'new',
      },
      ...this.s3Buckets.map((s3Bucket) => {
        return {
          label: s3Bucket.isDefault
            ? 'Default bucket'
            : s3Bucket.name,
          value: s3Bucket.name,
        };
      }),
    ];
  }

  get selectedOption(): string {
    if (
      this.projectStore.project == null ||
      this.projectStore.project.remoteCacheStorage == null
    ) {
      return 'new';
    }
    return this.projectStore.project.remoteCacheStorage.name;
  }

  copyProjectToken() {
    if (this.projectStore.project == null) {
      return;
    }
    copyToClipboard(this.projectStore.project.token);
    this.isCopyProjectButtonLoading = true;
    setTimeout(() => {
      this.isCopyProjectButtonLoading = false;
    }, 1000);
  }

  removeAccessKey() {
    this.secretAccessKey = '';
  }

  async changeRemoteCacheStorage() {
    if (
      this.projectStore.project == null ||
      this.projectStore.project.remoteCacheStorage == null
    ) {
      return;
    }
    await this.client.mutate<ChangeRemoteCacheStorageMutation>({
      mutation: ChangeRemoteCacheStorageDocument,
      variables: {
        input: {
          id: this.projectStore.project.remoteCacheStorage.id,
          projectId: this.projectStore.project.id,
        },
      },
    });
  }

  handleSelectOption(option: string) {
    if (this.projectStore.project == null) {
      return;
    }
    if (option == 'new') {
      this.projectStore.project.remoteCacheStorage = null;
      this.bucketName = '';
      this.accessKeyId = '';
      this.secretAccessKey = '';
      this.region = '';
      this.isDefaultBucket = false;
    }
    const s3Bucket = this.s3Buckets.find(
      (s3Bucket) => s3Bucket.name === option,
    );
    this.projectStore.project.remoteCacheStorage = s3Bucket ?? null;
    if (s3Bucket == null) {
      return;
    }
    this.bucketName = s3Bucket.name;
    this.accessKeyId = s3Bucket.accessKeyId;
    this.secretAccessKey = s3Bucket.secretAccessKey;
    this.region = s3Bucket.region;
    this.isDefaultBucket = s3Bucket.isDefault;
    this.changeRemoteCacheStorage();
  }

  get isApplyChangesButtonDisabled() {
    return (
      this.bucketName.length === 0 ||
      this.accessKeyId.length === 0 ||
      this.secretAccessKey.length === 0 ||
      this.region.length === 0
    );
  }

  get isCreatingBucket() {
    return this.selectedOption === 'new';
  }

  async load() {
    if (this.projectStore.project == null) {
      return;
    }
    const { data } = await this.client.query<S3BucketsQuery>({
      query: S3BucketsDocument,
      variables: {
        accountName: this.projectStore.project.account.name,
        projectName: this.projectStore.project.name,
      },
    });
    runInAction(() => {
      this.s3Buckets = data.s3Buckets.map((bucket) =>
        mapS3Bucket(bucket),
      );
      if (
        this.projectStore.project == null ||
        this.projectStore.project.remoteCacheStorage == null
      ) {
        this.bucketName = '';
        this.accessKeyId = '';
        this.secretAccessKey = '';
        this.region = '';
        return;
      }
      const {
        name,
        accessKeyId,
        secretAccessKey,
        region,
        isDefault,
      } = this.projectStore.project.remoteCacheStorage;
      this.bucketName = name;
      this.accessKeyId = accessKeyId;
      this.secretAccessKey = secretAccessKey;
      this.region = region;
      this.isDefaultBucket = isDefault;
    });
  }

  async applyChangesButtonClicked(accountId: string) {
    this.isApplyChangesButtonLoading = true;
    if (this.isCreatingBucket) {
      const { data } =
        await this.client.mutate<CreateS3BucketMutation>({
          mutation: CreateS3BucketDocument,
          variables: {
            input: {
              name: this.bucketName,
              accessKeyId: this.accessKeyId,
              secretAccessKey: this.secretAccessKey,
              region: this.region,
              accountId,
            },
          },
        });
      if (this.projectStore.project == null || data == null) {
        return;
      }
      const s3Bucket = mapS3Bucket(data.createS3Bucket);
      runInAction(() => {
        this.isApplyChangesButtonLoading = false;
        if (this.projectStore.project != null) {
          this.projectStore.project.remoteCacheStorage = s3Bucket;
        }
        this.s3Buckets.push(s3Bucket);
      });
    } else {
      if (this.projectStore.project?.remoteCacheStorage == null) {
        return;
      }
      const { data } =
        await this.client.mutate<UpdateS3BucketMutation>({
          mutation: UpdateS3BucketDocument,
          variables: {
            input: {
              id: this.projectStore.project.remoteCacheStorage.id,
              name: this.bucketName,
              accessKeyId: this.accessKeyId,
              secretAccessKey: this.secretAccessKey,
              region: this.region,
            },
          },
        });
      if (data == null) {
        return;
      }
      const s3Bucket = mapS3Bucket(data.updateS3Bucket);
      runInAction(() => {
        this.isApplyChangesButtonLoading = false;
        if (
          this.projectStore.project == null ||
          this.projectStore.project.remoteCacheStorage == null
        ) {
          return;
        }
        const previousId =
          this.projectStore.project.remoteCacheStorage.id;
        this.s3Buckets = this.s3Buckets.filter(
          (bucket) => bucket.id !== previousId,
        );
        this.s3Buckets.push(s3Bucket);
        this.projectStore.project.remoteCacheStorage = s3Bucket;
      });
    }
  }
}

export default RemoteCachePageStore;
