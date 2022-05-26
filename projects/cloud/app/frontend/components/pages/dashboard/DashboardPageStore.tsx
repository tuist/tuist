import {
  CacheHitRateAveragesDocument,
  CacheHitRateAveragesQuery,
  CommandAveragesDocument,
  CommandAveragesQuery,
  CommandEventsDocument,
  CommandEventsQuery,
} from '@/graphql/types';
import {
  CommandAverage,
  mapCommandAverage,
} from '@/models/CommandAverage';
import { CommandEvent, mapCommandEvent } from '@/models/CommandEvent';
import {
  ApolloClient,
  OperationVariables,
  QueryOptions,
} from '@apollo/client';
import { DataPoint } from '@shopify/polaris-viz';
import { makeAutoObservable, runInAction } from 'mobx';

class DashboardPageStore {
  commandEvents: CommandEvent[] = [];
  hasNextPage = false;
  hasPreviousPage = false;
  isLoading = true;
  commandName = 'generate';
  commandAveragesData: DataPoint[] = [];
  cacheHitRateCommandName = 'generate';
  cacheHitRateAveragesData: DataPoint[] = [];

  private currentStartCursor = '';
  private currentEndCursor = '';
  private client: ApolloClient<object>;

  constructor(client: ApolloClient<object>) {
    this.client = client;
    makeAutoObservable(this);
  }

  async loadCommandAverages(projectId: string) {
    const { data } = await this.client.query<CommandAveragesQuery>({
      query: CommandAveragesDocument,
      variables: {
        projectId,
        commandName: this.commandName,
      },
    });
    runInAction(() => {
      this.commandAveragesData = data.commandAverages.map(
        (commandAverage) => {
          return {
            key: new Date(commandAverage.date).toDateString(),
            value: commandAverage.durationAverage / 1000,
          };
        },
      );
    });
  }

  async loadCacheHitRateAverages(projectId: string) {
    const { data, error } =
      await this.client.query<CacheHitRateAveragesQuery>({
        query: CacheHitRateAveragesDocument,
        variables: {
          projectId,
          commandName: this.cacheHitRateCommandName,
        },
      });
    runInAction(() => {
      this.cacheHitRateAveragesData = data.cacheHitRateAverages.map(
        (cacheHitRateAverage) => {
          return {
            key: new Date(cacheHitRateAverage.date).toDateString(),
            value:
              Math.round(
                cacheHitRateAverage.cacheHitRateAverage * 100 * 10,
              ) / 10,
          };
        },
      );
    });
  }

  async loadNextPage(projectId: string) {
    await this.loadPage({
      projectId,
      first: 20,
      after: this.currentEndCursor,
    });
  }

  async loadPreviousPage(projectId: string) {
    await this.loadPage({
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
    this.isLoading = true;
    const { data, loading } =
      await this.client.query<CommandEventsQuery>({
        query: CommandEventsDocument,
        variables,
      });
    runInAction(() => {
      this.isLoading = loading;
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
              return mapCommandEvent(edge.node);
            }
          })
          .filter(
            (commandEvent): commandEvent is CommandEvent =>
              commandEvent !== null,
          ) ?? [];
    });
  }
}

export default DashboardPageStore;
