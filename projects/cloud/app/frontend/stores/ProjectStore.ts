import { ProjectQuery, ProjectDocument } from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';
import { mapProject, Project } from '@/models/Project';

export default class ProjectStore {
  project: Project | undefined;
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
      this.project = mapProject(data.project);
    });
  }
}
