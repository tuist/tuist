import { UserBasicInfoFragment } from '@/graphql/types';

export interface UserBasicInfo {
  id: string;
  email: string;
  avatarUrl: string;
  accountName: string;
}

export const mapUserBasicInfo = ({
  id,
  email,
  avatarUrl,
  account: { name },
}: UserBasicInfoFragment) => {
  return {
    id,
    email,
    avatarUrl,
    accountName: name,
  } as UserBasicInfo;
};
