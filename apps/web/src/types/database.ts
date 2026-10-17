export type UserRole = 'owner' | 'manager' | 'caller';

export type LeadStatus =
  | 'new'
  | 'assigned'
  | 'in_progress'
  | 'called'
  | 'interested'
  | 'not_interested'
  | 'follow_up'
  | 'unreachable'
  | 'do_not_call';

export type DndStatus = 'unknown' | 'clear' | 'registered';
export type CallSource = 'device_log' | 'provider';
export type CallStatus =
  | 'initiated'
  | 'caller_ringing'
  | 'caller_no_answer'
  | 'client_ringing'
  | 'connected'
  | 'client_no_answer'
  | 'client_busy'
  | 'failed'
  | 'completed'
  | 'awaiting_disposition'
  | 'closed';

export type DialAttemptStatus = 'open' | 'matched' | 'no_call_detected' | 'closed';
export type DeviceCallType = 'outgoing' | 'incoming' | 'missed';
export type DispositionOutcome = 'interested' | 'not_interested' | 'not_connected';
export type FollowUpType = 'callback' | 'proposal' | 'demo' | 'meeting';
export type FollowUpStatus = 'open' | 'done' | 'cancelled';
export type FlagSeverity = 'info' | 'warn' | 'high';
export type FlagStatus = 'open' | 'dismissed' | 'confirmed';

export interface Profile {
  id: string;
  full_name: string;
  role: UserRole;
  email: string | null;
  mobile_e164: string | null;
  mobile_verified_at: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface LeadBatch {
  id: string;
  name: string;
  source: string | null;
  created_by: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface Lead {
  id: string;
  batch_id: string | null;
  phone_e164: string;
  name: string | null;
  company: string | null;
  notes: string | null;
  assigned_to: string | null;
  assigned_at: string | null;
  status: LeadStatus;
  dnd_status: DndStatus;
  attempt_count: number;
  last_call_at: string | null;
  next_follow_up_at: string | null;
  created_at: string;
  updated_at: string;
  // joined relation
  assigned_caller?: Profile | null;
}

export interface Device {
  id: string;
  profile_id: string;
  device_label: string | null;
  app_version: string | null;
  last_sync_at: string | null;
  permissions_ok: boolean;
  created_at: string;
  updated_at: string;
}

export interface DialAttempt {
  id: string;
  lead_id: string;
  caller_id: string;
  device_id: string | null;
  dialed_at: string;
  status: DialAttemptStatus;
  created_at: string;
  updated_at: string;
}

export interface DeviceCallLogEntry {
  id: string;
  dial_attempt_id: string | null;
  device_id: string;
  number_e164: string;
  call_type: DeviceCallType;
  started_at: string;
  duration_secs: number;
  sim_slot: string | null;
  uploaded_at: string;
  clock_skew_secs: number;
  dedupe_key: string;
  created_at: string;
}

export interface Call {
  id: string;
  lead_id: string;
  caller_id: string;
  device_id: string | null;
  device_call_log_entry_id: string | null;
  source: CallSource;
  provider: string | null;
  provider_call_id: string | null;
  virtual_number: string | null;
  status: CallStatus;
  initiated_at: string;
  caller_answered_at: string | null;
  client_answered_at: string | null;
  ended_at: string | null;
  caller_leg_secs: number | null;
  client_leg_secs: number | null;
  talk_secs: number;
  end_reason: string | null;
  recording_path: string | null;
  cost_estimate: number | null;
  created_at: string;
  updated_at: string;
  // relations
  lead?: Lead | null;
  caller?: Profile | null;
  disposition?: Disposition | null;
}

export interface Reason {
  id: string;
  outcome: DispositionOutcome;
  label: string;
  sort_order: number;
  is_active: boolean;
  created_at: string;
}

export interface Disposition {
  id: string;
  call_id: string;
  lead_id: string;
  caller_id: string;
  connected: boolean;
  caller_claimed_connected: boolean | null;
  outcome: DispositionOutcome;
  reason_ids: string[];
  other_reason_text: string | null;
  note: string | null;
  submitted_at: string;
  seconds_after_call_end: number | null;
  created_at: string;
}

export interface Flag {
  id: string;
  call_id: string | null;
  caller_id: string;
  dial_attempt_id: string | null;
  rule_code: string;
  severity: FlagSeverity;
  details: Record<string, unknown>;
  status: FlagStatus;
  reviewed_by: string | null;
  review_note: string | null;
  created_at: string;
  updated_at: string;
}
