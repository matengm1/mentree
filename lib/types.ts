// TypeScript types mirroring the database schema.
// When you change supabase/migrations/, update these types to match.

export type OrgType = 'hell_family' | 'fraternity' | 'sorority' | 'club' | 'other'
export type MemberRole = 'owner' | 'admin' | 'member' | 'viewer'
export type RelationshipStatus = 'pending' | 'confirmed' | 'rejected'
export type AuditAction = 'created' | 'confirmed' | 'rejected' | 'deleted' | 'restored'

// ── Row types (what comes back from SELECT queries) ──────────────────────────

export interface School {
  id: string
  name: string
  short_name: string
  allowed_email_domains: string[]
  created_at: string
}

export interface User {
  id: string
  is_staff: boolean
  created_at: string
}

export interface ApprovedEmail {
  id: string
  email: string
  school_id: string
  note: string | null
  added_by: string | null
  created_at: string
}

export interface Profile {
  id: string
  user_id: string | null
  school_id: string
  display_name: string
  graduation_year: number | null
  school_email: string | null
  personal_email: string | null
  is_ghost: boolean
  claimed_at: string | null
  created_at: string
}

export interface Organization {
  id: string
  school_id: string
  name: string
  org_type: OrgType
  description: string | null
  is_public: boolean
  created_at: string
}

export interface Membership {
  id: string
  profile_id: string
  org_id: string
  role: MemberRole
  joined_at: string
  invited_by: string | null
}

export interface FamilyRelationship {
  id: string
  org_id: string
  parent_profile_id: string
  child_profile_id: string
  status: RelationshipStatus
  confirmed_at: string | null
  confirmed_by: string | null
  academic_year: number | null
  added_by: string
  deleted_at: string | null
  created_at: string
}

export interface RelationshipAudit {
  id: string
  relationship_id: string
  action: AuditAction
  actor_profile_id: string | null
  old_data: FamilyRelationship | null
  new_data: FamilyRelationship | null
  created_at: string
}

// ── Insert types (what you pass to INSERT queries) ───────────────────────────

export type NewProfile = Omit<Profile, 'id' | 'created_at' | 'claimed_at'>
export type NewOrganization = Omit<Organization, 'id' | 'created_at'>
export type NewMembership = Omit<Membership, 'id' | 'joined_at'>
export type NewRelationship = Pick<
  FamilyRelationship,
  'org_id' | 'parent_profile_id' | 'child_profile_id' | 'academic_year' | 'added_by'
>

// ── Joined / view types (common query results with related data) ─────────────

export interface ProfileWithSchool extends Profile {
  school: School
}

export interface MembershipWithProfile extends Membership {
  profile: Profile
}

export interface RelationshipWithProfiles extends FamilyRelationship {
  parent: Profile
  child: Profile
}

// ── Supabase Database type (used to type the Supabase client) ────────────────

export type Database = {
  public: {
    Tables: {
      schools: {
        Row: School
        Insert: Omit<School, 'id' | 'created_at'>
        Update: Partial<Omit<School, 'id' | 'created_at'>>
      }
      users: {
        Row: User
        Insert: Pick<User, 'id'>
        Update: Pick<User, 'is_staff'>
      }
      approved_emails: {
        Row: ApprovedEmail
        Insert: Omit<ApprovedEmail, 'id' | 'created_at'>
        Update: Partial<Omit<ApprovedEmail, 'id' | 'created_at'>>
      }
      profiles: {
        Row: Profile
        Insert: NewProfile
        Update: Partial<NewProfile>
      }
      organizations: {
        Row: Organization
        Insert: NewOrganization
        Update: Partial<NewOrganization>
      }
      memberships: {
        Row: Membership
        Insert: NewMembership
        Update: Partial<NewMembership>
      }
      family_relationships: {
        Row: FamilyRelationship
        Insert: NewRelationship
        Update: Partial<FamilyRelationship>
      }
      relationship_audit: {
        Row: RelationshipAudit
        Insert: never
        Update: never
      }
    }
    Functions: {
      is_mentree_staff: {
        Args: Record<string, never>
        Returns: boolean
      }
      create_organization: {
        Args: {
          p_school_id: string
          p_name: string
          p_org_type: OrgType
          p_description: string
          p_profile_id: string
        }
        Returns: Organization
      }
    }
  }
}
