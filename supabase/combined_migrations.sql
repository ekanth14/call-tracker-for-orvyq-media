-- ============================================================================
-- ORVYQMEDIA COLD-CALLING TRACKER: COMBINED MIGRATIONS (PHASE 0 & PHASE 1)
-- Run this in Supabase Dashboard SQL Editor or via `supabase db push`
-- ============================================================================

-- ============================================================================
-- PART 1: INITIAL SCHEMA (20261017000001_initial_schema.sql)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enums
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('owner', 'manager', 'caller');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'lead_status') THEN
        CREATE TYPE lead_status AS ENUM ('new', 'assigned', 'in_progress', 'called', 'interested', 'not_interested', 'follow_up', 'unreachable', 'do_not_call');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'dnd_status') THEN
        CREATE TYPE dnd_status AS ENUM ('unknown', 'clear', 'registered');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'call_source') THEN
        CREATE TYPE call_source AS ENUM ('device_log', 'provider');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'call_status') THEN
        CREATE TYPE call_status AS ENUM (
            'initiated',
            'caller_ringing',
            'caller_no_answer',
            'client_ringing',
            'connected',
            'client_no_answer',
            'client_busy',
            'failed',
            'completed',
            'awaiting_disposition',
            'closed'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'dial_attempt_status') THEN
        CREATE TYPE dial_attempt_status AS ENUM ('open', 'matched', 'no_call_detected', 'closed');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'device_call_type') THEN
        CREATE TYPE device_call_type AS ENUM ('outgoing', 'incoming', 'missed');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'disposition_outcome') THEN
        CREATE TYPE disposition_outcome AS ENUM ('interested', 'not_interested', 'not_connected');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'follow_up_type') THEN
        CREATE TYPE follow_up_type AS ENUM ('callback', 'proposal', 'demo', 'meeting');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'follow_up_status') THEN
        CREATE TYPE follow_up_status AS ENUM ('open', 'done', 'cancelled');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'flag_severity') THEN
        CREATE TYPE flag_severity AS ENUM ('info', 'warn', 'high');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'flag_status') THEN
        CREATE TYPE flag_status AS ENUM ('open', 'dismissed', 'confirmed');
    END IF;
END $$;

-- Profiles table (linked to auth.users)
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'caller',
    email TEXT,
    mobile_e164 TEXT UNIQUE,
    mobile_verified_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Lead Batches
CREATE TABLE IF NOT EXISTS lead_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    source TEXT,
    created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Leads
CREATE TABLE IF NOT EXISTS leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id UUID REFERENCES lead_batches(id) ON DELETE SET NULL,
    phone_e164 TEXT NOT NULL UNIQUE,
    name TEXT,
    company TEXT,
    notes TEXT,
    assigned_to UUID REFERENCES profiles(id) ON DELETE SET NULL,
    assigned_at TIMESTAMPTZ,
    status lead_status NOT NULL DEFAULT 'new',
    dnd_status dnd_status NOT NULL DEFAULT 'unknown',
    attempt_count INT NOT NULL DEFAULT 0,
    last_call_at TIMESTAMPTZ,
    next_follow_up_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Devices (Addendum Sec 7)
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    device_label TEXT,
    app_version TEXT,
    last_sync_at TIMESTAMPTZ,
    permissions_ok BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Dial Attempts (Addendum Sec 7)
CREATE TABLE IF NOT EXISTS dial_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    caller_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    dialed_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    status dial_attempt_status NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Partial index: at most one open dial attempt per caller (Call Lock)
CREATE UNIQUE INDEX IF NOT EXISTS one_open_dial_attempt_per_caller 
    ON dial_attempts(caller_id) 
    WHERE status = 'open';

-- Device Call Log Entries (Addendum Sec 7, append-only)
CREATE TABLE IF NOT EXISTS device_call_log_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dial_attempt_id UUID REFERENCES dial_attempts(id) ON DELETE SET NULL,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    number_e164 TEXT NOT NULL,
    call_type device_call_type NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    duration_secs INT NOT NULL DEFAULT 0,
    sim_slot TEXT,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    clock_skew_secs INT NOT NULL DEFAULT 0,
    dedupe_key TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Calls (Unified with Addendum: source = device_log default, provider columns nullable)
CREATE TABLE IF NOT EXISTS calls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    caller_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    device_call_log_entry_id UUID REFERENCES device_call_log_entries(id) ON DELETE SET NULL,
    source call_source NOT NULL DEFAULT 'device_log',
    provider TEXT,
    provider_call_id TEXT UNIQUE,
    virtual_number TEXT,
    status call_status NOT NULL DEFAULT 'initiated',
    initiated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    caller_answered_at TIMESTAMPTZ,
    client_answered_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    caller_leg_secs INT,
    client_leg_secs INT,
    talk_secs INT NOT NULL DEFAULT 0,
    end_reason TEXT,
    recording_path TEXT,
    cost_estimate NUMERIC,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Reasons (Owner configurable)
CREATE TABLE IF NOT EXISTS reasons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    outcome disposition_outcome NOT NULL,
    label TEXT NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Dispositions (One per closed call, immutable once saved)
CREATE TABLE IF NOT EXISTS dispositions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id UUID NOT NULL UNIQUE REFERENCES calls(id) ON DELETE CASCADE,
    lead_id UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    caller_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    connected BOOLEAN NOT NULL,
    caller_claimed_connected BOOLEAN,
    outcome disposition_outcome NOT NULL,
    reason_ids UUID[] NOT NULL DEFAULT '{}',
    other_reason_text TEXT,
    note TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    seconds_after_call_end INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Follow-ups
CREATE TABLE IF NOT EXISTS follow_ups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    assigned_to UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    due_at TIMESTAMPTZ NOT NULL,
    type follow_up_type NOT NULL,
    status follow_up_status NOT NULL DEFAULT 'open',
    source_disposition_id UUID REFERENCES dispositions(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Flags (Verification & anomaly flags)
CREATE TABLE IF NOT EXISTS flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id UUID REFERENCES calls(id) ON DELETE SET NULL,
    caller_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    dial_attempt_id UUID REFERENCES dial_attempts(id) ON DELETE SET NULL,
    rule_code TEXT NOT NULL,
    severity flag_severity NOT NULL DEFAULT 'warn',
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    status flag_status NOT NULL DEFAULT 'open',
    reviewed_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    review_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Audit Log (append-only)
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    before_state JSONB,
    after_state JSONB,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Settings
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_leads_assigned_status ON leads(assigned_to, status);
CREATE INDEX IF NOT EXISTS idx_leads_phone ON leads(phone_e164);
CREATE INDEX IF NOT EXISTS idx_calls_caller_initiated ON calls(caller_id, initiated_at DESC);
CREATE INDEX IF NOT EXISTS idx_calls_lead ON calls(lead_id);
CREATE INDEX IF NOT EXISTS idx_dispositions_submitted ON dispositions(submitted_at);
CREATE INDEX IF NOT EXISTS idx_device_call_log_device ON device_call_log_entries(device_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_flags_status_severity ON flags(status, severity);
CREATE INDEX IF NOT EXISTS idx_dial_attempts_caller_status ON dial_attempts(caller_id, status);

-- Trigger: Immutability for dispositions
CREATE OR REPLACE FUNCTION prevent_disposition_update_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Dispositions are immutable and cannot be updated or deleted.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_dispositions_immutable ON dispositions;
CREATE TRIGGER trg_dispositions_immutable
    BEFORE UPDATE OR DELETE ON dispositions
    FOR EACH ROW
    EXECUTE FUNCTION prevent_disposition_update_delete();

-- Trigger: Immutability for audit_log
CREATE OR REPLACE FUNCTION prevent_audit_log_update_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit log entries are immutable.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_log_immutable ON audit_log;
CREATE TRIGGER trg_audit_log_immutable
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW
    EXECUTE FUNCTION prevent_audit_log_update_delete();

-- ============================================================================
-- PART 2: ROW LEVEL SECURITY (20261017000002_row_level_security.sql)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS user_role AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_owner()
RETURNS BOOLEAN AS $$
    SELECT COALESCE((public.get_current_user_role() = 'owner'), false);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Enable RLS
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

-- Clean existing policies for idempotency
DO $$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT policyname, tablename 
        FROM pg_policies 
        WHERE schemaname = 'public'
    ) LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', r.policyname, r.tablename);
    END LOOP;
END $$;

-- PROFILES POLICIES
CREATE POLICY "Owners full access on profiles"
    ON profiles FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

CREATE POLICY "Callers can view own profile"
    ON profiles FOR SELECT
    TO authenticated
    USING (id = auth.uid());

CREATE POLICY "Callers can update own profile"
    ON profiles FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid() AND role = (SELECT role FROM profiles WHERE id = auth.uid()));

