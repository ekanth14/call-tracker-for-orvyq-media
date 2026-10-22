-- Migration: 20261019000001_security_quota_audit_hardening.sql
-- Description: Comprehensive database security, daily quota calculation, call verification,
--              anti-spoofing triggers, and audit hardening.

-- ============================================================================
-- 1. Enum Updates & Schema Alignments
-- ============================================================================

-- Add 'manual' to call_source enum if it doesn't already exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum 
        WHERE enumtypid = 'public.call_source'::regtype AND enumlabel = 'manual'
    ) THEN
        ALTER TYPE public.call_source ADD VALUE 'manual';
    END IF;
END $$;

-- Ensure calling timezone setting exists with default 'Asia/Kolkata'
INSERT INTO public.settings (key, value, description)
VALUES (
    'workday_timezone',
    '"Asia/Kolkata"'::jsonb,
    'Authoritative business timezone for daily quota and reporting'
) ON CONFLICT (key) DO NOTHING;


-- ============================================================================
-- 2. Audit Helper Functions with Search Paths
-- ============================================================================

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


-- ============================================================================
-- 3. Profile Self-Update Hardening & Trigger Protection
-- ============================================================================

-- Drop all conflicting legacy permissive update policies on profiles
DROP POLICY IF EXISTS "Callers can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_self_or_owner" ON public.profiles;

CREATE POLICY "profiles_update_self_or_owner"
ON public.profiles FOR UPDATE
TO authenticated
USING (id = auth.uid() OR public.is_owner())
WITH CHECK (id = auth.uid() OR public.is_owner());

-- Trigger: Prohibit callers from tampering with role, is_active, email, id, or created_at
CREATE OR REPLACE FUNCTION public.trg_enforce_profile_immutability()
RETURNS TRIGGER AS $$
BEGIN
    -- Owners are permitted to update all fields
    IF public.is_owner() THEN
        RETURN NEW;
    END IF;

    -- Non-owners (callers) can only update display name and mobile number
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


-- ============================================================================
-- 4. Work Sessions & Quota Security (Prevent Quota Spoofing)
-- ============================================================================

-- Drop direct client insert & update policies for callers on caller_work_sessions
DROP POLICY IF EXISTS "caller_work_sessions_insert" ON public.caller_work_sessions;
DROP POLICY IF EXISTS "caller_work_sessions_update" ON public.caller_work_sessions;
DROP POLICY IF EXISTS "caller_work_sessions_owner_manage" ON public.caller_work_sessions;

-- Only owners can directly write to caller_work_sessions table; callers MUST use clock_in/clock_out
CREATE POLICY "caller_work_sessions_owner_manage"
ON public.caller_work_sessions FOR ALL
TO authenticated
USING (public.is_owner())
WITH CHECK (public.is_owner());

-- Ensure partial unique index prevents more than 1 active session per caller
DROP INDEX IF EXISTS idx_one_active_work_session_per_caller;
CREATE UNIQUE INDEX IF NOT EXISTS one_active_work_session_per_caller
ON public.caller_work_sessions (caller_id)
WHERE is_active = TRUE;

-- Hardened RPC: Clock In
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

    -- Check if ANY active session exists for this caller (regardless of date)
    SELECT * INTO v_active_session
    FROM public.caller_work_sessions
    WHERE caller_id = v_caller_id 
      AND is_active = TRUE
    ORDER BY started_at DESC
    LIMIT 1;

    IF FOUND THEN
        -- If active session is older than 14 hours (stale forgotten clock-out), auto-close it
        IF (now() - v_active_session.started_at) > interval '14 hours' THEN
            UPDATE public.caller_work_sessions
            SET 
                ended_at = v_active_session.started_at + interval '8 hours',
                duration_seconds = 28800,
                is_active = FALSE
            WHERE id = v_active_session.id;
        ELSE
            -- Resume recent active session gracefully
            RETURN json_build_object(
                'success', true, 
                'session_id', v_active_session.id, 
                'message', 'Resumed existing active work session',
                'started_at', v_active_session.started_at
            );
        END IF;
    END IF;

    -- Create new active work session
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

-- Hardened RPC: Clock Out
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

    -- Locate target active session
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

    -- Derive duration strictly on the server from authoritative server clock
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

-- Hardened RPC: Get Daily Quota Progress
-- Corrected:
-- 1. Uses canonical calls.talk_secs and calls.initiated_at (NOT actual_duration_seconds / started_at)
-- 2. Restricts callers to viewing ONLY their own quota (owners can view any caller)
-- 3. Accurate workday timezone calculation (Asia/Kolkata)
-- 4. Correctly computes overlap for sessions crossing midnight
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
    v_target_seconds CONSTANT INTEGER := 7200; -- 2 Hours = 7,200 seconds
    v_progress_pct NUMERIC;
    v_is_clocked_in BOOLEAN := FALSE;
    v_current_session_id UUID;
    v_session RECORD;
    v_overlap_sec INTEGER;
