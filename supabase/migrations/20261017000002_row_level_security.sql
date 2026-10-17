-- Migration: 20261017000002_row_level_security.sql
-- Description: Strict Row Level Security policies matching ARCHITECTURE.md Sec 13.1 + Addendum

-- Helper functions
CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS user_role AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_owner()
RETURNS BOOLEAN AS $$
    SELECT COALESCE((public.get_current_user_role() = 'owner'), false);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Enable RLS on every table
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE dial_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_call_log_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE reasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispositions ENABLE ROW LEVEL SECURITY;
ALTER TABLE follow_ups ENABLE ROW LEVEL SECURITY;
ALTER TABLE flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

--------------------------------------------------------------------------------
-- PROFILES POLICIES
--------------------------------------------------------------------------------
-- Owners have full access to all profiles
CREATE POLICY "Owners full access on profiles"
    ON profiles FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- Callers can read their own profile
CREATE POLICY "Callers can view own profile"
    ON profiles FOR SELECT
    TO authenticated
    USING (id = auth.uid());

-- Callers can update their own non-sensitive profile info (cannot alter role or id)
CREATE POLICY "Callers can update own profile"
    ON profiles FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid() AND role = (SELECT role FROM profiles WHERE id = auth.uid()));

--------------------------------------------------------------------------------
-- LEAD BATCHES POLICIES
--------------------------------------------------------------------------------
-- Only owners can manage lead batches
CREATE POLICY "Owners full access on lead_batches"
    ON lead_batches FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

--------------------------------------------------------------------------------
-- LEADS POLICIES
--------------------------------------------------------------------------------
-- Owners can do everything on leads
CREATE POLICY "Owners full access on leads"
    ON leads FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- Callers can ONLY SELECT leads assigned directly to them
CREATE POLICY "Callers can only view assigned leads"
    ON leads FOR SELECT
    TO authenticated
    USING (assigned_to = auth.uid());

-- Callers have NO direct INSERT, UPDATE, or DELETE on leads.
-- Lead status transitions occur via verified server functions.

--------------------------------------------------------------------------------
-- DEVICES POLICIES
--------------------------------------------------------------------------------
-- Owners can view and manage all devices
CREATE POLICY "Owners full access on devices"
    ON devices FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- Callers can view their own devices
CREATE POLICY "Callers can view own devices"
    ON devices FOR SELECT
    TO authenticated
    USING (profile_id = auth.uid());

-- Callers can register/update their own device
CREATE POLICY "Callers can insert own devices"
    ON devices FOR INSERT
    TO authenticated
    WITH CHECK (profile_id = auth.uid());

CREATE POLICY "Callers can update own devices"
    ON devices FOR UPDATE
    TO authenticated
    USING (profile_id = auth.uid())
    WITH CHECK (profile_id = auth.uid());

--------------------------------------------------------------------------------
-- DIAL ATTEMPTS POLICIES
--------------------------------------------------------------------------------
-- Owners can manage all dial attempts
CREATE POLICY "Owners full access on dial_attempts"
    ON dial_attempts FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- Callers can view their own dial attempts
CREATE POLICY "Callers can view own dial_attempts"
    ON dial_attempts FOR SELECT
    TO authenticated
    USING (caller_id = auth.uid());

-- Callers can insert their own dial attempts (subject to one open attempt unique index)
CREATE POLICY "Callers can insert own dial_attempts"
    ON dial_attempts FOR INSERT
    TO authenticated
    WITH CHECK (caller_id = auth.uid());

--------------------------------------------------------------------------------
-- DEVICE CALL LOG ENTRIES POLICIES
--------------------------------------------------------------------------------
-- Owners can view all call log entries
CREATE POLICY "Owners full access on device_call_log_entries"
    ON device_call_log_entries FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- Callers can only view their own uploaded call log entries
CREATE POLICY "Callers can view own device_call_log_entries"
    ON device_call_log_entries FOR SELECT
    TO authenticated
    USING (device_id IN (SELECT id FROM devices WHERE profile_id = auth.uid()));

-- Callers CANNOT write directly to device_call_log_entries via client SDK.
-- All inserts must occur through secure Edge Functions / RPC with service role.

--------------------------------------------------------------------------------
-- CALLS POLICIES
--------------------------------------------------------------------------------
-- Owners have full access to all calls
CREATE POLICY "Owners full access on calls"
    ON calls FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- Callers can view only their own calls
CREATE POLICY "Callers can view own calls"
    ON calls FOR SELECT
    TO authenticated
    USING (caller_id = auth.uid());

-- Callers CANNOT directly INSERT, UPDATE, or DELETE calls.

--------------------------------------------------------------------------------
-- REASONS POLICIES
--------------------------------------------------------------------------------
-- All authenticated users can view active reasons
CREATE POLICY "Authenticated users can view active reasons"
    ON reasons FOR SELECT
    TO authenticated
    USING (is_active = true OR public.is_owner());

-- Only owners can insert, update, or delete reasons
CREATE POLICY "Owners can manage reasons"
    ON reasons FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

--------------------------------------------------------------------------------
-- DISPOSITIONS POLICIES
--------------------------------------------------------------------------------
-- Owners can view all dispositions
CREATE POLICY "Owners can view all dispositions"
    ON dispositions FOR SELECT
    TO authenticated
    USING (public.is_owner());

-- Callers can view only their own dispositions
CREATE POLICY "Callers can view own dispositions"
    ON dispositions FOR SELECT
    TO authenticated
    USING (caller_id = auth.uid());

-- Callers CANNOT directly INSERT, UPDATE, or DELETE dispositions.
-- Dispositions are immutable and created only via verified server Edge Function / RPC.

--------------------------------------------------------------------------------
-- FOLLOW-UPS POLICIES
--------------------------------------------------------------------------------
-- Owners have full access to follow-ups
CREATE POLICY "Owners full access on follow_ups"
    ON follow_ups FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- Callers can view their assigned follow-ups
CREATE POLICY "Callers can view assigned follow_ups"
    ON follow_ups FOR SELECT
    TO authenticated
    USING (assigned_to = auth.uid());

-- Callers can update their assigned follow-ups (e.g. mark done)
CREATE POLICY "Callers can update assigned follow_ups"
    ON follow_ups FOR UPDATE
    TO authenticated
    USING (assigned_to = auth.uid())
    WITH CHECK (assigned_to = auth.uid());

--------------------------------------------------------------------------------
-- FLAGS POLICIES
--------------------------------------------------------------------------------
-- Only owners can view and manage verification flags
CREATE POLICY "Owners full access on flags"
    ON flags FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

--------------------------------------------------------------------------------
-- AUDIT LOG POLICIES
--------------------------------------------------------------------------------
-- Only owners can view audit logs. Nobody can write directly via client.
CREATE POLICY "Owners can view audit_log"
    ON audit_log FOR SELECT
    TO authenticated
    USING (public.is_owner());

--------------------------------------------------------------------------------
-- SETTINGS POLICIES
--------------------------------------------------------------------------------
-- All authenticated users can view settings (e.g. min talk seconds, calling hours)
CREATE POLICY "Authenticated users can view settings"
    ON settings FOR SELECT
    TO authenticated
    USING (true);

-- Only owners can modify settings
CREATE POLICY "Owners can manage settings"
    ON settings FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());
