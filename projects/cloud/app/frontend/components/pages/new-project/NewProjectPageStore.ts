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
  formErrors: string[] = [];

  private myAccounts: Account[] = [];

  private client: ApolloClient<object>;

  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  get isCreateProjectButtonDisabled() {
    return (
      this.newProjectName.length === 0 ||
      !this.isNewProjectNameValid ||
      (this.selectedProjectOwner == null &&
        !this.isCreatingOrganization) ||
      (this.isCreatingOrganization &&
        (this.organizationName.length === 0 ||
          !this.isOrganizationNameValid))
    );
  }

  get isNewProjectNameValid() {
    return this.isNameValid(this.newProjectName);
  }

  get isOrganizationNameValid() {
    return this.isNameValid(this.organizationName);
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
    runInAction(() => {
      this.myAccounts = (data?.accounts ?? []).map(
        ({ id, name }) => ({
          id,
          name,
        }),
      );
    });

    // Set default project owner as the first entry from the `myAccounts` array
    if (
      this.selectedProjectOwner === undefined &&
      !this.isCreatingOrganization
    ) {
      runInAction(() => {
        this.selectedProjectOwner = this.myAccounts[0]?.id;
      });
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
    this.newProjectName = newProjectName;
  }

  organizationNameChanged(organizationName: string) {
    this.organizationName = organizationName;
  }

  async createNewProject(onCompleted: (projectSlug: string) => void) {
    this.formErrors = [];
    try {
      const { data } =
        await this.client.mutate<CreateProjectMutation>({
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
      if (data && data.createProject.errors.length !== 0) {
        runInAction(() => {
          this.formErrors = data.createProject.errors.map(
            (error) => error.message,
          );
        });
      } else if (data?.createProject.project) {
        onCompleted(data?.createProject.project.slug);
      }
    } catch {
      runInAction(() => {
        this.formErrors = ['This project could not be created'];
      });
    }
  }

  private isNameValid(name: string) {
    const regex = new RegExp('[^a-z\\-]');
    return !regex.test(name);
  }
}
