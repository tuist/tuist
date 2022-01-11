import { InvitationDocument } from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';

class AcceptInvitationViewStore {
  client: ApolloClient<object>;
  organizationName: string;
  inviterEmail: string;

  constructor(client: ApolloClient<object>) {
    makeAutoObservable(this);
    this.client = client;
  }

  async load(token: string) {
    const { data } = await this.client.query({
      query: InvitationDocument,
      variables: { token },
    });
    console.log(data);
    runInAction(() => {
      this.organizationName = data.invitation.organization.name;
      this.inviterEmail = data.invitation.inviter.account.name;
      console.log(this.organizationName);
    });
  }
}

export default AcceptInvitationViewStore;
