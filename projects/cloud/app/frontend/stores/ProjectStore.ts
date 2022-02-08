import { ProjectQuery, ProjectDocument } from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';
import { S3Bucket, mapS3Bucket, Account } from '@/models';

interface Project {
  id: string;
  account: Account;
  remoteCacheStorage: S3Bucket | null;
}

export default class ProjectStore {
  project: Project;
  client: ApolloClient<object>;
  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  async load(name: string, accountName: string) {
    const { data } = await this.client.query<ProjectQuery>({
      query: ProjectDocument,
      variables: {
        name,
        accountName,
      },
    });
    runInAction(() => {
      if (data == null || data.project == null) {
        return;
      }
      this.project = {
        id: data.project.id,
        account: {
          id: data.project.account.id,
          owner: {
            type:
              data.project.account.owner.__typename === 'Organization'
                ? 'organization'
                : 'user',
            id: data.project.account.owner.id,
          },
          name: data.project.account.name,
        },
        remoteCacheStorage:
          data.project.remoteCacheStorage == null
            ? null
            : mapS3Bucket(data.project.remoteCacheStorage),
      };
    });
  }
}
