import {
  CreateS3BucketDocument,
  CreateS3BucketMutation,
} from '@/graphql/types';
import { mapS3Bucket } from '@/models';
import ProjectStore from '@/stores/ProjectStore';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';

export class CreateBucketStore {
  bucketName: string = '';
  accessKeyId = '';
  secretAccessKey = '';
  region = '';
  saving = false;

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

  get isCreateButtonDisabled() {
    return (
      this.bucketName.length === 0 ||
      this.accessKeyId.length === 0 ||
      this.secretAccessKey.length === 0 ||
      this.region.length === 0
    );
  }

  async createBucket() {
    runInAction(() => {
      this.saving = true;
    });
    if (this.projectStore.project == null) {
      return;
    }
    const { data } = await this.client.mutate<CreateS3BucketMutation>(
      {
        mutation: CreateS3BucketDocument,
        variables: {
          input: {
            name: this.bucketName,
            accessKeyId: this.accessKeyId,
            secretAccessKey: this.secretAccessKey,
            region: this.region,
            accountId: this.projectStore.project.account.id,
          },
        },
      },
    );

    if (data == null) {
      runInAction(() => {
        this.saving = false;
      });
      return;
    }
    const s3Bucket = mapS3Bucket(data.createS3Bucket);
    runInAction(() => {
      this.saving = false;
      if (this.projectStore.project != null) {
        this.projectStore.project.remoteCacheStorage = s3Bucket;
      }
    });

    return s3Bucket;
  }
}
