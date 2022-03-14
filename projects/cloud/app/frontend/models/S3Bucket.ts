import { S3BucketInfoFragment } from '@/graphql/types';

export interface S3Bucket {
  id: string;
  name: string;
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
}

export const mapS3Bucket = (bucketFragment: S3BucketInfoFragment) => {
  return {
    id: bucketFragment.id,
    name: bucketFragment.name,
    accessKeyId: bucketFragment.accessKeyId,
    secretAccessKey: bucketFragment.secretAccessKey,
    region: bucketFragment.region,
  } as S3Bucket;
};
