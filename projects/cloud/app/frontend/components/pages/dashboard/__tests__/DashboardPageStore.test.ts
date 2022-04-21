import {
  CommandEventDetailFragment,
  CommandEventsDocument,
  CommandEventsQuery,
} from '@/graphql/types';
import { CommandEventDetail } from '@/models/CommandEventDetail';
import DashboardPageStore from '../DashboardPageStore';

jest.mock('@apollo/client');

describe('DashboardPageStore', () => {
  const client = {
    query: jest.fn(),
    mutate: jest.fn(),
  } as any;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('loads next page', async () => {
    // Given
    const dashboardPageStore = new DashboardPageStore(client);
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
        commandEvents: {
          edges: [
            {
              node: commandEventDetailFragment,
            },
          ],
          pageInfo: {
            hasNextPage: false,
            hasPreviousPage: false,
            endCursor: '',
            startCursor: '',
          },
        },
      } as CommandEventsQuery,
    });

    // When
    await dashboardPageStore.loadNextPage('id');

    // Then
    expect(dashboardPageStore.commandEvents).toStrictEqual([
      commandEventDetail,
    ]);
  });

  it('updates previous and next page availability', async () => {
    const dashboardPageStore = new DashboardPageStore(client);
    client.query.mockResolvedValueOnce({
      data: {
        commandEvents: {
          edges: [],
          pageInfo: {
            hasNextPage: true,
            hasPreviousPage: true,
            endCursor: '',
            startCursor: '',
          },
        },
      } as CommandEventsQuery,
    });

    await dashboardPageStore.loadNextPage('');

    expect(dashboardPageStore.hasNextPage).toBe(true);
    expect(dashboardPageStore.hasPreviousPage).toBe(true);

    client.query.mockResolvedValueOnce({
      data: {
        commandEvents: {
          edges: [],
          pageInfo: {
            hasNextPage: false,
            hasPreviousPage: false,
            endCursor: '',
            startCursor: '',
          },
        },
      } as CommandEventsQuery,
    });
    await dashboardPageStore.loadNextPage('');

    expect(dashboardPageStore.hasNextPage).toBe(false);
    expect(dashboardPageStore.hasPreviousPage).toBe(false);
  });

  it('loads next page with endCursor from the last request', async () => {
    // Given
    const dashboardPageStore = new DashboardPageStore(client);
    client.query.mockResolvedValue({
      data: {
        commandEvents: {
          edges: [],
          pageInfo: {
            hasNextPage: true,
            hasPreviousPage: false,
            endCursor: 'end-cursor',
            startCursor: '',
          },
        },
      } as CommandEventsQuery,
    });
    await dashboardPageStore.loadNextPage('id');

    // When
    await dashboardPageStore.loadNextPage('id');

    // Then
    expect(client.query).toHaveBeenLastCalledWith({
      query: CommandEventsDocument,
      variables: {
        projectId: 'id',
        first: 20,
        after: 'end-cursor',
      },
    });
  });

  it('loads previous page with startCursor from the last request', async () => {
    // Given
    const dashboardPageStore = new DashboardPageStore(client);
    client.query.mockResolvedValue({
      data: {
        commandEvents: {
          edges: [],
          pageInfo: {
            hasNextPage: false,
            hasPreviousPage: true,
            endCursor: '',
            startCursor: 'start-cursor',
          },
        },
      } as CommandEventsQuery,
    });
    await dashboardPageStore.loadNextPage('id');

    // When
    await dashboardPageStore.loadPreviousPage('id');

    // Then
    expect(client.query).toHaveBeenLastCalledWith({
      query: CommandEventsDocument,
      variables: {
        projectId: 'id',
        last: 20,
        before: 'start-cursor',
      },
    });
  });
});
