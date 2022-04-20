import {
  CommandEventsDocument,
  CommandEventsQuery,
} from '@/graphql/types';
import {
  CommandEventDetail,
  mapCommandEventDetail,
} from '@/models/CommandEventDetail';
import { ApolloClient } from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';

class DashboardPageStore {
  commandEvents: CommandEventDetail[] = [];

  private client: ApolloClient<object>;

  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  async load(projectId: string) {
    // TODO: Do not use command event details here
    const { data } = await this.client.query<CommandEventsQuery>({
      query: CommandEventsDocument,
      variables: {
        projectId,
        first: 2,
      },
    });
    runInAction(() => {
      this.commandEvents =
        data.commandEvents.edges
          ?.filter((edge) => edge != null)
          .map((edge) => {
            if (edge?.node == null) {
              return null;
            } else {
              return mapCommandEventDetail(edge.node);
            }
          })
          .filter(
            (commandEvent): commandEvent is CommandEventDetail =>
              commandEvent !== null,
          ) ?? [];
    });
  }
}

export default DashboardPageStore;
