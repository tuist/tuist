import {
  AcceptInvitationDocument,
  InvitationDocument,
} from '@/graphql/types';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';

class AcceptInvitationPageStore {
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
    runInAction(() => {
      this.organizationName = data.invitation.organization.name;
      this.inviterEmail = data.invitation.inviter.account.name;
    });
  }

  async acceptInvitation(token: string): Promise<string> {
    const { data } = await this.client.mutate({
      mutation: AcceptInvitationDocument,
      variables: { input: { token } },
    });
    return data.acceptInvitation.account.projects[0]?.slug ?? '';
  }
}

export default AcceptInvitationPageStore;
