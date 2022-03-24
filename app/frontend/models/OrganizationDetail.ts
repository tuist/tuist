import { Organization } from '@/graphql/types';
import {
  mapPendingInvitation,
  PendingInvitation,
} from './PendingInvitation';
import { mapUserBasicInfo, UserBasicInfo } from './UserBasicInfo';

export interface OrganizationDetail {
  id: string;
  pendingInvitations: PendingInvitation[];
  admins: UserBasicInfo[];
  users: UserBasicInfo[];
}

export const mapOrganizationDetail = ({
  id,
  invitations,
  admins,
  users,
}: Organization) => {
  return {
    id,
    pendingInvitations: invitations.map((pendingInvitation) =>
      mapPendingInvitation(pendingInvitation),
    ),
    admins: admins.map((admin) => mapUserBasicInfo(admin)),
    users: users.map((user) => mapUserBasicInfo(user)),
  } as OrganizationDetail;
};
