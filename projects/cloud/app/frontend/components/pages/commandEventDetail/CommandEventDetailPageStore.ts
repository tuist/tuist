import {
  CommandEventDocument,
  CommandEventQuery,
} from '@/graphql/types';
import {
  CommandEventDetail,
  mapCommandEventDetail,
} from '@/models/CommandEventDetail';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';

class CommandEventDetailPageStore {
  commandEventDetail?: CommandEventDetail;
  private client: ApolloClient<object>;

  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  async load(commandEventId: string) {
    const { data } = await this.client.query<CommandEventQuery>({
      query: CommandEventDocument,
      variables: { commandEventId },
    });

    runInAction(() => {
      this.commandEventDetail = mapCommandEventDetail(
        data.commandEvent,
      );
    });
  }
}

export default CommandEventDetailPageStore;
