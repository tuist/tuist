import {
  CreateProjectDocument,
  CreateProjectMutation,
  MyAccountsDocument,
  MyAccountsQuery,
} from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { SelectOption } from '@shopify/polaris';
import { makeAutoObservable, runInAction } from 'mobx';

interface Account {
  id: string;
  name: string;
}

export class NewProjectPageStore {
  newProjectName = '';
  selectedProjectOwner: Account['id'] | null | undefined;
  isCreatingOrganization: boolean = false;
  organizationName: string = '';

  private myAccounts: Account[] = [];

  private client: ApolloClient<object>;

  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  get isCreateProjectButtonDisabled() {
    return (
      this.newProjectName.length === 0 ||
      (this.selectedProjectOwner == null &&
        !this.isCreatingOrganization) ||
      (this.isCreatingOrganization &&
        this.organizationName.length === 0)
    );
  }

  get options(): SelectOption[] {
    return this.myAccounts
      .map((account) => {
        return {
          label: account.name,
          value: account.id,
        };
      })
      .concat([
        {
          label: 'Create new organization',
          value: 'new',
        },
      ]);
  }

  async load() {
    const { data } = await this.client.query<MyAccountsQuery>({
      query: MyAccountsDocument,
    });
    this.myAccounts = (data?.accounts ?? []).map(({ id, name }) => ({
      id,
      name,
    }));

    // Set default project owner as the first entry from the `myAccounts` array
    if (
      this.selectedProjectOwner === undefined &&
      !this.isCreatingOrganization
    ) {
      this.selectedProjectOwner = this.myAccounts[0]?.id;
    }
  }

  selectedProjectOwnerChanged(projectOwner: string) {
    if (projectOwner === 'new') {
      this.isCreatingOrganization = true;
      this.selectedProjectOwner = projectOwner;
    } else {
      this.isCreatingOrganization = false;
      this.selectedProjectOwner = null;
    }
  }

  projectNameChanged(newProjectName: string) {
    console.log(this);
    console.log(newProjectName);
    console.log(this.newProjectName);
    this.newProjectName = newProjectName;
  }

  organizationNameChanged(organizationName: string) {
    this.organizationName = organizationName;
  }

  async createNewProject(onCompleted: (projectSlug: string) => void) {
    const { data } = await this.client.mutate<CreateProjectMutation>({
      mutation: CreateProjectDocument,
      variables: {
        input: {
          accountId: this.isCreatingOrganization
            ? null
            : this.selectedProjectOwner!,
          name: this.newProjectName,
          organizationName: this.isCreatingOrganization
            ? this.organizationName
            : null,
        },
      },
    });

    if (data) {
      onCompleted(data?.createProject.slug);
    }
  }
}