-- LEAD BATCHES POLICIES
CREATE POLICY "Owners full access on lead_batches"
    ON lead_batches FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- LEADS POLICIES
CREATE POLICY "Owners full access on leads"
    ON leads FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

CREATE POLICY "Callers can only view assigned leads"
    ON leads FOR SELECT
    TO authenticated
    USING (assigned_to = auth.uid());

-- DEVICES POLICIES
CREATE POLICY "Owners full access on devices"
    ON devices FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

CREATE POLICY "Callers can view own devices"
    ON devices FOR SELECT
    TO authenticated
    USING (profile_id = auth.uid());

CREATE POLICY "Callers can insert own devices"
    ON devices FOR INSERT
    TO authenticated
    WITH CHECK (profile_id = auth.uid());

CREATE POLICY "Callers can update own devices"
    ON devices FOR UPDATE
    TO authenticated
    USING (profile_id = auth.uid())
    WITH CHECK (profile_id = auth.uid());

-- DIAL ATTEMPTS POLICIES
CREATE POLICY "Owners full access on dial_attempts"
    ON dial_attempts FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

CREATE POLICY "Callers can view own dial_attempts"
    ON dial_attempts FOR SELECT
    TO authenticated
    USING (caller_id = auth.uid());

CREATE POLICY "Callers can insert own dial_attempts"
    ON dial_attempts FOR INSERT
    TO authenticated
    WITH CHECK (caller_id = auth.uid());

-- DEVICE CALL LOG ENTRIES POLICIES
CREATE POLICY "Owners full access on device_call_log_entries"
    ON device_call_log_entries FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

CREATE POLICY "Callers can view own device_call_log_entries"
    ON device_call_log_entries FOR SELECT
    TO authenticated
    USING (device_id IN (SELECT id FROM devices WHERE profile_id = auth.uid()));

-- CALLS POLICIES
CREATE POLICY "Owners full access on calls"
    ON calls FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

CREATE POLICY "Callers can view own calls"
    ON calls FOR SELECT
    TO authenticated
    USING (caller_id = auth.uid());

-- REASONS POLICIES
CREATE POLICY "Authenticated users can view active reasons"
    ON reasons FOR SELECT
    TO authenticated
    USING (is_active = true OR public.is_owner());

CREATE POLICY "Owners can manage reasons"
    ON reasons FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- DISPOSITIONS POLICIES
CREATE POLICY "Owners can view all dispositions"
    ON dispositions FOR SELECT
    TO authenticated
    USING (public.is_owner());

CREATE POLICY "Callers can view own dispositions"
    ON dispositions FOR SELECT
    TO authenticated
    USING (caller_id = auth.uid());

-- FOLLOW-UPS POLICIES
CREATE POLICY "Owners full access on follow_ups"
    ON follow_ups FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

CREATE POLICY "Callers can view assigned follow_ups"
    ON follow_ups FOR SELECT
    TO authenticated
    USING (assigned_to = auth.uid());

CREATE POLICY "Callers can update assigned follow_ups"
    ON follow_ups FOR UPDATE
    TO authenticated
    USING (assigned_to = auth.uid())
    WITH CHECK (assigned_to = auth.uid());

-- FLAGS POLICIES
CREATE POLICY "Owners full access on flags"
    ON flags FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- AUDIT LOG POLICIES
CREATE POLICY "Owners can view audit_log"
    ON audit_log FOR SELECT
    TO authenticated
    USING (public.is_owner());

-- SETTINGS POLICIES
CREATE POLICY "Authenticated users can view settings"
    ON settings FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Owners can manage settings"
    ON settings FOR ALL
    TO authenticated
    USING (public.is_owner())
    WITH CHECK (public.is_owner());

-- ============================================================================
-- PART 3: SEED REASONS & SETTINGS (20261017000003_seed_reasons.sql)
-- ============================================================================

INSERT INTO settings (key, value, description) VALUES
    ('min_talk_seconds', '10'::jsonb, 'Minimum call duration in seconds to count as connected'),
    ('daily_attempt_limit', '3'::jsonb, 'Maximum call attempts per lead per day'),
    ('calling_hours', '{"start": "09:00", "end": "19:00", "timezone": "Asia/Kolkata"}'::jsonb, 'Configured outbound calling hours window'),
    ('flag_thresholds', '{"short_call_sec": 10, "clock_skew_sec": 120, "slow_dialog_sec": 300}'::jsonb, 'Verification thresholds for automated anomaly detection')
ON CONFLICT (key) DO UPDATE SET
    value = EXCLUDED.value,
    description = EXCLUDED.description,
    updated_at = timezone('utc'::text, now());

-- Seed Default Reasons (Section 10.2)
DELETE FROM reasons;

-- Interested Reasons
INSERT INTO reasons (outcome, label, sort_order, is_active) VALUES
    ('interested', 'Wants pricing / proposal', 1, true),
    ('interested', 'Wants a demo or meeting', 2, true),
    ('interested', 'Needs to discuss with team or partner', 3, true),
    ('interested', 'Currently looking for influencer marketing', 4, true),
    ('interested', 'Asked for a callback at a specific time', 5, true),
    ('interested', 'Referred to another decision maker', 6, true);

-- Not Interested Reasons
INSERT INTO reasons (outcome, label, sort_order, is_active) VALUES
    ('not_interested', 'Budget constraints', 1, true),
    ('not_interested', 'Already has an agency or in-house team', 2, true),
    ('not_interested', 'No need right now', 3, true),
    ('not_interested', 'Bad timing, try later', 4, true),
    ('not_interested', 'Not the decision maker, no referral', 5, true),
    ('not_interested', 'Unhappy with influencer marketing', 6, true),
    ('not_interested', 'Asked not to be contacted again', 7, true);

-- Not Connected Reasons
INSERT INTO reasons (outcome, label, sort_order, is_active) VALUES
    ('not_connected', 'No answer', 1, true),
    ('not_connected', 'Busy', 2, true),
    ('not_connected', 'Switched off or unreachable', 3, true),
    ('not_connected', 'Wrong or invalid number', 4, true),
    ('not_connected', 'Voicemail', 5, true),
    ('not_connected', 'Call dropped', 6, true);

