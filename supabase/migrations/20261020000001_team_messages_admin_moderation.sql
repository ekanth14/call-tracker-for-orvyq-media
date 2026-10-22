-- 20261020000001_team_messages_admin_moderation.sql
-- Implements:
-- 1. Admin message moderation columns: is_edited (BOOLEAN), edited_at (TIMESTAMPTZ)
-- 2. Enhanced is_owner() recognizing service_role and owner profile
-- 3. Strictly enforces that ONLY owners/admins can DELETE any team message (their own or employees')
-- 4. Strictly enforces that ONLY owners/admins can UPDATE/EDIT any team message
-- 5. Callers/employees are strictly prohibited from editing or deleting team messages
-- 6. Authoritative RPCs: admin_edit_team_message and admin_delete_team_message

-- ============================================================================
-- 1. Moderation Columns on team_messages
-- ============================================================================

ALTER TABLE public.team_messages 
ADD COLUMN IF NOT EXISTS is_edited BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.team_messages 
ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

-- Ensure RLS is enabled
ALTER TABLE public.team_messages ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. Enhanced is_owner() recognizing service_role and owner profile
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

-- ============================================================================
-- 3. Restrict DELETE to Owners/Admins Only
-- ============================================================================

DROP POLICY IF EXISTS "team_messages_delete_owner" ON public.team_messages;

CREATE POLICY "team_messages_delete_owner"
ON public.team_messages FOR DELETE
TO authenticated, service_role
USING (public.is_owner());

-- Delete guard trigger: extra layer of protection to guarantee no non-owner can delete
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

-- ============================================================================
-- 4. Restrict UPDATE (Edit) to Owners/Admins Only
-- ============================================================================

DROP POLICY IF EXISTS "team_messages_update_owner" ON public.team_messages;

CREATE POLICY "team_messages_update_owner"
ON public.team_messages FOR UPDATE
TO authenticated, service_role
USING (public.is_owner())
WITH CHECK (public.is_owner());

-- Update guard trigger: prevents non-owners from editing, freezes immutable columns,
-- and automatically sets is_edited = TRUE and edited_at = now()
CREATE OR REPLACE FUNCTION public.trg_team_messages_update_guard()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT public.is_owner() THEN
        RAISE EXCEPTION 'Access denied: Only owners/admins can edit team messages.';
    END IF;

    -- Freeze immutable identity and creation fields
    NEW.id := OLD.id;
    NEW.sender_id := OLD.sender_id;
    NEW.sender_name := OLD.sender_name;
    NEW.sender_role := OLD.sender_role;
    NEW.created_at := OLD.created_at;

    -- Stamp moderation flags
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

-- ============================================================================
-- 5. Authoritative RPCs for Admin Moderation
-- ============================================================================

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
    v_updated RECORD;
BEGIN
    IF NOT public.is_owner() THEN
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
GRANT EXECUTE ON FUNCTION public.admin_edit_team_message(UUID, TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_delete_team_message(
    p_message_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
    IF NOT public.is_owner() THEN
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
GRANT EXECUTE ON FUNCTION public.admin_delete_team_message(UUID) TO authenticated, service_role;
