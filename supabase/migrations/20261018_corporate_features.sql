-- 20261018_corporate_features.sql
-- Implements:
-- 1. Community Team Chatbox (team_messages + Supabase Realtime)
-- 2. Employee Profile Management (self-update RLS)
-- 3. Mandatory 2-Hour Daily Work Quota (caller_work_sessions + get_daily_caller_quota RPC)
-- 4. Corporate Features: In-App Pitch Scripts & Objection Cheat-Sheet (pitch_scripts)

-- ============================================================================
-- 1. Community Team Chatbox
-- ============================================================================

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

-- Everyone authenticated can read team messages
CREATE POLICY "team_messages_select_authenticated"
ON public.team_messages FOR SELECT
TO authenticated
USING (true);

-- Authenticated users can insert their own messages
CREATE POLICY "team_messages_insert_own"
ON public.team_messages FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = sender_id);

-- Owners can delete messages if moderation is needed
CREATE POLICY "team_messages_delete_owner"
ON public.team_messages FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() AND role = 'owner'
    )
);

-- Enable Supabase Realtime publication
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'team_messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.team_messages;
    END IF;
END $$;


-- ============================================================================
-- 2. Employee Profile Self-Update Policy
-- ============================================================================

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own"
ON public.profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (
    auth.uid() = id
    -- Callers cannot elevate their own role or toggle their own active status
    AND (
        (role = (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid()) 
         AND is_active = (SELECT p.is_active FROM public.profiles p WHERE p.id = auth.uid()))
        OR (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid()) = 'owner'
    )
);


-- ============================================================================
-- 3. Mandatory 2-Hour Daily Work Quota (Interpretation A)
-- ============================================================================

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

-- RPC: Clock In
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

    -- Check if an active session already exists for today
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

    -- Create new session
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

-- RPC: Clock Out
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

-- RPC: Get Daily Quota Progress (Mandatory 2-Hour Target = 7200 seconds)
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
    v_target_seconds CONSTANT INTEGER := 7200; -- 2 Hours = 7200 seconds
    v_progress_pct NUMERIC;
    v_is_clocked_in BOOLEAN := FALSE;
    v_current_session_id UUID;
    v_active_session RECORD;
BEGIN
    IF v_target_caller_id IS NULL THEN
        RAISE EXCEPTION 'Caller ID required';
    END IF;

    -- Calculate total duration from completed work sessions today
    SELECT COALESCE(SUM(duration_seconds), 0)
    INTO v_active_seconds
    FROM public.caller_work_sessions
    WHERE caller_id = v_target_caller_id 
      AND session_date = p_date 
      AND is_active = FALSE;

    -- Add elapsed seconds from currently active session if any
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

    -- Calculate total talk seconds from calls made today
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


-- ============================================================================
-- 4. Corporate Pitch Scripts & Objection Cheat-Sheet
-- ============================================================================

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

-- Seed standard corporate pitch scripts and objection handlers
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
