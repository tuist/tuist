import { makeAutoObservable } from 'mobx';
import OrganizationStore from './OrganizationStore';
import UserStore from './UserStore';
import ProjectStore from './ProjectStore';
import { createContext } from 'react';
import { ApolloClient } from '@apollo/client';

export class HomeStore {
  userStore: UserStore;
  organizationStore: OrganizationStore;
  projectStore: ProjectStore;
  client: ApolloClient<object>;

  constructor(client: ApolloClient<object>) {
    makeAutoObservable(this);
    this.userStore = new UserStore(client);
    this.organizationStore = new OrganizationStore(client);
    this.projectStore = new ProjectStore(client);
  }

  get isAdmin() {
    if (this.userStore.me === undefined) {
      return false;
    }

    if (this.projectStore.project?.account.owner.type === 'user') {
      return true;
    } else {
      return this.organizationStore.admins
        .map((admin) => admin.id)
        .includes(this.userStore.me.id);
    }
  }

  async load(projectName: string, accountName: string) {
    await this.userStore.load();
    if (this.userStore.me?.account.name !== accountName) {
      await this.organizationStore.load(accountName);
    }
    await this.projectStore.load(projectName, accountName);
  }
}

// @ts-ignore
export const HomeStoreContext = createContext<HomeStore>();
