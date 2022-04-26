import {
  CommandAveragesDocument,
  CommandAveragesQuery,
  CommandEventFragment,
  CommandEventsDocument,
  CommandEventsQuery,
} from '@/graphql/types';
import { CommandEvent } from '@/models/CommandEvent';
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

  it('loads command averages for the current command name', async () => {
    const dashboardPageStore = new DashboardPageStore(client);
    client.query.mockResolvedValueOnce({
      data: {
        commandAverages: [
          {
            date: new Date(2022, 5, 2).toString(),
            durationAverage: 1500,
          },
          {
            date: new Date(2022, 5, 3).toString(),
            durationAverage: 1000,
          },
        ],
      } as CommandAveragesQuery,
    });
    await dashboardPageStore.loadCommandAverages('id');
    expect(dashboardPageStore.commandAveragesData).toStrictEqual([
      { key: new Date(2022, 5, 2).toDateString(), value: 1.5 },
      { key: new Date(2022, 5, 3).toDateString(), value: 1 },
    ]);
    expect(client.query).toHaveBeenCalledWith({
      query: CommandAveragesDocument,
      variables: {
        projectId: 'id',
        commandName: 'generate',
      },
    });
    client.query.mockReset();

    dashboardPageStore.commandName = 'fetch';
    client.query.mockResolvedValueOnce({
      data: {
        commandAverages: [
          {
            date: new Date(2022, 5, 1).toString(),
            durationAverage: 100,
          },
          {
            date: new Date(2022, 5, 2).toString(),
            durationAverage: 400,
          },
        ],
      } as CommandAveragesQuery,
    });
    await dashboardPageStore.loadCommandAverages('id');
    expect(dashboardPageStore.commandAveragesData).toStrictEqual([
      { key: new Date(2022, 5, 1).toDateString(), value: 0.1 },
      { key: new Date(2022, 5, 2).toDateString(), value: 0.4 },
    ]);
    expect(client.query).toHaveBeenCalledWith({
      query: CommandAveragesDocument,
      variables: {
        projectId: 'id',
        commandName: 'fetch',
      },
    });
  });

  it('loads next page', async () => {
    // Given
    const dashboardPageStore = new DashboardPageStore(client);
    const commandEventDetail: CommandEvent = {
      commandArguments: 'generate MyApp',
      createdAt: new Date(),
      duration: 1240,
      id: 'command-event-id',
    };
    const commandEventDetailFragment = {
      commandArguments: commandEventDetail.commandArguments,
      createdAt: commandEventDetail.createdAt.toISOString(),
      duration: commandEventDetail.duration,
      id: commandEventDetail.id,
      __typename: 'CommandEvent',
    } as CommandEventFragment;
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
