-- Migration: 20261017000004_functions_and_triggers.sql
-- Description: Auth triggers and secure Security Definer RPCs for Call/Dialog lifecycles

-- 1. Automatic Profile Creation on auth.users Signup
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

-- Trigger to hook into auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT OR UPDATE OF email, raw_user_meta_data ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- 2. Secure RPC to start a Dial Attempt (Enforces Call Lock & Assignment)
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

-- 3. Secure RPC to submit Matched Call Log Entry + Post-Call Dialog
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

    -- Retrieve dial attempt
    SELECT * INTO v_attempt
    FROM dial_attempts
    WHERE id = p_dial_attempt_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dial attempt not found.';
    END IF;

    IF v_attempt.caller_id != v_caller_id AND NOT public.is_owner() THEN
        RAISE EXCEPTION 'Dial attempt does not belong to you.';
    END IF;

    -- Get min talk seconds threshold from settings (default 10)
    SELECT COALESCE((value)::int, 10) INTO v_min_talk_secs
    FROM settings
    WHERE key = 'min_talk_seconds';
    IF v_min_talk_secs IS NULL THEN v_min_talk_secs := 10; END IF;

    -- Evaluate whether the call connected based on device log evidence
    v_connected := (p_call_type = 'outgoing' AND p_duration_secs >= v_min_talk_secs);

    -- Validation: If system determined not connected, outcome cannot be 'interested'
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

    -- Check if "Asked not to be contacted again" was selected
    SELECT EXISTS (
        SELECT 1 FROM reasons 
        WHERE id = ANY(p_reason_ids) AND label ILIKE '%not to be contacted%'
    ) INTO v_has_dnc_reason;

    -- Determine new lead status
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

    -- 5. If follow-up requested, create follow-up
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

    -- 6. Close the dial attempt (Releases Call Lock)
    UPDATE dial_attempts SET
        status = 'closed',
        updated_at = timezone('utc'::text, now())
    WHERE id = p_dial_attempt_id;

    -- 7. Verification Flags Evaluation
    -- Rule: CLAIM_MISMATCH (caller claimed connected, but log duration was under minimum)
    IF p_caller_claimed_connected AND NOT v_connected THEN
        INSERT INTO flags (call_id, caller_id, dial_attempt_id, rule_code, severity, details)
        VALUES (v_call_id, v_caller_id, p_dial_attempt_id, 'CLAIM_MISMATCH', 'high', 
            jsonb_build_object('claimed', true, 'duration_secs', p_duration_secs, 'min_threshold', v_min_talk_secs));
    END IF;

    -- Rule: SHORT_INTERESTED (marked interested on a very short call < min threshold)
    IF p_outcome = 'interested' AND p_duration_secs < v_min_talk_secs THEN
        INSERT INTO flags (call_id, caller_id, dial_attempt_id, rule_code, severity, details)
        VALUES (v_call_id, v_caller_id, p_dial_attempt_id, 'SHORT_INTERESTED', 'warn',
            jsonb_build_object('duration_secs', p_duration_secs, 'outcome', 'interested'));
    END IF;

    -- Rule: CLOCK_SKEW (large time difference between phone and server)
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
