import { makeAutoObservable } from 'mobx';
import OrganizationStore from './OrganizationStore';
import UserStore from './UserStore';
import { createContext } from 'react';
import { ApolloClient } from '@apollo/client';

export class HomeStore {
  userStore: UserStore;
  organizationStore: OrganizationStore;
  client: ApolloClient<object>;

  constructor(client: ApolloClient<object>) {
    makeAutoObservable(this);
    this.userStore = new UserStore(client);
    this.organizationStore = new OrganizationStore(client);
  }

  async load(organizationName: string) {
    await this.userStore.load();
    await this.organizationStore.load(organizationName);
  }
}

// @ts-ignore
export const HomeStoreContext = createContext<HomeStore>();
