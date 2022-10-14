import {
  CommandEventDetailFragment,
  CommandEventQuery,
} from '@/graphql/types';
import { CommandEventDetail } from '@/models/CommandEventDetail';
import CommandEventDetailPageStore from '../CommandEventDetailPageStore';

jest.mock('@apollo/client');

describe('CommandEventDetailPageStore', () => {
  const client = {
    query: jest.fn(),
    mutate: jest.fn(),
  } as any;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('loads command event detail', async () => {
    // Given
    const commandEventDetailPageStore =
      new CommandEventDetailPageStore(client);
    const commandEventDetail: CommandEventDetail = {
      clientId: 'client-id',
      commandArguments: 'generate MyApp',
      createdAt: new Date(),
      duration: 1240,
      macosVersion: '13.3.0',
      tuistVersion: '3.3.0',
      swiftVersion: '5.4.0',
      id: 'command-event-id',
      name: 'generate',
      subcommand: null,
      cacheableTargets: ['Target1', 'Target2', 'Target3', 'Target4'],
      localCacheTargetHits: ['Target2', 'Target4'],
      remoteCacheTargetHits: ['Target3'],
      cacheHitRate: 0.75,
    };
    const commandEventDetailFragment = {
      clientId: commandEventDetail.clientId,
      commandArguments: commandEventDetail.commandArguments,
      createdAt: commandEventDetail.createdAt.toISOString(),
      duration: commandEventDetail.duration,
      macosVersion: commandEventDetail.macosVersion,
      tuistVersion: commandEventDetail.tuistVersion,
      swiftVersion: commandEventDetail.swiftVersion,
      id: commandEventDetail.id,
      name: commandEventDetail.name,
      subcommand: commandEventDetail.subcommand,
      cacheableTargets: commandEventDetail.cacheableTargets,
      localCacheTargetHits: commandEventDetail.localCacheTargetHits,
      remoteCacheTargetHits: commandEventDetail.remoteCacheTargetHits,
      cacheHitRate: commandEventDetail.cacheHitRate,
      __typename: 'CommandEvent',
    } as CommandEventDetailFragment;
    client.query.mockResolvedValueOnce({
      data: {
        commandEvent: commandEventDetailFragment,
      } as CommandEventQuery,
    });

    // When
    await commandEventDetailPageStore.load('id');

    // Then
    expect(commandEventDetailPageStore.commandEventDetail).toEqual(
      commandEventDetail,
    );
    expect(commandEventDetailPageStore.cacheTargetHitRate).toEqual(
      '75 %',
    );
    expect(commandEventDetailPageStore.cacheTargetMisses).toEqual([
      'Target1',
    ]);
  });
});
