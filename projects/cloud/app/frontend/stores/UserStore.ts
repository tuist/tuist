import { MeQuery, MeDocument } from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';

export default class UsersStore {
  me: MeQuery['me'];
  client: ApolloClient<object>;
  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  async load() {
    const { data } = await this.client.query({
      query: MeDocument,
    });
    runInAction(() => {
      this.me = data.me;
    });
  }
}
