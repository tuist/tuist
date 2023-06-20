import ProjectStore from '@/stores/ProjectStore';
import { CreateBucketStore } from '../CreateBucketStore';
import { S3Bucket } from '@/models';

jest.mock('@apollo/client');
jest.mock('@/stores/ProjectStore');

describe('CreateBucketStore', () => {
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
      token: '',
      name: 'project',
      slug: 'org/project',
    };
  });

  it('creates a new bucket', async () => {
    // Given
    const createBucketStore = new CreateBucketStore(
      client,
      projectStore,
    );
    createBucketStore.bucketName = 'S3 bucket';
    createBucketStore.secretAccessKey = 'secret';
    createBucketStore.accessKeyId = 'access-key-id';
    createBucketStore.region = 'region';
    client.mutate.mockReturnValueOnce({
      data: {
        createS3Bucket: {
          accessKeyId: 'access-key-id',
          accountId: 'account-id',
          id: 'id-1',
          name: 'S3 bucket',
          secretAccessKey: 'secret',
          region: 'region',
          __typename: 'S3Bucket',
        },
      },
    });
    const expectedS3Bucket: S3Bucket = {
      accessKeyId: 'access-key-id',
      id: 'id-1',
      name: 'S3 bucket',
      secretAccessKey: 'secret',
      region: 'region',
    };

    // When
    const got = await createBucketStore.createBucket();

    // Then
    expect(
      createBucketStore.projectStore.project?.remoteCacheStorage,
    ).toEqual(expectedS3Bucket);
    expect(got).toEqual(expectedS3Bucket);
  });
});