-- ============================================================================
-- PART 4: FUNCTIONS & TRIGGERS (20261017000004_functions_and_triggers.sql)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    INSERT INTO public.profiles (
        id,
        full_name,
        email,
        role,
        mobile_e164,
        is_active
    ) VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        NEW.email,
        COALESCE((NEW.raw_user_meta_data->>'role')::public.user_role, 'caller'::public.user_role),
        NULLIF(NEW.raw_user_meta_data->>'mobile_e164', ''),
        true
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        email = EXCLUDED.email,
        updated_at = timezone('utc'::text, now());

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT OR UPDATE OF email, raw_user_meta_data ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Secure RPC to start a Dial Attempt (Enforces Call Lock & Assignment)
CREATE OR REPLACE FUNCTION public.start_dial_attempt(
    p_lead_id UUID,
    p_device_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_caller_id UUID;
    v_lead RECORD;
    v_open_attempt_id UUID;
    v_new_attempt_id UUID;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Check if caller already has an open dial attempt (Call Lock)
    SELECT id INTO v_open_attempt_id
    FROM dial_attempts
    WHERE caller_id = v_caller_id AND status = 'open'
    LIMIT 1;

    IF v_open_attempt_id IS NOT NULL THEN
        RAISE EXCEPTION 'CALL_LOCKED: You have an open dial attempt (%) awaiting completion.', v_open_attempt_id;
    END IF;

    -- Check lead exists and is assigned to caller (or caller is owner)
    SELECT * INTO v_lead
    FROM leads
    WHERE id = p_lead_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead not found.';
    END IF;

    IF v_lead.status = 'do_not_call' THEN
        RAISE EXCEPTION 'Lead is marked as Do Not Call.';
    END IF;

    IF v_lead.assigned_to != v_caller_id AND NOT public.is_owner() THEN
        RAISE EXCEPTION 'Lead is not assigned to you.';
    END IF;

    -- Insert dial attempt
    INSERT INTO dial_attempts (
        lead_id,
        caller_id,
        device_id,
        dialed_at,
        status
    ) VALUES (
        p_lead_id,
        v_caller_id,
        p_device_id,
        timezone('utc'::text, now()),
        'open'
    )
    RETURNING id INTO v_new_attempt_id;

    -- Update lead status to in_progress if currently assigned
    IF v_lead.status = 'assigned' OR v_lead.status = 'new' THEN
        UPDATE leads SET status = 'in_progress', updated_at = timezone('utc'::text, now()) WHERE id = p_lead_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'dial_attempt_id', v_new_attempt_id,
        'phone_e164', v_lead.phone_e164
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Secure RPC to submit Matched Call Log Entry + Post-Call Dialog
CREATE OR REPLACE FUNCTION public.submit_call_dialog(
    p_dial_attempt_id UUID,
    p_device_id UUID,
    p_number_e164 TEXT,
    p_call_type device_call_type,
    p_started_at TIMESTAMPTZ,
    p_duration_secs INT,
    p_sim_slot TEXT,
    p_clock_skew_secs INT,
    p_caller_claimed_connected BOOLEAN,
    p_outcome disposition_outcome,
    p_reason_ids UUID[],
    p_other_reason_text TEXT DEFAULT NULL,
    p_note TEXT DEFAULT NULL,
    p_seconds_after_call_end INT DEFAULT NULL,
    p_follow_up_due_at TIMESTAMPTZ DEFAULT NULL,
    p_follow_up_type follow_up_type DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_caller_id UUID;
    v_attempt RECORD;
    v_min_talk_secs INT;
    v_connected BOOLEAN;
    v_dedupe_key TEXT;
    v_log_entry_id UUID;
    v_call_id UUID;
    v_disp_id UUID;
    v_new_lead_status lead_status;
    v_has_dnc_reason BOOLEAN := false;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT * INTO v_attempt
    FROM dial_attempts
    WHERE id = p_dial_attempt_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dial attempt not found.';
    END IF;

    IF v_attempt.caller_id != v_caller_id AND NOT public.is_owner() THEN
        RAISE EXCEPTION 'Dial attempt does not belong to you.';
    END IF;

    SELECT COALESCE((value)::int, 10) INTO v_min_talk_secs
    FROM settings
    WHERE key = 'min_talk_seconds';
    IF v_min_talk_secs IS NULL THEN v_min_talk_secs := 10; END IF;

    -- Evaluate connected status (Addendum Sec 5.1 & user override: 10s min)
    v_connected := (p_call_type = 'outgoing' AND p_duration_secs >= v_min_talk_secs);

    IF NOT v_connected AND p_outcome = 'interested' THEN
        RAISE EXCEPTION 'Cannot claim interested on a call that did not connect.';
    END IF;

    -- 1. Insert into device_call_log_entries (deduped)
    v_dedupe_key := p_device_id::text || '_' || p_number_e164 || '_' || extract(epoch from p_started_at)::text || '_' || p_duration_secs::text;
    
    INSERT INTO device_call_log_entries (
        dial_attempt_id,
        device_id,
        number_e164,
        call_type,
        started_at,
        duration_secs,
        sim_slot,
        uploaded_at,
        clock_skew_secs,
        dedupe_key
    ) VALUES (
        p_dial_attempt_id,
        p_device_id,
        p_number_e164,
        p_call_type,
        p_started_at,
        p_duration_secs,
        p_sim_slot,
        timezone('utc'::text, now()),
        p_clock_skew_secs,
        v_dedupe_key
    )
    ON CONFLICT (dedupe_key) DO UPDATE SET
        dial_attempt_id = EXCLUDED.dial_attempt_id
    RETURNING id INTO v_log_entry_id;

    -- 2. Insert into calls
    INSERT INTO calls (
        lead_id,
        caller_id,
        device_id,
        device_call_log_entry_id,
        source,
        status,
        initiated_at,
        ended_at,
        talk_secs
    ) VALUES (
        v_attempt.lead_id,
        v_caller_id,
        p_device_id,
        v_log_entry_id,
        'device_log',
        'closed',
        v_attempt.dialed_at,
        p_started_at + (p_duration_secs * interval '1 second'),
        p_duration_secs
    )
    RETURNING id INTO v_call_id;

    -- 3. Insert immutable disposition
    INSERT INTO dispositions (
        call_id,
        lead_id,
        caller_id,
        connected,
        caller_claimed_connected,
        outcome,
        reason_ids,
        other_reason_text,
        note,
        submitted_at,
        seconds_after_call_end
    ) VALUES (
        v_call_id,
        v_attempt.lead_id,
        v_caller_id,
        v_connected,
        p_caller_claimed_connected,
        p_outcome,
        p_reason_ids,
        p_other_reason_text,
        p_note,
        timezone('utc'::text, now()),
        p_seconds_after_call_end
    )
    RETURNING id INTO v_disp_id;

    -- Check if DNC reason selected
    SELECT EXISTS (
        SELECT 1 FROM reasons 
        WHERE id = ANY(p_reason_ids) AND label ILIKE '%not to be contacted%'
    ) INTO v_has_dnc_reason;

    IF v_has_dnc_reason THEN
        v_new_lead_status := 'do_not_call';
    ELSIF p_outcome = 'interested' THEN
        IF p_follow_up_due_at IS NOT NULL THEN
            v_new_lead_status := 'follow_up';
        ELSE
            v_new_lead_status := 'interested';
        END IF;
    ELSIF p_outcome = 'not_interested' THEN
        v_new_lead_status := 'not_interested';
    ELSE
        v_new_lead_status := 'called';
    END IF;

    -- 4. Update Lead
    UPDATE leads SET
        status = v_new_lead_status,
        attempt_count = attempt_count + 1,
        last_call_at = timezone('utc'::text, now()),
        next_follow_up_at = p_follow_up_due_at,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_attempt.lead_id;

    -- 5. Insert Follow-up if scheduled
    IF p_outcome = 'interested' AND p_follow_up_due_at IS NOT NULL AND p_follow_up_type IS NOT NULL THEN
        INSERT INTO follow_ups (
            lead_id,
            assigned_to,
            due_at,
            type,
            status,
            source_disposition_id,
            notes
        ) VALUES (
            v_attempt.lead_id,
            v_caller_id,
            p_follow_up_due_at,
            p_follow_up_type,
            'open',
            v_disp_id,
            p_note
        );
    END IF;

    -- 6. Close the dial attempt
    UPDATE dial_attempts SET
        status = 'closed',
        updated_at = timezone('utc'::text, now())
    WHERE id = p_dial_attempt_id;

    -- 7. Verification Flags
    IF p_caller_claimed_connected AND NOT v_connected THEN
        INSERT INTO flags (call_id, caller_id, dial_attempt_id, rule_code, severity, details)
        VALUES (v_call_id, v_caller_id, p_dial_attempt_id, 'CLAIM_MISMATCH', 'high', 
            jsonb_build_object('claimed', true, 'duration_secs', p_duration_secs, 'min_threshold', v_min_talk_secs));
    END IF;

    IF p_outcome = 'interested' AND p_duration_secs < v_min_talk_secs THEN
        INSERT INTO flags (call_id, caller_id, dial_attempt_id, rule_code, severity, details)
        VALUES (v_call_id, v_caller_id, p_dial_attempt_id, 'SHORT_INTERESTED', 'warn',
            jsonb_build_object('duration_secs', p_duration_secs, 'outcome', 'interested'));
    END IF;

    IF abs(p_clock_skew_secs) > 120 THEN
        INSERT INTO flags (call_id, caller_id, dial_attempt_id, rule_code, severity, details)
        VALUES (v_call_id, v_caller_id, p_dial_attempt_id, 'CLOCK_SKEW', 'high',
            jsonb_build_object('skew_secs', p_clock_skew_secs));
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'call_id', v_call_id,
        'disposition_id', v_disp_id,
        'connected', v_connected,
        'status', 'closed'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- PART 6: CORPORATE FEATURES (20261018_corporate_features.sql)
-- ============================================================================

-- 1. Community Team Chatbox
CREATE TABLE IF NOT EXISTS public.team_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    sender_name TEXT NOT NULL,
    sender_role TEXT NOT NULL DEFAULT 'caller',
    content TEXT NOT NULL,
    is_announcement BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_team_messages_created_at ON public.team_messages(created_at DESC);

ALTER TABLE public.team_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "team_messages_select_authenticated"
ON public.team_messages FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "team_messages_insert_own"
ON public.team_messages FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "team_messages_delete_owner"
ON public.team_messages FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role = 'owner'
    )
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'team_messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.team_messages;
    END IF;
END $$;

-- 2. Employee Profile Self-Update Policy
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (
    auth.uid() = id
    AND (
        (role = (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid()) 
         AND is_active = (SELECT p.is_active FROM public.profiles p WHERE p.id = auth.uid()))
        OR (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid()) = 'owner'
    )
);

-- 3. Mandatory 2-Hour Daily Work Quota (Interpretation A)
CREATE TABLE IF NOT EXISTS public.caller_work_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    session_date DATE NOT NULL DEFAULT CURRENT_DATE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_caller_work_sessions_caller_date 
ON public.caller_work_sessions(caller_id, session_date);

ALTER TABLE public.caller_work_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "caller_work_sessions_select"
ON public.caller_work_sessions FOR SELECT
TO authenticated
USING (
    auth.uid() = caller_id 
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'owner')
);

