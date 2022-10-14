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

  get cacheTargetHitRate(): string {
    if (this.commandEventDetail == null) {
      return '';
    }
    const { cacheHitRate } = this.commandEventDetail;
    if (cacheHitRate == null) {
      return '';
    }

    return `${cacheHitRate * 100} %`;
  }

  get cacheTargetMisses(): string[] {
    if (this.commandEventDetail?.cacheableTargets == null) {
      return [];
    }

    return this.commandEventDetail.cacheableTargets.filter(
      (target) => {
        return !(
          this.commandEventDetail?.localCacheTargetHits?.includes(
            target,
          ) ||
          this.commandEventDetail?.remoteCacheTargetHits?.includes(
            target,
          )
        );
      },
    );
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
