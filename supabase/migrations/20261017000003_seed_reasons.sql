-- Migration: 20261017000003_seed_reasons.sql
-- Description: Seed default reasons (ARCHITECTURE.md Sec 10.2) and default settings

-- Seed Default Settings
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
