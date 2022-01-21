import { User } from './User';
import { Organization } from './Organization';

export interface Account {
  id: string;
  owner: User | Organization;
  name: string;
}