CREATE POLICY "caller_work_sessions_insert"
ON public.caller_work_sessions FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = caller_id);

CREATE POLICY "caller_work_sessions_update"
ON public.caller_work_sessions FOR UPDATE
TO authenticated
USING (auth.uid() = caller_id)
WITH CHECK (auth.uid() = caller_id);

CREATE OR REPLACE FUNCTION public.clock_in()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_session_id UUID;
    v_active_session RECORD;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT * INTO v_active_session
    FROM public.caller_work_sessions
    WHERE caller_id = v_caller_id 
      AND session_date = CURRENT_DATE 
      AND is_active = TRUE
    ORDER BY started_at DESC
    LIMIT 1;

    IF FOUND THEN
        RETURN json_build_object(
            'success', true, 
            'session_id', v_active_session.id, 
            'message', 'Resumed existing session',
            'started_at', v_active_session.started_at
        );
    END IF;

    INSERT INTO public.caller_work_sessions (caller_id, session_date, started_at, is_active)
    VALUES (v_caller_id, CURRENT_DATE, now(), TRUE)
    RETURNING id INTO v_session_id;

    RETURN json_build_object(
        'success', true, 
        'session_id', v_session_id, 
        'message', 'Clocked in successfully',
        'started_at', now()
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.clock_out(p_session_id UUID)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_duration INTEGER;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    UPDATE public.caller_work_sessions
    SET 
        ended_at = now(),
        duration_seconds = GREATEST(0, EXTRACT(EPOCH FROM (now() - started_at))::INTEGER),
        is_active = FALSE
    WHERE id = p_session_id AND caller_id = v_caller_id
    RETURNING duration_seconds INTO v_duration;

    RETURN json_build_object(
        'success', true, 
        'duration_seconds', COALESCE(v_duration, 0),
        'message', 'Clocked out successfully'
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_daily_caller_quota(p_caller_id UUID DEFAULT NULL, p_date DATE DEFAULT CURRENT_DATE)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_target_caller_id UUID := COALESCE(p_caller_id, auth.uid());
    v_active_seconds INTEGER := 0;
    v_talk_seconds INTEGER := 0;
    v_target_seconds CONSTANT INTEGER := 7200;
    v_progress_pct NUMERIC;
    v_is_clocked_in BOOLEAN := FALSE;
    v_current_session_id UUID;
    v_active_session RECORD;
BEGIN
    IF v_target_caller_id IS NULL THEN
        RAISE EXCEPTION 'Caller ID required';
    END IF;

    SELECT COALESCE(SUM(duration_seconds), 0)
    INTO v_active_seconds
    FROM public.caller_work_sessions
    WHERE caller_id = v_target_caller_id 
      AND session_date = p_date 
      AND is_active = FALSE;

    SELECT id, started_at INTO v_active_session
    FROM public.caller_work_sessions
    WHERE caller_id = v_target_caller_id 
      AND session_date = p_date 
      AND is_active = TRUE
    ORDER BY started_at DESC
    LIMIT 1;

    IF FOUND THEN
        v_is_clocked_in := TRUE;
        v_current_session_id := v_active_session.id;
        v_active_seconds := v_active_seconds + GREATEST(0, EXTRACT(EPOCH FROM (now() - v_active_session.started_at))::INTEGER);
    END IF;

    SELECT COALESCE(SUM(actual_duration_seconds), 0)
    INTO v_talk_seconds
    FROM public.calls
    WHERE caller_id = v_target_caller_id 
      AND started_at::DATE = p_date;

    v_progress_pct := ROUND(LEAST(100.0, (v_active_seconds::NUMERIC / v_target_seconds::NUMERIC) * 100), 1);

    RETURN json_build_object(
        'caller_id', v_target_caller_id,
        'date', p_date,
        'active_seconds', v_active_seconds,
        'talk_seconds', v_talk_seconds,
        'target_seconds', v_target_seconds,
        'progress_pct', v_progress_pct,
        'quota_met', (v_active_seconds >= v_target_seconds),
        'is_clocked_in', v_is_clocked_in,
        'current_session_id', v_current_session_id
    );
END;
$$;

-- 4. Corporate Pitch Scripts & Objection Cheat-Sheet
CREATE TABLE IF NOT EXISTS public.pitch_scripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('pitch', 'objection', 'closing')),
    lead_stage TEXT NOT NULL DEFAULT 'general',
    content TEXT NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.pitch_scripts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pitch_scripts_select_all"
ON public.pitch_scripts FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "pitch_scripts_owner_modify"
ON public.pitch_scripts FOR ALL
TO authenticated
USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'owner'))
WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'owner'));

