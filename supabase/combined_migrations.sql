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
