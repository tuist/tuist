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
  });
});