INSERT INTO public.pitch_scripts (title, category, lead_stage, content, display_order)
VALUES
(
    'Elevator Pitch Opener',
    'pitch',
    'cold',
    'Hi [Lead Name], this is [Caller Name] from Orvyq Media. I noticed your recent work in [City/Field], and I''m reaching out because we help companies like yours increase qualified leads by 3x without increasing ad spend. Do you have 60 seconds for a quick intro?',
    1
),
(
    'Objection: "Not Interested Right Now"',
    'objection',
    'cold',
    'I completely understand, [Lead Name]. Most of our current high-performing clients said the exact same thing before seeing our 5-minute case study. Would you be open to just seeing how we increased conversions for similar brands, with zero commitment?',
    2
),
(
    'Objection: "Send Me an Email / Brochure"',
    'objection',
    'cold',
    'I''d love to send that over! So I don''t clutter your inbox with irrelevant slides, what is the single biggest priority your team is trying to solve this month?',
    3
),
(
    'Objection: "Already Working with an Agency"',
    'objection',
    'cold',
    'That''s fantastic! We actually work alongside existing teams as performance accelerators. When is your next performance review with them? I''d love to share an audit of untapped revenue areas they might have missed.',
    4
),
(
    'Closing: 10-Minute Discovery Call',
    'closing',
    'interested',
    'It sounds like this would be a high-leverage fit for your roadmap. I''d love to put you in touch with our senior media strategist for a quick 10-minute discovery call. Does Tuesday at 3:00 PM or Wednesday at 11:30 AM work better for you?',
    5
)
ON CONFLICT DO NOTHING;


-- ============================================================================
-- PART 6: SECURITY, QUOTA & AUDIT HARDENING (20261019000001_security_quota_audit_hardening.sql)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum 
        WHERE enumtypid = 'public.call_source'::regtype AND enumlabel = 'manual'
    ) THEN
        ALTER TYPE public.call_source ADD VALUE 'manual';
    END IF;
END $$;

INSERT INTO public.settings (key, value, description)
VALUES (
    'workday_timezone',
    '"Asia/Kolkata"'::jsonb,
    'Authoritative business timezone for daily quota and reporting'
) ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS user_role AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp;

CREATE OR REPLACE FUNCTION public.is_owner()
RETURNS BOOLEAN AS $$
    SELECT COALESCE((public.get_current_user_role() = 'owner'), false);
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp;

CREATE OR REPLACE FUNCTION public.get_workday_timezone()
RETURNS TEXT AS $$
DECLARE
    v_tz TEXT;
