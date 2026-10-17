-- Migration: 20261017000001_initial_schema.sql
-- Description: Core schema for Orvyqmedia Cold-Calling Tracker (ARCHITECTURE.md Sec 8 + ANDROID_FIRST_ADDENDUM.md Sec 7)

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enums
CREATE TYPE user_role AS ENUM ('owner', 'manager', 'caller');
CREATE TYPE lead_status AS ENUM ('new', 'assigned', 'in_progress', 'called', 'interested', 'not_interested', 'follow_up', 'unreachable', 'do_not_call');
CREATE TYPE dnd_status AS ENUM ('unknown', 'clear', 'registered');
CREATE TYPE call_source AS ENUM ('device_log', 'provider');
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
CREATE TYPE dial_attempt_status AS ENUM ('open', 'matched', 'no_call_detected', 'closed');
CREATE TYPE device_call_type AS ENUM ('outgoing', 'incoming', 'missed');
CREATE TYPE disposition_outcome AS ENUM ('interested', 'not_interested', 'not_connected');
CREATE TYPE follow_up_type AS ENUM ('callback', 'proposal', 'demo', 'meeting');
CREATE TYPE follow_up_status AS ENUM ('open', 'done', 'cancelled');
CREATE TYPE flag_severity AS ENUM ('info', 'warn', 'high');
CREATE TYPE flag_status AS ENUM ('open', 'dismissed', 'confirmed');

-- Profiles table (linked to auth.users)
CREATE TABLE profiles (
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
CREATE TABLE lead_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    source TEXT,
    created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Leads
CREATE TABLE leads (
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
CREATE TABLE devices (
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
CREATE TABLE dial_attempts (
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
CREATE UNIQUE INDEX one_open_dial_attempt_per_caller 
    ON dial_attempts(caller_id) 
    WHERE status = 'open';

-- Device Call Log Entries (Addendum Sec 7, append-only)
CREATE TABLE device_call_log_entries (
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
CREATE TABLE calls (
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
CREATE TABLE reasons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    outcome disposition_outcome NOT NULL,
    label TEXT NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Dispositions (One per closed call, immutable once saved)
CREATE TABLE dispositions (
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
CREATE TABLE follow_ups (
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
CREATE TABLE flags (
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
CREATE TABLE audit_log (
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
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Indexes for performance
CREATE INDEX idx_leads_assigned_status ON leads(assigned_to, status);
CREATE INDEX idx_leads_phone ON leads(phone_e164);
CREATE INDEX idx_calls_caller_initiated ON calls(caller_id, initiated_at DESC);
CREATE INDEX idx_calls_lead ON calls(lead_id);
CREATE INDEX idx_dispositions_submitted ON dispositions(submitted_at);
CREATE INDEX idx_device_call_log_device ON device_call_log_entries(device_id, started_at DESC);
CREATE INDEX idx_flags_status_severity ON flags(status, severity);
CREATE INDEX idx_dial_attempts_caller_status ON dial_attempts(caller_id, status);

-- Trigger: Immutability for dispositions
CREATE OR REPLACE FUNCTION prevent_disposition_update_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Dispositions are immutable and cannot be updated or deleted.';
END;
$$ LANGUAGE plpgsql;

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

CREATE TRIGGER trg_audit_log_immutable
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW
    EXECUTE FUNCTION prevent_audit_log_update_delete();
