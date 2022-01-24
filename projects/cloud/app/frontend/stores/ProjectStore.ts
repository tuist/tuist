import { ProjectQuery, ProjectDocument } from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';

export default class ProjectStore {
  project: ProjectQuery['project'];
  client: ApolloClient<object>;
  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  async load(name: string, accountName: string) {
    const { data } = await this.client.query({
      query: ProjectDocument,
      variables: {
        name,
        accountName,
      },
    });
    runInAction(() => {
      this.project = data.project;
    });
  }
}