BEGIN
    SELECT (value #>> '{}') INTO v_tz FROM public.settings WHERE key = 'workday_timezone';
    RETURN COALESCE(v_tz, 'Asia/Kolkata');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp;

DROP POLICY IF EXISTS "Callers can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_self_or_owner" ON public.profiles;

CREATE POLICY "profiles_update_self_or_owner"
ON public.profiles FOR UPDATE
TO authenticated
USING (id = auth.uid() OR public.is_owner())
WITH CHECK (id = auth.uid() OR public.is_owner());

CREATE OR REPLACE FUNCTION public.trg_enforce_profile_immutability()
RETURNS TRIGGER AS $$
BEGIN
    IF public.is_owner() THEN
        RETURN NEW;
    END IF;

    IF NEW.role IS DISTINCT FROM OLD.role THEN
        RAISE EXCEPTION 'Security violation: Callers cannot alter user roles.';
    END IF;

    IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
        RAISE EXCEPTION 'Security violation: Callers cannot alter active account status.';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'Security violation: User identifier is immutable.';
    END IF;

    IF NEW.email IS DISTINCT FROM OLD.email THEN
        RAISE EXCEPTION 'Security violation: Profile email must be updated via auth provider.';
    END IF;

    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'Security violation: Profile creation timestamp is immutable.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp;

DROP TRIGGER IF EXISTS trg_protect_profile_columns ON public.profiles;
CREATE TRIGGER trg_protect_profile_columns
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_enforce_profile_immutability();

DROP POLICY IF EXISTS "caller_work_sessions_insert" ON public.caller_work_sessions;
DROP POLICY IF EXISTS "caller_work_sessions_update" ON public.caller_work_sessions;
DROP POLICY IF EXISTS "caller_work_sessions_owner_manage" ON public.caller_work_sessions;

CREATE POLICY "caller_work_sessions_owner_manage"
ON public.caller_work_sessions FOR ALL
TO authenticated
USING (public.is_owner())
WITH CHECK (public.is_owner());

DROP INDEX IF EXISTS idx_one_active_work_session_per_caller;
CREATE UNIQUE INDEX IF NOT EXISTS one_active_work_session_per_caller
ON public.caller_work_sessions (caller_id)
WHERE is_active = TRUE;

CREATE OR REPLACE FUNCTION public.clock_in()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_session_id UUID;
    v_active_session RECORD;
    v_tz TEXT;
    v_today DATE;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_tz := public.get_workday_timezone();
    v_today := (now() AT TIME ZONE v_tz)::DATE;

    SELECT * INTO v_active_session
    FROM public.caller_work_sessions
    WHERE caller_id = v_caller_id 
      AND is_active = TRUE
    ORDER BY started_at DESC
    LIMIT 1;

    IF FOUND THEN
        IF (now() - v_active_session.started_at) > interval '14 hours' THEN
            UPDATE public.caller_work_sessions
            SET 
                ended_at = v_active_session.started_at + interval '8 hours',
                duration_seconds = 28800,
                is_active = FALSE
            WHERE id = v_active_session.id;
        ELSE
            RETURN json_build_object(
                'success', true, 
                'session_id', v_active_session.id, 
                'message', 'Resumed existing active work session',
                'started_at', v_active_session.started_at
            );
        END IF;
    END IF;

    INSERT INTO public.caller_work_sessions (
        caller_id, 
        session_date, 
        started_at, 
        is_active, 
        duration_seconds
    )
    VALUES (
        v_caller_id, 
        v_today, 
        now(), 
        TRUE, 
        0
    )
    RETURNING id INTO v_session_id;

    RETURN json_build_object(
        'success', true, 
        'session_id', v_session_id, 
        'message', 'Clocked in successfully',
        'started_at', now()
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.clock_out(p_session_id UUID DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_session RECORD;
    v_duration INTEGER;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_session_id IS NOT NULL THEN
        SELECT * INTO v_session
        FROM public.caller_work_sessions
        WHERE id = p_session_id AND caller_id = v_caller_id AND is_active = TRUE;
    ELSE
        SELECT * INTO v_session
        FROM public.caller_work_sessions
        WHERE caller_id = v_caller_id AND is_active = TRUE
        ORDER BY started_at DESC
        LIMIT 1;
    END IF;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'message', 'No active work session found to clock out.'
        );
    END IF;

    v_duration := GREATEST(0, EXTRACT(EPOCH FROM (now() - v_session.started_at))::INTEGER);

    UPDATE public.caller_work_sessions
    SET 
        ended_at = now(),
        duration_seconds = v_duration,
        is_active = FALSE
    WHERE id = v_session.id;

    RETURN json_build_object(
        'success', true, 
        'session_id', v_session.id,
        'duration_seconds', v_duration,
        'message', 'Clocked out successfully'
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_daily_caller_quota(
    p_caller_id UUID DEFAULT NULL, 
    p_date DATE DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_requesting_id UUID := auth.uid();
    v_target_caller_id UUID;
    v_tz TEXT;
    v_workday_date DATE;
    v_day_start TIMESTAMPTZ;
    v_day_end TIMESTAMPTZ;
    v_active_seconds INTEGER := 0;
    v_talk_seconds INTEGER := 0;
    v_target_seconds CONSTANT INTEGER := 7200;
    v_progress_pct NUMERIC;
    v_is_clocked_in BOOLEAN := FALSE;
    v_current_session_id UUID;
    v_session RECORD;
    v_overlap_sec INTEGER;
BEGIN
    IF v_requesting_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_caller_id IS NOT NULL AND p_caller_id != v_requesting_id THEN
        IF NOT public.is_owner() THEN
            RAISE EXCEPTION 'Access denied: Callers may only inspect their own daily quota.';
        END IF;
        v_target_caller_id := p_caller_id;
    ELSE
        v_target_caller_id := COALESCE(p_caller_id, v_requesting_id);
    END IF;

    v_tz := public.get_workday_timezone();
    v_workday_date := COALESCE(p_date, (now() AT TIME ZONE v_tz)::DATE);

    v_day_start := (v_workday_date::text || ' 00:00:00')::timestamp AT TIME ZONE v_tz;
    v_day_end := (v_workday_date::text || ' 23:59:59.999999')::timestamp AT TIME ZONE v_tz;

    FOR v_session IN 
        SELECT 
            id, 
            started_at, 
            COALESCE(ended_at, now()) AS effective_end,
            is_active
        FROM public.caller_work_sessions
        WHERE caller_id = v_target_caller_id
          AND started_at <= v_day_end
          AND COALESCE(ended_at, now()) >= v_day_start
    LOOP
        v_overlap_sec := GREATEST(0, EXTRACT(EPOCH FROM (
            LEAST(v_session.effective_end, v_day_end) - GREATEST(v_session.started_at, v_day_start)
        ))::INTEGER);
        
        v_active_seconds := v_active_seconds + v_overlap_sec;

        IF v_session.is_active THEN
            v_is_clocked_in := TRUE;
            v_current_session_id := v_session.id;
        END IF;
    END LOOP;

    SELECT COALESCE(SUM(talk_secs), 0)
    INTO v_talk_seconds
    FROM public.calls
    WHERE caller_id = v_target_caller_id 
      AND (initiated_at AT TIME ZONE v_tz)::DATE = v_workday_date;

    v_progress_pct := ROUND(LEAST(100.0, (v_active_seconds::NUMERIC / v_target_seconds::NUMERIC) * 100), 1);

    RETURN json_build_object(
        'caller_id', v_target_caller_id,
        'date', v_workday_date,
        'timezone', v_tz,
        'active_seconds', v_active_seconds,
        'talk_seconds', v_talk_seconds,
        'target_seconds', v_target_seconds,
        'progress_pct', v_progress_pct,
        'quota_met', (v_active_seconds >= v_target_seconds),
        'is_clocked_in', v_is_clocked_in,
        'current_session_id', v_current_session_id
    );
END;
$$;

DROP POLICY IF EXISTS "team_messages_insert_own" ON public.team_messages;

CREATE POLICY "team_messages_insert_own"
ON public.team_messages FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = sender_id 
    AND (is_announcement = FALSE OR public.is_owner())
);

CREATE OR REPLACE FUNCTION public.trg_sanitize_team_message()
RETURNS TRIGGER AS $$
DECLARE
    v_profile RECORD;
BEGIN
    SELECT full_name, role INTO v_profile
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sender profile not found.';
    END IF;

    NEW.sender_id := auth.uid();
    NEW.sender_name := v_profile.full_name;
    NEW.sender_role := v_profile.role::text;

    IF NEW.is_announcement = TRUE AND v_profile.role != 'owner' THEN
        RAISE EXCEPTION 'Security violation: Only owners can broadcast team announcements.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp;

DROP TRIGGER IF EXISTS trg_team_messages_sanitize ON public.team_messages;
CREATE TRIGGER trg_team_messages_sanitize
    BEFORE INSERT ON public.team_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_sanitize_team_message();

CREATE OR REPLACE FUNCTION public.submit_call_dialog(
    p_dial_attempt_id UUID,
    p_device_id UUID,
    p_number_e164 TEXT,
    p_call_type device_call_type,
    p_started_at TIMESTAMPTZ,
    p_duration_secs INT,
    p_sim_slot TEXT,
    p_clock_skew_secs INT,
    p_caller_claimed_connected BOOLEAN,
    p_outcome disposition_outcome,
    p_reason_ids UUID[],
    p_other_reason_text TEXT DEFAULT NULL,
    p_note TEXT DEFAULT NULL,
    p_seconds_after_call_end INT DEFAULT NULL,
    p_follow_up_due_at TIMESTAMPTZ DEFAULT NULL,
    p_follow_up_type follow_up_type DEFAULT NULL,
    p_evidence_source TEXT DEFAULT 'device_log'
)
RETURNS JSONB AS $$
DECLARE
    v_caller_id UUID;
    v_attempt RECORD;
    v_lead RECORD;
    v_min_talk_secs INT;
    v_is_hardware_verified BOOLEAN;
    v_dedupe_key TEXT;
    v_log_entry_id UUID := NULL;
    v_call_id UUID;
    v_disp_id UUID;
    v_new_lead_status lead_status;
    v_has_dnc_reason BOOLEAN := false;
    v_call_source call_source;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_device_id IS NULL THEN
        RAISE EXCEPTION 'Missing required device identifier.';
    END IF;

    SELECT * INTO v_attempt
    FROM public.dial_attempts
    WHERE id = p_dial_attempt_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dial attempt not found.';
    END IF;

    IF v_attempt.caller_id != v_caller_id AND NOT public.is_owner() THEN
        RAISE EXCEPTION 'Security violation: Dial attempt does not belong to you.';
    END IF;

    IF v_attempt.status = 'closed' THEN
        SELECT id INTO v_call_id FROM public.calls 
        WHERE lead_id = v_attempt.lead_id AND caller_id = v_caller_id AND initiated_at = v_attempt.dialed_at
        LIMIT 1;

        RETURN jsonb_build_object(
            'success', true,
            'duplicate_submission', true,
            'message', 'Dial attempt already processed.',
            'call_id', v_call_id
        );
    END IF;

    SELECT * INTO v_lead
    FROM public.leads
    WHERE id = v_attempt.lead_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Associated lead not found.';
    END IF;

    IF p_number_e164 IS NOT NULL AND v_lead.phone_e164 IS NOT NULL THEN
        IF regexp_replace(p_number_e164, '\D', '', 'g') NOT LIKE '%' || right(regexp_replace(v_lead.phone_e164, '\D', '', 'g'), 10) THEN
            RAISE EXCEPTION 'Phone number mismatch: Submitted number does not match assigned lead.';
        END IF;
    END IF;

    IF p_duration_secs < 0 OR p_duration_secs > 86400 THEN
        RAISE EXCEPTION 'Invalid duration: Duration seconds must be between 0 and 86400.';
    END IF;

    IF p_started_at > (now() + interval '2 minutes') THEN
        RAISE EXCEPTION 'Invalid timestamp: Call start time cannot be in the future.';
    END IF;

    IF p_started_at < (v_attempt.dialed_at - interval '10 minutes') THEN
        RAISE EXCEPTION 'Invalid timestamp: Call start time precedes dial attempt.';
    END IF;

    SELECT COALESCE((value)::int, 10) INTO v_min_talk_secs
    FROM public.settings
    WHERE key = 'min_talk_seconds';
    IF v_min_talk_secs IS NULL THEN v_min_talk_secs := 10; END IF;

    v_is_hardware_verified := (p_evidence_source = 'device_log' AND p_sim_slot IS NOT NULL);

    IF v_is_hardware_verified THEN
        v_call_source := 'device_log';
    ELSE
        v_call_source := 'manual';
    END IF;

    IF p_duration_secs < v_min_talk_secs AND p_outcome = 'interested' THEN
        RAISE EXCEPTION 'Cannot claim interested on a call duration under the minimum % second threshold.', v_min_talk_secs;
    END IF;

    IF v_is_hardware_verified THEN
        v_dedupe_key := p_device_id::text || '_' || p_number_e164 || '_' || extract(epoch from p_started_at)::text || '_' || p_duration_secs::text;
        
        INSERT INTO public.device_call_log_entries (
            dial_attempt_id,
            device_id,
            number_e164,
            call_type,
            started_at,
            duration_secs,
            sim_slot,
            uploaded_at,
            clock_skew_secs,
            dedupe_key
        ) VALUES (
            p_dial_attempt_id,
            p_device_id,
            p_number_e164,
            p_call_type,
            p_started_at,
            p_duration_secs,
            p_sim_slot,
            timezone('utc'::text, now()),
            p_clock_skew_secs,
            v_dedupe_key
        )
        ON CONFLICT (dedupe_key) DO UPDATE SET
            dial_attempt_id = EXCLUDED.dial_attempt_id
        RETURNING id INTO v_log_entry_id;
    END IF;

    INSERT INTO public.calls (
        lead_id,
        caller_id,
        device_id,
        device_call_log_entry_id,
        source,
        status,
        initiated_at,
        ended_at,
        talk_secs
    ) VALUES (
        v_attempt.lead_id,
        v_caller_id,
        p_device_id,
        v_log_entry_id,
        v_call_source,
        'closed',
        v_attempt.dialed_at,
        p_started_at + (p_duration_secs * interval '1 second'),
        p_duration_secs
    )
    RETURNING id INTO v_call_id;

    INSERT INTO public.dispositions (
        call_id,
        lead_id,
        caller_id,
        connected,
        caller_claimed_connected,
        outcome,
        reason_ids,
        other_reason_text,
        note,
        submitted_at,
        seconds_after_call_end
    ) VALUES (
        v_call_id,
        v_attempt.lead_id,
        v_caller_id,
        (p_duration_secs >= v_min_talk_secs),
        p_caller_claimed_connected,
        p_outcome,
        p_reason_ids,
        p_other_reason_text,
        p_note,
        timezone('utc'::text, now()),
        p_seconds_after_call_end
    )
    RETURNING id INTO v_disp_id;

    SELECT EXISTS (
        SELECT 1 FROM public.reasons 
        WHERE id = ANY(p_reason_ids) AND label ILIKE '%not to be contacted%'
    ) INTO v_has_dnc_reason;

    IF v_has_dnc_reason THEN
        v_new_lead_status := 'do_not_call';
    ELSIF p_outcome = 'interested' THEN
        IF p_follow_up_due_at IS NOT NULL THEN
            v_new_lead_status := 'follow_up';
        ELSE
            v_new_lead_status := 'interested';
        END IF;
    ELSIF p_outcome = 'not_interested' THEN
        v_new_lead_status := 'not_interested';
    ELSE
        v_new_lead_status := 'called';
    END IF;

    UPDATE public.leads SET
        status = v_new_lead_status,
        attempt_count = attempt_count + 1,
        last_call_at = timezone('utc'::text, now()),
        next_follow_up_at = p_follow_up_due_at,
        updated_at = timezone('utc'::text, now())
    WHERE id = v_attempt.lead_id;

    IF p_outcome = 'interested' AND p_follow_up_due_at IS NOT NULL AND p_follow_up_type IS NOT NULL THEN
        INSERT INTO public.follow_ups (
            lead_id,
            assigned_to,
            due_at,
            type,
            status,
            source_disposition_id,
            notes
        ) VALUES (
            v_attempt.lead_id,
            v_caller_id,
            p_follow_up_due_at,
            p_follow_up_type,
            'open',
            v_disp_id,
            p_note
        );
    END IF;

    UPDATE public.dial_attempts SET
        status = 'closed',
        updated_at = timezone('utc'::text, now())
    WHERE id = p_dial_attempt_id;

    IF NOT v_is_hardware_verified THEN
        INSERT INTO public.flags (call_id, caller_id, dial_attempt_id, rule_code, severity, details)
        VALUES (
            v_call_id, 
            v_caller_id, 
            p_dial_attempt_id, 
            'MANUAL_UNVERIFIED_ENTRY', 
            'warn', 
            jsonb_build_object(
                'reason', 'No SIM call log matched; duration self-reported by caller',
                'manual_duration_secs', p_duration_secs,
                'evidence_source', p_evidence_source
            )
        );
    END IF;

    IF p_caller_claimed_connected AND p_duration_secs < v_min_talk_secs THEN
        INSERT INTO public.flags (call_id, caller_id, dial_attempt_id, rule_code, severity, details)
        VALUES (
            v_call_id, 
            v_caller_id, 
            p_dial_attempt_id, 
            'CLAIM_MISMATCH', 
            'high', 
            jsonb_build_object(
                'claimed', true, 
                'duration_secs', p_duration_secs, 
                'min_threshold', v_min_talk_secs
            )
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'call_id', v_call_id,
        'disposition_id', v_disp_id,
        'evidence_source', v_call_source,
        'is_verified', v_is_hardware_verified
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp;

REVOKE EXECUTE ON FUNCTION public.clock_in() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clock_in() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.clock_out(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clock_out(UUID) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.get_daily_caller_quota(UUID, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_daily_caller_quota(UUID, DATE) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.submit_call_dialog(
    UUID, UUID, TEXT, device_call_type, TIMESTAMPTZ, INT, TEXT, INT, BOOLEAN, 
    disposition_outcome, UUID[], TEXT, TEXT, INT, TIMESTAMPTZ, follow_up_type, TEXT
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_call_dialog(
    UUID, UUID, TEXT, device_call_type, TIMESTAMPTZ, INT, TEXT, INT, BOOLEAN, 
    disposition_outcome, UUID[], TEXT, TEXT, INT, TIMESTAMPTZ, follow_up_type, TEXT
) TO authenticated, service_role;

-- ============================================================================
-- 20261020000001_team_messages_admin_moderation.sql
-- Admin message moderation (Edit & Delete for Admin only)
-- Strictly restricts callers from editing or deleting team messages
-- ============================================================================

ALTER TABLE public.team_messages 
ADD COLUMN IF NOT EXISTS is_edited BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.team_messages 
ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

ALTER TABLE public.team_messages ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Enhanced is_owner() recognizing service_role and owner profile
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_owner()
RETURNS BOOLEAN AS $$
    SELECT (
        -- Service role or superuser execution (Next.js server with SERVICE_ROLE_KEY or pg admin)
        COALESCE(auth.role(), '') = 'service_role'
        OR current_user IN ('postgres', 'service_role', 'supabase_admin')
        OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
        -- Authenticated owner user
        OR COALESCE((public.get_current_user_role() = 'owner'), false)
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp;

DROP POLICY IF EXISTS "team_messages_delete_owner" ON public.team_messages;

CREATE POLICY "team_messages_delete_owner"
ON public.team_messages FOR DELETE
TO authenticated, service_role
USING (public.is_owner());

CREATE OR REPLACE FUNCTION public.trg_team_messages_delete_guard()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT public.is_owner() THEN
        RAISE EXCEPTION 'Access denied: Only owners/admins can delete team messages.';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp;

DROP TRIGGER IF EXISTS trg_team_messages_delete ON public.team_messages;
CREATE TRIGGER trg_team_messages_delete
    BEFORE DELETE ON public.team_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_team_messages_delete_guard();

DROP POLICY IF EXISTS "team_messages_update_owner" ON public.team_messages;

CREATE POLICY "team_messages_update_owner"
ON public.team_messages FOR UPDATE
TO authenticated, service_role
USING (public.is_owner())
WITH CHECK (public.is_owner());

CREATE OR REPLACE FUNCTION public.trg_team_messages_update_guard()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT public.is_owner() THEN
        RAISE EXCEPTION 'Access denied: Only owners/admins can edit team messages.';
    END IF;

    NEW.id := OLD.id;
    NEW.sender_id := OLD.sender_id;
    NEW.sender_name := OLD.sender_name;
    NEW.sender_role := OLD.sender_role;
    NEW.created_at := OLD.created_at;

    NEW.is_edited := TRUE;
    NEW.edited_at := now();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp;

DROP TRIGGER IF EXISTS trg_team_messages_update ON public.team_messages;
CREATE TRIGGER trg_team_messages_update
    BEFORE UPDATE ON public.team_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_team_messages_update_guard();

CREATE OR REPLACE FUNCTION public.admin_edit_team_message(
    p_message_id UUID,
    p_new_content TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_is_owner BOOLEAN;
    v_updated RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    SELECT (role = 'owner') INTO v_is_owner
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT COALESCE(v_is_owner, FALSE) THEN
        RAISE EXCEPTION 'Access denied: Only owners/admins can edit team messages.';
    END IF;

    IF p_new_content IS NULL OR trim(p_new_content) = '' THEN
        RAISE EXCEPTION 'Message content cannot be empty.';
    END IF;

    UPDATE public.team_messages
    SET 
        content = trim(p_new_content),
        is_edited = TRUE,
        edited_at = now()
    WHERE id = p_message_id
    RETURNING * INTO v_updated;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Message not found.';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message_id', v_updated.id,
        'content', v_updated.content,
        'is_edited', v_updated.is_edited,
        'edited_at', v_updated.edited_at
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_edit_team_message(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_edit_team_message(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_team_message(
    p_message_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_is_owner BOOLEAN;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.';
    END IF;

    SELECT (role = 'owner') INTO v_is_owner
    FROM public.profiles
    WHERE id = auth.uid();

    IF NOT COALESCE(v_is_owner, FALSE) THEN
        RAISE EXCEPTION 'Access denied: Only owners/admins can delete team messages.';
    END IF;

    DELETE FROM public.team_messages
    WHERE id = p_message_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Message not found.';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message_id', p_message_id
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_delete_team_message(UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_team_message(UUID) TO authenticated;
-- 20261020000002_work_period_tracking_and_management.sql
-- Implements:
-- 1. Strict Work Period Enforcement: Callers cannot start dial attempts or submit calls unless clocked in.
-- 2. get_caller_work_status RPC: authoritative work status, active session, and duration for the caller.
-- 3. Leads and Callers Management: Ensures owners have authoritative RPCs and RLS for updating leads and caller profiles.

-- ============================================================================
-- 1. Enforce Active Work Period on start_dial_attempt
-- ============================================================================

CREATE OR REPLACE FUNCTION public.start_dial_attempt(
    p_lead_id UUID,
    p_device_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_caller_id UUID;
    v_lead RECORD;
    v_open_attempt_id UUID;
    v_new_attempt_id UUID;
    v_is_clocked_in BOOLEAN;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- 1. Strictly verify caller is clocked in (active work session)
    SELECT EXISTS (
        SELECT 1 FROM public.caller_work_sessions
        WHERE caller_id = v_caller_id AND is_active = TRUE
    ) INTO v_is_clocked_in;

    IF NOT COALESCE(v_is_clocked_in, FALSE) THEN
        RAISE EXCEPTION 'NOT_CLOCKED_IN: Work login required. You must clock in to begin your work period before initiating calls.';
    END IF;

    -- 2. Verify lead exists and is assigned to caller (or caller is owner)
    SELECT * INTO v_lead FROM public.leads WHERE id = p_lead_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead not found.';
    END IF;

    IF v_lead.status = 'do_not_call' THEN
        RAISE EXCEPTION 'LEAD_DNC: This lead is on the Do Not Call list.';
    END IF;

    IF NOT public.is_owner() AND v_lead.assigned_to IS DISTINCT FROM v_caller_id THEN
        RAISE EXCEPTION 'Access denied: You are not assigned to this lead.';
    END IF;

    -- 3. Check Call Lock (open dial attempt)
    SELECT id INTO v_open_attempt_id
    FROM public.dial_attempts
    WHERE caller_id = v_caller_id AND status = 'open'
    LIMIT 1;

    IF v_open_attempt_id IS NOT NULL THEN
        RAISE EXCEPTION 'CALL_LOCKED: You have an open dial attempt (%) awaiting completion.', v_open_attempt_id;
    END IF;

    -- 4. Create dial attempt
    INSERT INTO public.dial_attempts (
        lead_id,
        caller_id,
        device_id,
        dialed_at,
        status
    )
    VALUES (
        p_lead_id,
        v_caller_id,
        p_device_id,
        now(),
        'open'
    )
    RETURNING id INTO v_new_attempt_id;

    -- Increment attempt count
    UPDATE public.leads
    SET 
        attempt_count = COALESCE(attempt_count, 0) + 1,
        last_call_at = now(),
        status = CASE WHEN status = 'new' THEN 'in_progress' ELSE status END
    WHERE id = p_lead_id;

    RETURN jsonb_build_object(
        'success', true,
        'dial_attempt_id', v_new_attempt_id,
        'lead_id', p_lead_id,
        'dialed_at', now()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp;

REVOKE EXECUTE ON FUNCTION public.start_dial_attempt(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_dial_attempt(UUID, UUID) TO authenticated, service_role;

-- ============================================================================
-- 2. RPC: get_caller_work_status
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_caller_work_status()
RETURNS JSONB AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_session RECORD;
    v_tz TEXT;
    v_today DATE;
    v_today_seconds INT := 0;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_tz := public.get_workday_timezone();
    v_today := (now() AT TIME ZONE v_tz)::DATE;

    -- Locate active session
    SELECT * INTO v_session
    FROM public.caller_work_sessions
    WHERE caller_id = v_caller_id AND is_active = TRUE
    ORDER BY started_at DESC
    LIMIT 1;

    -- Calculate total duration today
    SELECT COALESCE(SUM(
        CASE 
            WHEN is_active = TRUE THEN 
                COALESCE(duration_seconds, 0) + GREATEST(0, EXTRACT(EPOCH FROM (now() - started_at))::INT)
            ELSE 
                COALESCE(duration_seconds, 0)
        END
    ), 0)::INT INTO v_today_seconds
    FROM public.caller_work_sessions
    WHERE caller_id = v_caller_id AND session_date = v_today;

    RETURN jsonb_build_object(
        'is_clocked_in', (v_session.id IS NOT NULL),
        'current_session_id', v_session.id,
        'started_at', v_session.started_at,
        'active_seconds_today', v_today_seconds,
        'quota_target_seconds', 7200,
        'quota_met', (v_today_seconds >= 7200)
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_caller_work_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_caller_work_status() TO authenticated, service_role;

-- ============================================================================
-- 3. Owner RPC: admin_update_lead
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_update_lead(
    p_lead_id UUID,
    p_name TEXT DEFAULT NULL,
    p_phone_e164 TEXT DEFAULT NULL,
    p_company TEXT DEFAULT NULL,
    p_city TEXT DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_assigned_to UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_next_follow_up_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_updated RECORD;
BEGIN
    IF NOT public.is_owner() THEN
        RAISE EXCEPTION 'Access denied: Only owners/admins can modify lead details.';
    END IF;

    UPDATE public.leads
    SET
        name = COALESCE(trim(p_name), name),
        phone_e164 = COALESCE(trim(p_phone_e164), phone_e164),
        company = CASE WHEN p_company IS NOT NULL THEN trim(p_company) ELSE company END,
        city = CASE WHEN p_city IS NOT NULL THEN trim(p_city) ELSE city END,
        status = COALESCE(p_status, status),
        assigned_to = CASE WHEN p_assigned_to IS NOT NULL THEN p_assigned_to ELSE assigned_to END,
        assigned_at = CASE WHEN p_assigned_to IS NOT NULL AND p_assigned_to IS DISTINCT FROM assigned_to THEN now() ELSE assigned_at END,
        notes = CASE WHEN p_notes IS NOT NULL THEN trim(p_notes) ELSE notes END,
        next_follow_up_at = p_next_follow_up_at,
        updated_at = now()
    WHERE id = p_lead_id
    RETURNING * INTO v_updated;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lead not found.';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'lead', row_to_json(v_updated)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_temp;

REVOKE EXECUTE ON FUNCTION public.admin_update_lead FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_lead TO authenticated, service_role;
