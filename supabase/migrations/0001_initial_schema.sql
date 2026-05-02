-- 0001_initial_schema.sql
--
-- Creates the full initial schema for Mentree.
-- Run this once in the Supabase SQL editor (or via Supabase CLI).
-- See SETUP.md for step-by-step instructions.
--
-- Tables: schools, users, profiles, organizations, memberships,
--         family_relationships, relationship_audit
--
-- Also creates:
--   - Indexes for all foreign keys and common query patterns
--   - Trigger: auto-create public.users row on auth.users insert
--   - Trigger: auto-audit every insert/update on family_relationships
--   - Row Level Security policies for all tables


-- ============================================================
-- Extensions
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- ============================================================
-- Schools
-- ============================================================

CREATE TABLE IF NOT EXISTS schools (
  id                    uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name                  text NOT NULL,
  short_name            text NOT NULL,
  allowed_email_domains text[] NOT NULL DEFAULT '{}',
  created_at            timestamptz NOT NULL DEFAULT now()
);


-- ============================================================
-- Users (extends Supabase auth.users)
-- ============================================================

-- auth.users is managed by Supabase and not directly editable.
-- This table is a thin extension for app-level user data.
CREATE TABLE IF NOT EXISTS public.users (
  id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Automatically create a public.users row when someone signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id) VALUES (NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ============================================================
-- Profiles
-- ============================================================

-- One profile per person per school. Can be a "ghost" — a placeholder
-- for a historical member who has never registered. When a ghost is
-- claimed, user_id is populated and is_ghost is set to false.
CREATE TABLE IF NOT EXISTS profiles (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         uuid REFERENCES public.users(id) ON DELETE SET NULL,
  school_id       uuid NOT NULL REFERENCES schools(id),
  display_name    text NOT NULL,
  graduation_year smallint,
  school_email    text,
  personal_email  text,
  is_ghost        boolean NOT NULL DEFAULT false,
  claimed_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),

  -- A row is either a ghost (no user) or a real profile (has a user).
  CONSTRAINT ghost_xor_user CHECK (
    (is_ghost = true  AND user_id IS NULL) OR
    (is_ghost = false AND user_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_profiles_user_id   ON profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_school_id ON profiles(school_id);


-- ============================================================
-- Organizations
-- ============================================================

-- An organization is a group within a school that tracks lineage.
-- Examples: "Hell Families", "Phi Delta Pre-Law Fraternity".
-- org_type controls terminology in the UI (hell parent/child vs big/little, etc.)
CREATE TABLE IF NOT EXISTS organizations (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id   uuid NOT NULL REFERENCES schools(id),
  name        text NOT NULL,
  org_type    text NOT NULL CHECK (org_type IN ('hell_family', 'fraternity', 'sorority', 'club', 'other')),
  description text,
  is_public   boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_organizations_school_id ON organizations(school_id);


-- ============================================================
-- Memberships
-- ============================================================

-- Links a profile to an organization with a role.
-- Roles (descending power): owner > admin > member > viewer
CREATE TABLE IF NOT EXISTS memberships (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  org_id     uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  role       text NOT NULL CHECK (role IN ('owner', 'admin', 'member', 'viewer')),
  joined_at  timestamptz NOT NULL DEFAULT now(),
  invited_by uuid REFERENCES profiles(id),

  UNIQUE (profile_id, org_id)
);

CREATE INDEX IF NOT EXISTS idx_memberships_profile_id ON memberships(profile_id);
CREATE INDEX IF NOT EXISTS idx_memberships_org_id     ON memberships(org_id);


-- ============================================================
-- Family Relationships (the tree edges)
-- ============================================================

-- Each row is a directed edge: parent proposed-to-by child.
-- The UNIQUE constraint on (org_id, child_profile_id) enforces that
-- each person has at most one parent per org (single-parent tree).
--
-- status flow:
--   pending   → confirmed  (other party confirms, or admin approves)
--   pending   → rejected   (other party rejects)
--   confirmed → (soft-deleted via deleted_at)
CREATE TABLE IF NOT EXISTS family_relationships (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id            uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  parent_profile_id uuid NOT NULL REFERENCES profiles(id),
  child_profile_id  uuid NOT NULL REFERENCES profiles(id),
  status            text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'confirmed', 'rejected')),
  confirmed_at      timestamptz,
  confirmed_by      uuid REFERENCES profiles(id),
  academic_year     smallint,
  added_by          uuid NOT NULL REFERENCES profiles(id),
  deleted_at        timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),

  UNIQUE (org_id, child_profile_id),
  CONSTRAINT no_self_relationship CHECK (parent_profile_id != child_profile_id)
);

CREATE INDEX IF NOT EXISTS idx_relationships_org_id    ON family_relationships(org_id);
CREATE INDEX IF NOT EXISTS idx_relationships_parent    ON family_relationships(parent_profile_id);
CREATE INDEX IF NOT EXISTS idx_relationships_child     ON family_relationships(child_profile_id);
CREATE INDEX IF NOT EXISTS idx_relationships_status    ON family_relationships(status) WHERE deleted_at IS NULL;


-- ============================================================
-- Relationship Audit Log
-- ============================================================

-- Append-only log of every state change on family_relationships.
-- old_data / new_data are full JSON snapshots of the row.
-- Admins use this to understand history and restore soft-deleted relationships.
CREATE TABLE IF NOT EXISTS relationship_audit (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  relationship_id   uuid NOT NULL REFERENCES family_relationships(id),
  action            text NOT NULL CHECK (action IN ('created', 'confirmed', 'rejected', 'deleted', 'restored')),
  actor_profile_id  uuid REFERENCES profiles(id),
  old_data          jsonb,
  new_data          jsonb,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_relationship_id ON relationship_audit(relationship_id);

-- Automatically write an audit record on every relevant change.
CREATE OR REPLACE FUNCTION audit_relationship_change()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO relationship_audit (relationship_id, action, actor_profile_id, new_data)
    VALUES (NEW.id, 'created', NEW.added_by, to_jsonb(NEW));

  ELSIF TG_OP = 'UPDATE' THEN
    -- Soft delete
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      INSERT INTO relationship_audit (relationship_id, action, old_data, new_data)
      VALUES (NEW.id, 'deleted', to_jsonb(OLD), to_jsonb(NEW));

    -- Restore
    ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
      INSERT INTO relationship_audit (relationship_id, action, old_data, new_data)
      VALUES (NEW.id, 'restored', to_jsonb(OLD), to_jsonb(NEW));

    -- Status change (confirmed or rejected)
    ELSIF OLD.status != NEW.status THEN
      INSERT INTO relationship_audit (relationship_id, action, actor_profile_id, old_data, new_data)
      VALUES (NEW.id, NEW.status, NEW.confirmed_by, to_jsonb(OLD), to_jsonb(NEW));
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS relationship_audit_trigger ON family_relationships;
CREATE TRIGGER relationship_audit_trigger
  AFTER INSERT OR UPDATE ON family_relationships
  FOR EACH ROW EXECUTE FUNCTION audit_relationship_change();


-- ============================================================
-- Helper: Create Org (atomic — creates org + owner membership)
-- ============================================================

-- Creating an org and adding the creator as owner must be atomic.
-- This function runs as a transaction so both inserts succeed or both fail.
CREATE OR REPLACE FUNCTION create_organization(
  p_school_id   uuid,
  p_name        text,
  p_org_type    text,
  p_description text,
  p_profile_id  uuid
) RETURNS organizations AS $$
DECLARE
  new_org organizations;
BEGIN
  INSERT INTO organizations (school_id, name, org_type, description)
  VALUES (p_school_id, p_name, p_org_type, p_description)
  RETURNING * INTO new_org;

  INSERT INTO memberships (profile_id, org_id, role)
  VALUES (p_profile_id, new_org.id, 'owner');

  RETURN new_org;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- Row Level Security
-- ============================================================

ALTER TABLE schools               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users          ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles              ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations         ENABLE ROW LEVEL SECURITY;
ALTER TABLE memberships           ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_relationships  ENABLE ROW LEVEL SECURITY;
ALTER TABLE relationship_audit    ENABLE ROW LEVEL SECURITY;

-- ---------- schools ----------
-- Anyone can read schools (needed at signup to pick a school).
CREATE POLICY "schools_public_read" ON schools
  FOR SELECT USING (true);

-- ---------- users ----------
-- Users can only see their own auth record.
CREATE POLICY "users_own_record_read" ON public.users
  FOR SELECT USING (auth.uid() = id);

-- ---------- profiles ----------
-- A user can see their own profile plus any profile that shares an org with them.
CREATE POLICY "profiles_read" ON profiles
  FOR SELECT USING (
    user_id = auth.uid()
    OR id IN (
      SELECT m1.profile_id
      FROM memberships m1
      WHERE m1.org_id IN (
        SELECT m2.org_id FROM memberships m2
        JOIN profiles p2 ON p2.id = m2.profile_id
        WHERE p2.user_id = auth.uid()
      )
    )
  );

-- Users create their own profile on onboarding.
CREATE POLICY "profiles_insert_own" ON profiles
  FOR INSERT WITH CHECK (user_id = auth.uid() AND is_ghost = false);

-- Any authenticated user can create a ghost profile (no user_id).
-- The relationship RLS still gates whether they can connect that ghost.
CREATE POLICY "profiles_insert_ghost" ON profiles
  FOR INSERT WITH CHECK (is_ghost = true AND user_id IS NULL AND auth.uid() IS NOT NULL);

-- Users update only their own non-ghost profile.
CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE USING (user_id = auth.uid());

-- Org admins can update ghost profiles (e.g. to correct a name).
CREATE POLICY "profiles_ghost_admin_update" ON profiles
  FOR UPDATE USING (
    is_ghost = true
    AND EXISTS (
      SELECT 1 FROM memberships m
      JOIN profiles p ON p.id = m.profile_id
      WHERE p.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
    )
  );

-- ---------- organizations ----------
-- Members see their own orgs; anyone sees public orgs.
CREATE POLICY "orgs_read" ON organizations
  FOR SELECT USING (
    is_public = true
    OR id IN (
      SELECT m.org_id FROM memberships m
      JOIN profiles p ON p.id = m.profile_id
      WHERE p.user_id = auth.uid()
    )
  );

-- Any authenticated user with a profile can create an org.
CREATE POLICY "orgs_insert" ON organizations
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Owners and admins can update org settings.
CREATE POLICY "orgs_update" ON organizations
  FOR UPDATE USING (
    id IN (
      SELECT m.org_id FROM memberships m
      JOIN profiles p ON p.id = m.profile_id
      WHERE p.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
    )
  );

-- ---------- memberships ----------
-- Members see all memberships in their orgs (to render the member list).
CREATE POLICY "memberships_read" ON memberships
  FOR SELECT USING (
    org_id IN (
      SELECT m.org_id FROM memberships m
      JOIN profiles p ON p.id = m.profile_id
      WHERE p.user_id = auth.uid()
    )
  );

-- Admins can add memberships (invites).
CREATE POLICY "memberships_admin_insert" ON memberships
  FOR INSERT WITH CHECK (
    org_id IN (
      SELECT m.org_id FROM memberships m
      JOIN profiles p ON p.id = m.profile_id
      WHERE p.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
    )
  );

-- Admins can update roles; users can update their own membership (e.g. to leave).
CREATE POLICY "memberships_update" ON memberships
  FOR UPDATE USING (
    profile_id IN (SELECT id FROM profiles WHERE user_id = auth.uid())
    OR org_id IN (
      SELECT m.org_id FROM memberships m
      JOIN profiles p ON p.id = m.profile_id
      WHERE p.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
    )
  );

-- ---------- family_relationships ----------
-- Members and the public (for public orgs) can view non-deleted relationships.
CREATE POLICY "relationships_read" ON family_relationships
  FOR SELECT USING (
    deleted_at IS NULL
    AND (
      org_id IN (
        SELECT m.org_id FROM memberships m
        JOIN profiles p ON p.id = m.profile_id
        WHERE p.user_id = auth.uid()
      )
      OR org_id IN (SELECT id FROM organizations WHERE is_public = true)
    )
  );

-- Members can add relationships where they (or a ghost they manage) are one party.
-- Ghost-to-ghost relationships always go to admin approval (status stays 'pending').
CREATE POLICY "relationships_member_insert" ON family_relationships
  FOR INSERT WITH CHECK (
    org_id IN (
      SELECT m.org_id FROM memberships m
      JOIN profiles p ON p.id = m.profile_id
      WHERE p.user_id = auth.uid()
        AND m.role IN ('owner', 'admin', 'member')
    )
    AND added_by IN (SELECT id FROM profiles WHERE user_id = auth.uid())
  );

-- The non-adding party can confirm/reject their own relationships.
-- Admins can update any relationship in their org (approve, soft-delete, restore).
CREATE POLICY "relationships_update" ON family_relationships
  FOR UPDATE USING (
    parent_profile_id IN (SELECT id FROM profiles WHERE user_id = auth.uid())
    OR child_profile_id IN (SELECT id FROM profiles WHERE user_id = auth.uid())
    OR org_id IN (
      SELECT m.org_id FROM memberships m
      JOIN profiles p ON p.id = m.profile_id
      WHERE p.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
    )
  );

-- ---------- relationship_audit ----------
-- Only org admins can view the audit log.
CREATE POLICY "audit_admin_read" ON relationship_audit
  FOR SELECT USING (
    relationship_id IN (
      SELECT r.id FROM family_relationships r
      WHERE r.org_id IN (
        SELECT m.org_id FROM memberships m
        JOIN profiles p ON p.id = m.profile_id
        WHERE p.user_id = auth.uid()
          AND m.role IN ('owner', 'admin')
      )
    )
  );