BEGIN
    IF v_requesting_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Security restriction: Callers can only view their own quota
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

    -- Calculate day boundaries in the authoritative workday timezone
    v_day_start := (v_workday_date::text || ' 00:00:00')::timestamp AT TIME ZONE v_tz;
    v_day_end := (v_workday_date::text || ' 23:59:59.999999')::timestamp AT TIME ZONE v_tz;

    -- 1. Calculate active seconds from all sessions overlapping this workday date (handles crossing midnight)
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
        -- Calculate overlap between [started_at, effective_end] and [v_day_start, v_day_end]
        v_overlap_sec := GREATEST(0, EXTRACT(EPOCH FROM (
            LEAST(v_session.effective_end, v_day_end) - GREATEST(v_session.started_at, v_day_start)
        ))::INTEGER);
        
        v_active_seconds := v_active_seconds + v_overlap_sec;

        IF v_session.is_active THEN
            v_is_clocked_in := TRUE;
            v_current_session_id := v_session.id;
        END IF;
    END LOOP;

    -- 2. Calculate verified talk seconds using canonical calls.talk_secs and calls.initiated_at
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


-- ============================================================================
-- 5. Team Messages Anti-Forging & Announcement Protection
-- ============================================================================

-- Drop and recreate insert policy on team_messages
DROP POLICY IF EXISTS "team_messages_insert_own" ON public.team_messages;

CREATE POLICY "team_messages_insert_own"
ON public.team_messages FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = sender_id 
    AND (is_announcement = FALSE OR public.is_owner())
);

-- Trigger: Enforce authoritative sender profile and reject announcement spoofing
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

    -- Overwrite sender fields with authoritative profile data
    NEW.sender_id := auth.uid();
    NEW.sender_name := v_profile.full_name;
    NEW.sender_role := v_profile.role::text;

    -- Prohibit non-owners from flagging messages as announcements
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


-- ============================================================================
-- 6. Hardened submit_call_dialog RPC (Evidence Source & Verification)
-- ============================================================================

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

    -- 1. Validate dial attempt exists and belongs to caller
    SELECT * INTO v_attempt
    FROM public.dial_attempts
    WHERE id = p_dial_attempt_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dial attempt not found.';
    END IF;

    IF v_attempt.caller_id != v_caller_id AND NOT public.is_owner() THEN
        RAISE EXCEPTION 'Security violation: Dial attempt does not belong to you.';
    END IF;

    -- Prevent submitting dialog against already closed attempts (duplicate sync protection)
    IF v_attempt.status = 'closed' THEN
        -- If already closed, return existing call info idempotently
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

    -- 2. Validate Lead Relationship
    SELECT * INTO v_lead
    FROM public.leads
    WHERE id = v_attempt.lead_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Associated lead not found.';
    END IF;

    -- Ensure submitted phone corresponds to the assigned lead phone
    IF p_number_e164 IS NOT NULL AND v_lead.phone_e164 IS NOT NULL THEN
        IF regexp_replace(p_number_e164, '\D', '', 'g') NOT LIKE '%' || right(regexp_replace(v_lead.phone_e164, '\D', '', 'g'), 10) THEN
            RAISE EXCEPTION 'Phone number mismatch: Submitted number does not match assigned lead.';
        END IF;
    END IF;

    -- 3. Validate timing and duration boundaries
    IF p_duration_secs < 0 OR p_duration_secs > 86400 THEN
        RAISE EXCEPTION 'Invalid duration: Duration seconds must be between 0 and 86400.';
    END IF;

    IF p_started_at > (now() + interval '2 minutes') THEN
        RAISE EXCEPTION 'Invalid timestamp: Call start time cannot be in the future.';
    END IF;

    IF p_started_at < (v_attempt.dialed_at - interval '10 minutes') THEN
        RAISE EXCEPTION 'Invalid timestamp: Call start time precedes dial attempt.';
    END IF;

    -- Get min talk seconds threshold from settings (default 10)
    SELECT COALESCE((value)::int, 10) INTO v_min_talk_secs
    FROM public.settings
    WHERE key = 'min_talk_seconds';
    IF v_min_talk_secs IS NULL THEN v_min_talk_secs := 10; END IF;

    -- Determine hardware-verified vs manual/unverified
    -- Manual submissions MUST NEVER be labeled as hardware-verified
    v_is_hardware_verified := (p_evidence_source = 'device_log' AND p_sim_slot IS NOT NULL);

    IF v_is_hardware_verified THEN
        v_call_source := 'device_log';
    ELSE
        v_call_source := 'manual';
    END IF;

    -- 10-Second rule is a duration threshold only (not proof of human contact)
    -- If under threshold, outcome cannot be 'interested'
    IF p_duration_secs < v_min_talk_secs AND p_outcome = 'interested' THEN
        RAISE EXCEPTION 'Cannot claim interested on a call duration under the minimum % second threshold.', v_min_talk_secs;
    END IF;

    -- 4. If hardware-verified, record in device_call_log_entries
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

    -- 5. Insert into calls table (canonical columns: initiated_at, talk_secs, source)
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

    -- 6. Insert immutable disposition
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

    -- 7. Update Lead status and metadata
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

    -- 8. Follow-up scheduling if requested
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

    -- 9. Close the dial attempt (Releases Call Lock)
    UPDATE public.dial_attempts SET
        status = 'closed',
        updated_at = timezone('utc'::text, now())
    WHERE id = p_dial_attempt_id;

    -- 10. Audit Flags & Anomaly Detection
    -- Flag: MANUAL_UNVERIFIED_ENTRY
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

    -- Flag: CLAIM_MISMATCH (caller claimed connected, but duration was under minimum threshold)
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


-- ============================================================================
-- 7. Secure EXECUTE Grants on RPCs
-- ============================================================================

-- Revoke public & anon execution on security-sensitive procedures
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
