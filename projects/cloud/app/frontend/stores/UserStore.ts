import { MeQuery, MeDocument } from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';

export default class UserStore {
  me: MeQuery['me'] | undefined;
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
