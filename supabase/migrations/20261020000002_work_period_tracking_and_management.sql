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
