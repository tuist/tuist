import ProjectStore from '@/stores/ProjectStore';
import RemoteCachePageStore from '../RemoteCachePageStore';
import { Account, S3Bucket } from '@/models';
import { S3BucketInfoFragment } from '@/graphql/types';

jest.mock('@apollo/client');
jest.mock('@/stores/ProjectStore');

describe('RemoteCachePageStore', () => {
  const client = {
    query: jest.fn(),
    mutate: jest.fn(),
  } as any;
  const projectStore = {} as ProjectStore;

  beforeEach(() => {
    jest.clearAllMocks();
    projectStore.project = {
      id: 'project',
      account: {
        id: 'account-id',
        name: 'acount-name',
        owner: {
          id: 'owner',
          type: 'organization',
        },
      },
      remoteCacheStorage: null,
    };
  });

  it('keeps apply changes button disabled when not all fields are filled', async () => {
    // Given
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // When
    remoteCachePageStore.bucketName = '1';
    remoteCachePageStore.accessKeyId = '1';

    // Then
    expect(
      remoteCachePageStore.isApplyChangesButtonDisabled,
    ).toBeTruthy();
  });

  it('marks apply changes button enabled when all fields are filled', async () => {
    // Given
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // When
    remoteCachePageStore.bucketName = '1';
    remoteCachePageStore.accessKeyId = '1';
    remoteCachePageStore.secretAccessKey = '1';

    // Then
    expect(
      remoteCachePageStore.isApplyChangesButtonDisabled,
    ).toBeFalsy();
  });

  it('returns new as selected option when remoteCacheStorage is null', () => {
    // Given
    projectStore.project = {
      id: 'project',
      account: {
        id: 'account-id',
        name: 'acount-name',
        owner: {
          id: 'owner',
          type: 'organization',
        },
      },
      remoteCacheStorage: null,
    };

    // When
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // Then
    expect(remoteCachePageStore.selectedOption).toEqual('new');
    expect(remoteCachePageStore.isCreatingBucket).toBeTruthy();
  });

  it('returns remote cache storage name if it is set in the project', () => {
    // Given
    projectStore.project.remoteCacheStorage = {
      accessKeyId: 'accessKeyId',
      id: 'id',
      name: 'bucket',
      secretAccessKey: 'secret',
    };

    // When
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );

    // Then
    expect(remoteCachePageStore.selectedOption).toEqual('bucket');
  });

  it('loads remote cache page', async () => {
    // Given
    projectStore.project.remoteCacheStorage = {
      accessKeyId: 'key-id-1',
      id: 'id-1',
      name: 'S3 bucket one',
      secretAccessKey: 'secret',
    };
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    client.query.mockResolvedValueOnce({
      data: {
        s3Buckets: [
          {
            accessKeyId: 'key-id-1',
            accountId: 'account-id-1',
            id: 'id-1',
            name: 'S3 bucket one',
            __typename: 'S3Bucket',
          },
          {
            accessKeyId: 'key-id-2',
            accountId: 'account-id-2',
            id: 'id-2',
            name: 'S3 bucket two',
            __typename: 'S3Bucket',
          },
        ] as S3BucketInfoFragment[],
      },
    });

    // When
    await remoteCachePageStore.load();

    // Then
    expect(remoteCachePageStore.bucketName).toEqual('S3 bucket one');
    expect(remoteCachePageStore.accessKeyId).toEqual('key-id-1');
    expect(remoteCachePageStore.secretAccessKey).toEqual('secret');
    expect(remoteCachePageStore.s3Buckets).toEqual([
      {
        accessKeyId: 'key-id-1',
        secretAccessKey: undefined,
        id: 'id-1',
        name: 'S3 bucket one',
      },
      {
        accessKeyId: 'key-id-2',
        secretAccessKey: undefined,
        id: 'id-2',
        name: 'S3 bucket two',
      },
    ]);
    expect(remoteCachePageStore.bucketOptions).toEqual([
      {
        label: 'Create new bucket',
        value: 'new',
      },
      {
        label: 'S3 bucket one',
        value: 'S3 bucket one',
      },
      {
        label: 'S3 bucket two',
        value: 'S3 bucket two',
      },
    ]);
  });

  it('creates a new bucket', async () => {
    // Given
    const remoteCachePageStore = new RemoteCachePageStore(
      client,
      projectStore,
    );
    remoteCachePageStore.bucketName = 'S3 bucket';
    remoteCachePageStore.secretAccessKey = 'secret';
    remoteCachePageStore.accessKeyId = 'access-key-id';
    client.mutate.mockReturnValueOnce({
      data: {
        createS3Bucket: {
          accessKeyId: 'access-key-id',
          accountId: 'account-id',
          id: 'id-1',
          name: 'S3 bucket',
          secretAccessKey: 'secret',
          __typename: 'S3Bucket',
        },
      },
    });
    const expectedS3Bucket: S3Bucket = {
      accessKeyId: 'access-key-id',
      id: 'id-1',
      name: 'S3 bucket',
      secretAccessKey: 'secret',
    };

    // When
    await remoteCachePageStore.applyChangesButtonClicked(
      'account-id',
    );

    // Then
    expect(
      remoteCachePageStore.projectStore.project.remoteCacheStorage,
    ).toEqual(expectedS3Bucket);
    expect(remoteCachePageStore.s3Buckets).toEqual([
      expectedS3Bucket,
    ]);
  });
});
