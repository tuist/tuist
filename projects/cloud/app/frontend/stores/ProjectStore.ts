import {
  ProjectQuery,
  ProjectDocument,
  DeleteProjectMutation,
  DeleteProjectDocument,
} from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';
import { mapProject, Project } from '@/models/Project';

export default class ProjectStore {
  project: Project | undefined | null;
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

  async deleteProject() {
    if (this.project === undefined || this.project === null) {
      return;
    }
    await this.client.mutate<DeleteProjectMutation>({
      mutation: DeleteProjectDocument,
      variables: {
        input: {
          id: this.project.id,
        },
      },
    });
    this.project = null;
  }
}
