import {
  CommandEventsDocument,
  CommandEventsQuery,
} from '@/graphql/types';
import {
  CommandEventDetail,
  mapCommandEventDetail,
} from '@/models/CommandEventDetail';
import {
  ApolloClient,
  OperationVariables,
  QueryOptions,
} from '@apollo/client';
import { makeAutoObservable, runInAction } from 'mobx';

class DashboardPageStore {
  commandEvents: CommandEventDetail[] = [];
  hasNextPage = false;
  hasPreviousPage = false;

  private currentStartCursor = '';
  private currentEndCursor = '';
  private client: ApolloClient<object>;

  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  async loadNextPage(projectId: string) {
    this.loadPage({
      projectId,
      first: 20,
      after: this.currentEndCursor,
    });
  }

  async loadPreviousPage(projectId: string) {
    this.loadPage({
      projectId,
      last: 20,
      before: this.currentStartCursor,
    });
  }

  private async loadPage(
    variables: QueryOptions<
      OperationVariables,
      CommandEventsQuery
    >['variables'],
  ) {
    // TODO: Do not use command event details here
    const { data } = await this.client.query<CommandEventsQuery>({
      query: CommandEventsDocument,
      variables,
    });
    runInAction(() => {
      this.hasNextPage = data.commandEvents.pageInfo.hasNextPage;
      this.hasPreviousPage =
        data.commandEvents.pageInfo.hasPreviousPage;
      this.currentStartCursor =
        data.commandEvents.pageInfo.startCursor ?? '';
      this.currentEndCursor =
        data.commandEvents.pageInfo.endCursor ?? '';
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
