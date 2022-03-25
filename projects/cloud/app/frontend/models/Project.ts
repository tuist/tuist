import { ProjectDetailFragment } from '@/graphql/types';
import { Account, mapS3Bucket, S3Bucket } from '.';

export interface Project {
  id: string;
  account: Account;
  remoteCacheStorage: S3Bucket | null;
  token: string;
}

export const mapProject = ({
  id,
  account,
  remoteCacheStorage,
  token,
}: ProjectDetailFragment) => {
  let mappedRemoteCacheStorage: S3Bucket | undefined | null;
  if (
    remoteCacheStorage === null ||
    remoteCacheStorage === undefined
  ) {
    mappedRemoteCacheStorage = remoteCacheStorage;
  } else {
    mappedRemoteCacheStorage = mapS3Bucket(remoteCacheStorage);
  }
  return {
    id,
    account: {
      id: account.id,
      owner: {
        type:
          account.owner.__typename === 'Organization'
            ? 'organization'
            : 'user',
        id: account.owner.id,
      },
      name: account.name,
    },
    remoteCacheStorage: mappedRemoteCacheStorage,
    token,
  } as Project;
};
