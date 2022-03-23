import { PendingInvitationFragment } from '@/graphql/types';

export interface PendingInvitation {
  id: string;
  inviteeEmail: string;
}

export const mapPendingInvitation = ({
  id,
  inviteeEmail,
}: PendingInvitationFragment) => {
  return {
    id,
    inviteeEmail,
  } as PendingInvitation;
};
