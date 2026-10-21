"use client";

import React, { useState, useEffect, useRef, useMemo } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { normalizePhoneE164 } from "@/lib/phone";
import {
  PhoneCall,
  Phone,
  PhoneOff,
  Clock,
  MessageSquare,
  User,
  ShieldCheck,
  ShieldAlert,
  Search,
  Filter,
  CheckCircle2,
  XCircle,
  AlertCircle,
  Loader2,
  LogOut,
  Send,
  Calendar,
  ChevronDown,
  ChevronUp,
  Sparkles,
  ExternalLink,
  Target,
  Flame,
  Check,
  Smartphone,
  LayoutDashboard,
  Play,
  Square,
  FileText,
} from "lucide-react";

interface Profile {
  id: string;
  full_name: string;
  role: "owner" | "manager" | "caller";
  email: string | null;
  mobile_e164: string | null;
}

interface Lead {
  id: string;
  name: string | null;
  phone_e164: string;
  company: string | null;
  city: string | null;
  status: string;
  attempt_count: number;
  last_call_at: string | null;
  notes: string | null;
  assigned_to: string | null;
  next_follow_up_at: string | null;
}

interface Reason {
  id: string;
  outcome: string;
  label: string;
  sort_order: number;
}

interface PitchScript {
  id: string;
  title: string;
  category: string;
  content: string;
}

interface TeamMessage {
  id: string;
  sender_id: string;
  content: string;
  created_at: string;
  sender_name?: string;
  sender_role?: string;
  is_edited?: boolean;
}

interface CallRecord {
  id: string;
  lead_id: string;
  talk_secs: number;
  initiated_at: string;
  status: string;
  lead?: {
    name: string | null;
    phone_e164: string;
    company: string | null;
  };
  disposition?: {
    outcome: string;
    note: string | null;
    connected: boolean;
  };
}

export default function CallerAppPage() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  // Tabs: queue, history, chat, shift
  const [activeTab, setActiveTab] = useState<"queue" | "history" | "chat" | "shift">("queue");

  // User state
  const [profile, setProfile] = useState<Profile | null>(null);
  const [deviceId, setDeviceId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // Work Session & Duty State
  const [isClockedIn, setIsClockedIn] = useState(false);
  const [currentSessionId, setCurrentSessionId] = useState<string | null>(null);
  const [sessionStartTime, setSessionStartTime] = useState<Date | null>(null);
  const [activeSecondsToday, setActiveSecondsToday] = useState(0);
  const [clockLoading, setClockLoading] = useState(false);

  // Daily Quota State
  const [callsToday, setCallsToday] = useState(0);
  const [connectedToday, setConnectedToday] = useState(0);
  const [interestedToday, setInterestedToday] = useState(0);
  const [talkSecondsToday, setTalkSecondsToday] = useState(0);
  const quotaTarget = 50;

  // Leads & Queue
  const [leads, setLeads] = useState<Lead[]>([]);
  const [searchQuery, setSearchQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [leadsLoading, setLeadsLoading] = useState(false);

  // Pitch scripts & reasons
  const [pitchScripts, setPitchScripts] = useState<PitchScript[]>([]);
  const [reasons, setReasons] = useState<Reason[]>([]);
  const [selectedScriptTab, setSelectedScriptTab] = useState<string>("opener");

  // Active Call State
  const [activeCall, setActiveCall] = useState<{
    lead: Lead;
    attemptId: string;
    startedAt: Date;
  } | null>(null);
  const [callElapsedSecs, setCallElapsedSecs] = useState(0);
  const [isPitchExpanded, setIsPitchExpanded] = useState(false);

  // Post-Call Disposition Sheet State
  const [dispositionOpen, setDispositionOpen] = useState(false);
  const [postCallLead, setPostCallLead] = useState<Lead | null>(null);
  const [postCallAttemptId, setPostCallAttemptId] = useState<string | null>(null);
  const [postCallDuration, setPostCallDuration] = useState(0);
  const [callerClaimedConnected, setCallerClaimedConnected] = useState(false);
  const [selectedOutcome, setSelectedOutcome] = useState<"interested" | "callback" | "no_answer" | "busy" | "wrong_number" | "not_interested">("interested");
  const [selectedReasonIds, setSelectedReasonIds] = useState<string[]>([]);
  const [callNotes, setCallNotes] = useState("");
  const [followUpDate, setFollowUpDate] = useState("");
  const [submittingDisposition, setSubmittingDisposition] = useState(false);

  // Off-Duty Blocking Modal
  const [offDutyModalOpen, setOffDutyModalOpen] = useState(false);

  // Team Chat
  const [messages, setMessages] = useState<TeamMessage[]>([]);
  const [newMessageText, setNewMessageText] = useState("");
  const [sendingMessage, setSendingMessage] = useState(false);
  const chatScrollRef = useRef<HTMLDivElement>(null);

  // Call History
  const [callHistory, setCallHistory] = useState<CallRecord[]>([]);

  // Feedback Toast
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 3500);
  };

  // 1. Initial Load: Authenticate & Load Profile
  useEffect(() => {
    async function initUser() {
      setLoading(true);
      const { data: { user } } = await supabase.auth.getUser();

      if (!user) {
        router.push("/login");
        return;
      }

      // Fetch profile
      const { data: prof, error: profErr } = await supabase
        .from("profiles")
        .select("id, full_name, role, email, mobile_e164")
        .eq("id", user.id)
        .single();

      if (profErr || !prof) {
        router.push("/login?error=no_profile");
        return;
      }

      setProfile(prof as Profile);

      // Ensure a web device record exists for call logging verification
      const { data: existingDevs } = await supabase
        .from("devices")
        .select("id")
        .eq("profile_id", prof.id)
        .order("created_at", { ascending: false })
        .limit(1);

      if (existingDevs && existingDevs.length > 0) {
        setDeviceId(existingDevs[0].id);
      } else {
        const { data: newDev } = await supabase
          .from("devices")
          .insert({
            profile_id: prof.id,
            device_label: "iOS Web App",
            app_version: "1.0.0",
            permissions_ok: true,
          })
          .select("id")
          .single();

        if (newDev) {
          setDeviceId(newDev.id);
        }
      }

      setLoading(false);
    }

    initUser();
  }, [supabase, router]);

  // 2. Fetch Work Status & Daily Quota
  const fetchWorkAndQuota = async (callerId: string) => {
    try {
      // 1. RPC: get_caller_work_status
      const { data: workStatus } = await supabase.rpc("get_caller_work_status");
      if (workStatus) {
        setIsClockedIn(workStatus.is_clocked_in === true);
        setCurrentSessionId(workStatus.current_session_id || null);
        setActiveSecondsToday(workStatus.active_seconds_today || 0);
        if (workStatus.started_at) {
          setSessionStartTime(new Date(workStatus.started_at));
        }
      }

      // 2. Fetch today's calls & stats
      const now = new Date();
      const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();

      const { data: calls } = await supabase
        .from("calls")
        .select("id, lead_id, talk_secs, status, initiated_at, lead:leads(name, phone_e164, company), disposition:dispositions(outcome, note, connected)")
        .eq("caller_id", callerId)
        .gte("initiated_at", startOfDay)
        .order("initiated_at", { ascending: false });

      if (calls) {
        setCallsToday(calls.length);
        let connectedCount = 0;
        let interestedCount = 0;
        let totalTalk = 0;

        calls.forEach((c: any) => {
          const talk = c.talk_secs || 0;
          totalTalk += talk;
          const disp = Array.isArray(c.disposition) ? c.disposition[0] : c.disposition;
          if (talk >= 10 || disp?.connected === true) {
            connectedCount++;
          }
          if (disp?.outcome === "interested") {
            interestedCount++;
          }
        });

        setConnectedToday(connectedCount);
        setInterestedToday(interestedCount);
        setTalkSecondsToday(totalTalk);

        const mapped: CallRecord[] = (calls as any[]).map((c) => ({
          id: c.id,
          lead_id: c.lead_id,
          talk_secs: c.talk_secs || 0,
          initiated_at: c.initiated_at,
          status: c.status,
          lead: Array.isArray(c.lead) ? c.lead[0] : c.lead,
          disposition: Array.isArray(c.disposition) ? c.disposition[0] : c.disposition,
        }));
        setCallHistory(mapped);
      }
    } catch (e) {
      console.error("Error fetching work & quota status:", e);
    }
  };

  // 3. Fetch Leads for Caller
  const fetchLeads = async (callerProfile: Profile) => {
    setLeadsLoading(true);
    try {
      let query = supabase
        .from("leads")
        .select("id, name, phone_e164, company, city, status, attempt_count, last_call_at, notes, assigned_to, next_follow_up_at")
        .order("attempt_count", { ascending: true })
        .order("created_at", { ascending: false });

      // If caller, RLS enforces assigned_to = user.id.
      // If owner, let them see leads assigned to them or unassigned/in_progress leads.
      if (callerProfile.role === "caller") {
        query = query.eq("assigned_to", callerProfile.id);
      } else {
        // For owner testing as caller: show leads assigned to owner or first 25 leads
        query = query.limit(30);
      }

      const { data, error } = await query;
      if (!error && data) {
        setLeads(data as Lead[]);
      }
    } catch (e) {
      console.error("Error fetching leads:", e);
    } finally {
      setLeadsLoading(false);
    }
  };

  // 4. Fetch Scripts and Reasons
  const fetchScriptsAndReasons = async () => {
    try {
      const [scriptsRes, reasonsRes] = await Promise.all([
        supabase.from("pitch_scripts").select("*").order("category"),
        supabase.from("reasons").select("*").eq("is_active", true).order("sort_order"),
      ]);

      if (scriptsRes.data) {
        setPitchScripts(scriptsRes.data as PitchScript[]);
      }
      if (reasonsRes.data) {
        setReasons(reasonsRes.data as Reason[]);
      }
    } catch (e) {
      console.error("Error fetching scripts/reasons:", e);
    }
  };

  // 5. Fetch Team Chat & Subscribe to Realtime
  useEffect(() => {
    if (!profile) return;

    // Fetch initial chat messages
    async function loadMessages() {
      const { data } = await supabase
        .from("team_messages")
        .select(`
          id,
          sender_id,
          content,
          created_at,
          sender:profiles!team_messages_sender_id_fkey(full_name, role)
        `)
        .order("created_at", { ascending: true })
        .limit(100);

      if (data) {
        const formatted: TeamMessage[] = data.map((m: any) => ({
          id: m.id,
          sender_id: m.sender_id,
          content: m.content,
          created_at: m.created_at,
          sender_name: m.sender?.full_name || "Team Member",
          sender_role: m.sender?.role || "caller",
        }));
        setMessages(formatted);
      }
    }

    loadMessages();

    // Subscribe to realtime team_messages
    const channel = supabase
      .channel("public:team_messages")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "team_messages" },
        async (payload) => {
          if (payload.eventType === "INSERT") {
            const newRow = payload.new as any;
            // Fetch sender profile info
            const { data: senderProf } = await supabase
              .from("profiles")
              .select("full_name, role")
              .eq("id", newRow.sender_id)
              .single();

            const newMsg: TeamMessage = {
              id: newRow.id,
              sender_id: newRow.sender_id,
              content: newRow.content,
              created_at: newRow.created_at,
              sender_name: senderProf?.full_name || "Team Member",
              sender_role: senderProf?.role || "caller",
            };

            setMessages((prev) => {
              // Deduplicate
              if (prev.some((m) => m.id === newMsg.id)) return prev;
              return [...prev, newMsg];
            });
          } else if (payload.eventType === "DELETE") {
            const oldId = payload.old.id;
            setMessages((prev) => prev.filter((m) => m.id !== oldId));
          } else if (payload.eventType === "UPDATE") {
            const updated = payload.new as any;
            setMessages((prev) =>
              prev.map((m) =>
                m.id === updated.id
                  ? { ...m, content: updated.content, is_edited: true }
                  : m
              )
            );
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [profile, supabase]);

  // Trigger loads once profile is ready
  useEffect(() => {
    if (profile) {
      fetchWorkAndQuota(profile.id);
      fetchLeads(profile);
      fetchScriptsAndReasons();
    }
  }, [profile]);

  // Live timer for active work session
  useEffect(() => {
    let interval: NodeJS.Timeout | null = null;
    if (isClockedIn) {
      interval = setInterval(() => {
        setActiveSecondsToday((prev) => prev + 1);
      }, 1000);
    }
    return () => {
      if (interval) clearInterval(interval);
    };
  }, [isClockedIn]);

  // Live stopwatch for active call
  useEffect(() => {
    let interval: NodeJS.Timeout | null = null;
    if (activeCall) {
      interval = setInterval(() => {
        setCallElapsedSecs((prev) => prev + 1);
      }, 1000);
    } else {
      setCallElapsedSecs(0);
    }
    return () => {
      if (interval) clearInterval(interval);
    };
  }, [activeCall]);

  // Auto-scroll chat to bottom
  useEffect(() => {
    if (activeTab === "chat" && chatScrollRef.current) {
      chatScrollRef.current.scrollTop = chatScrollRef.current.scrollHeight;
    }
  }, [messages, activeTab]);

  // ==========================================================================
  // Work Shift Controls (Clock In / Clock Out)
  // ==========================================================================
  const handleClockIn = async () => {
    setClockLoading(true);
    try {
      const { data, error } = await supabase.rpc("clock_in");
      if (error) {
        showToast("Error clocking in: " + error.message);
      } else {
        setIsClockedIn(true);
        setCurrentSessionId(data?.session_id || null);
        setSessionStartTime(new Date());
        showToast("🟢 Shift started! You are now ON DUTY.");
        if (profile) fetchWorkAndQuota(profile.id);
      }
    } catch (err: any) {
      showToast("Clock-in failed: " + err.message);
    } finally {
      setClockLoading(false);
      setOffDutyModalOpen(false);
    }
  };

  const handleClockOut = async () => {
    if (!confirm("Are you sure you want to end your shift and clock out? Call tracking will stop.")) {
      return;
    }
    setClockLoading(true);
    try {
      const { error } = await supabase.rpc("clock_out", {
        p_session_id: currentSessionId,
      });
      if (error) {
        showToast("Error clocking out: " + error.message);
      } else {
        setIsClockedIn(false);
        setCurrentSessionId(null);
        showToast("⏸️ Shift ended. You are now OFF DUTY.");
        if (profile) fetchWorkAndQuota(profile.id);
      }
    } catch (err: any) {
      showToast("Clock-out failed: " + err.message);
    } finally {
      setClockLoading(false);
    }
  };

  // ==========================================================================
  // Call Initiation & Active Call Management
  // ==========================================================================
  const handleInitiateCall = async (lead: Lead) => {
    // 1. Shift check: Callers must be clocked in
    if (!isClockedIn) {
      setOffDutyModalOpen(true);
      return;
    }

    try {
      // 2. Start dial attempt in database
      const { data, error } = await supabase.rpc("start_dial_attempt", {
        p_lead_id: lead.id,
        p_device_id: deviceId,
      });

      if (error) {
        showToast("Cannot start call: " + error.message);
        return;
      }

      const attemptId = data?.dial_attempt_id;
      const started = new Date();

      setActiveCall({
        lead,
        attemptId,
        startedAt: started,
      });
      setCallElapsedSecs(0);

      // 3. Trigger native phone dialer via tel:
      // On iOS Safari, this opens the native iPhone dialer confirmation sheet: "Call +91 98765 43210?"
      window.location.href = `tel:${lead.phone_e164}`;
    } catch (err: any) {
      showToast("Call launch error: " + err.message);
    }
  };

  const handleEndCall = () => {
    if (!activeCall) return;

    const measuredDuration = callElapsedSecs;
    setPostCallLead(activeCall.lead);
    setPostCallAttemptId(activeCall.attemptId);
    setPostCallDuration(measuredDuration);
    setCallerClaimedConnected(measuredDuration >= 10);
    setSelectedOutcome(measuredDuration >= 10 ? "interested" : "no_answer");
    setSelectedReasonIds([]);
    setCallNotes("");
    setFollowUpDate("");

    // Close HUD and open Post-Call Disposition Sheet
    setActiveCall(null);
    setDispositionOpen(true);
  };

  // ==========================================================================
  // Post-Call Disposition Submission
  // ==========================================================================
  const handleSubmitDisposition = async () => {
    if (!postCallLead || !postCallAttemptId) return;

    if (callerClaimedConnected && postCallDuration < 10) {
      if (!confirm("This call was under 10 seconds. Are you sure you connected with the customer?")) {
        return;
      }
    }

    setSubmittingDisposition(true);

    try {
      // Map UI outcome to Postgres disposition_outcome
      let dbOutcome: "interested" | "not_interested" | "not_connected" = "not_connected";
      if (selectedOutcome === "interested" || selectedOutcome === "callback") {
        dbOutcome = "interested";
      } else if (selectedOutcome === "not_interested") {
        dbOutcome = "not_interested";
      } else {
        dbOutcome = "not_connected";
      }

      const now = new Date();
      const callStartedAt = new Date(now.getTime() - postCallDuration * 1000).toISOString();

      const params: any = {
        p_dial_attempt_id: postCallAttemptId,
        p_device_id: deviceId,
        p_number_e164: postCallLead.phone_e164,
        p_call_type: "outgoing",
        p_started_at: callStartedAt,
        p_duration_secs: postCallDuration,
        p_sim_slot: "iOS Web",
        p_clock_skew_secs: 0,
        p_caller_claimed_connected: callerClaimedConnected,
        p_outcome: dbOutcome,
        p_reason_ids: selectedReasonIds,
        p_other_reason_text: null,
        p_note: callNotes.trim() || null,
        p_seconds_after_call_end: 0,
        p_follow_up_due_at: followUpDate ? new Date(followUpDate).toISOString() : null,
        p_follow_up_type: followUpDate ? "callback" : null,
        p_evidence_source: "manual_verification",
      };

      let { data, error } = await supabase.rpc("submit_call_dialog", params);

      // Fallback in case schema cache rejects p_evidence_source
      if (error && (error.message.includes("p_evidence_source") || error.code === "PGRST202")) {
        delete params.p_evidence_source;
        const res = await supabase.rpc("submit_call_dialog", params);
        error = res.error;
        data = res.data;
      }

      if (error) {
        showToast("Error recording call: " + error.message);
      } else {
        showToast("✅ Call recorded successfully! Queue updated.");
        setDispositionOpen(false);
        setPostCallLead(null);
        setPostCallAttemptId(null);

        // Refresh leads and today's quota
        if (profile) {
          fetchLeads(profile);
          fetchWorkAndQuota(profile.id);
        }
      }
    } catch (err: any) {
      showToast("Submission failed: " + err.message);
    } finally {
      setSubmittingDisposition(false);
    }
  };

  // ==========================================================================
  // Team Chat Messaging
  // ==========================================================================
  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newMessageText.trim() || !profile) return;

    setSendingMessage(true);
    const content = newMessageText.trim();
    setNewMessageText("");

    try {
      const { error } = await supabase.from("team_messages").insert({
        sender_id: profile.id,
        content,
      });

      if (error) {
        showToast("Failed to send message: " + error.message);
      }
    } catch (err: any) {
      showToast("Error: " + err.message);
    } finally {
      setSendingMessage(false);
    }
  };

  // Filter leads based on search query and status filter
  const filteredLeads = useMemo(() => {
    return leads.filter((lead) => {
      const q = searchQuery.toLowerCase();
      const matchName = lead.name?.toLowerCase().includes(q) ?? false;
      const matchCompany = lead.company?.toLowerCase().includes(q) ?? false;
      const matchPhone = lead.phone_e164.includes(q);

      const matchesSearch = !searchQuery || matchName || matchCompany || matchPhone;

      if (!matchesSearch) return false;

      if (statusFilter === "all") return true;
      if (statusFilter === "pending") return lead.attempt_count === 0 || lead.status === "new" || lead.status === "assigned";
      if (statusFilter === "callbacks") return lead.status === "in_progress" || lead.next_follow_up_at !== null;
      if (statusFilter === "interested") return lead.status === "interested";
      if (statusFilter === "not_interested") return lead.status === "not_interested";

      return true;
    });
  }, [leads, searchQuery, statusFilter]);

  // Format seconds to HH:MM:SS
  const formatTime = (totalSeconds: number) => {
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    if (hours > 0) {
      return `${hours}h ${minutes}m ${seconds}s`;
    }
    return `${minutes}m ${seconds}s`;
  };

  const formatStopwatch = (totalSeconds: number) => {
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  };

  // Available reasons for the selected outcome in disposition sheet
  const activeReasons = useMemo(() => {
    let outcomeGroup = "not_connected";
    if (selectedOutcome === "interested" || selectedOutcome === "callback") {
      outcomeGroup = "interested";
    } else if (selectedOutcome === "not_interested") {
      outcomeGroup = "not_interested";
    }
    return reasons.filter((r) => r.outcome === outcomeGroup);
  }, [reasons, selectedOutcome]);

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center bg-slate-950 text-white">
        <div className="flex flex-col items-center gap-3">
          <Loader2 className="h-8 w-8 animate-spin text-indigo-500" />
          <div className="text-sm font-medium text-slate-400">Loading Orvyq Caller...</div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col min-h-screen-safe bg-slate-950 text-slate-100 font-sans selection:bg-indigo-600 selection:text-white pb-24">
      {/* Toast Notification */}
      {toastMessage && (
        <div className="fixed top-4 left-1/2 -translate-x-1/2 z-50 px-4 py-2.5 rounded-2xl bg-indigo-600 text-white text-xs font-semibold shadow-xl shadow-indigo-600/40 flex items-center gap-2 animate-in fade-in slide-in-from-top-4 duration-200 max-w-[90vw]">
          <Sparkles className="h-4 w-4 shrink-0" />
          <span className="truncate">{toastMessage}</span>
        </div>
      )}

      {/* Top Header Bar */}
      <header className="sticky top-0 z-40 bg-slate-900/90 backdrop-blur-md border-b border-slate-800/80 px-4 py-3 pt-safe flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="h-8 w-8 rounded-xl bg-indigo-600 flex items-center justify-center text-white shadow-md shadow-indigo-600/30">
            <PhoneCall className="h-4 w-4" />
          </div>
          <div>
            <div className="text-sm font-bold text-white tracking-tight flex items-center gap-1.5 leading-none">
              Orvyqmedia
              <span className="text-[10px] font-medium px-1.5 py-0.5 rounded-md bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                iOS Caller
              </span>
            </div>
            <div className="text-[11px] text-slate-400 mt-1 truncate max-w-[140px]">
              {profile?.full_name || "Caller"}
            </div>
          </div>
        </div>

        {/* Shift Duty Status Pill & Quick Clock Toggle */}
        <div className="flex items-center gap-2">
          {isClockedIn ? (
            <button
              onClick={handleClockOut}
              disabled={clockLoading}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-xs font-semibold active:scale-95 transition"
            >
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
              </span>
              <span>ON DUTY</span>
              <span className="font-mono text-[11px] text-emerald-300 pl-0.5">
                {formatStopwatch(activeSecondsToday)}
              </span>
            </button>
          ) : (
            <button
              onClick={handleClockIn}
              disabled={clockLoading}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-slate-800 border border-slate-700 text-slate-300 hover:text-white text-xs font-semibold active:scale-95 transition"
            >
              <span className="h-2 w-2 rounded-full bg-slate-500" />
              <span>OFF DUTY</span>
              <span className="text-[10px] text-indigo-400 font-bold ml-1">Clock In</span>
            </button>
          )}

          {/* If Owner: Option to view desktop dashboard */}
          {profile?.role === "owner" && (
            <button
              onClick={() => router.push("/")}
              title="Admin Dashboard"
              className="p-1.5 rounded-lg bg-slate-800/80 hover:bg-slate-700 text-slate-400 hover:text-white transition"
            >
              <LayoutDashboard className="h-4 w-4 text-indigo-400" />
            </button>
          )}
        </div>
      </header>

      {/* Main Content Rendered by Tab */}
      <main className="flex-1 max-w-lg mx-auto w-full px-4 py-4 space-y-4">
        {/* ================================================================= */}
        {/* TAB 1: LEAD QUEUE & COLD CALLING                                 */}
        {/* ================================================================= */}
        {activeTab === "queue" && (
          <div className="space-y-4">
            {/* Duty Warning Banner when Clocked Out */}
            {!isClockedIn && (
              <div className="p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/25 flex items-center justify-between gap-3 text-amber-300 text-xs animate-in fade-in">
                <div className="flex items-center gap-2.5">
                  <ShieldAlert className="h-5 w-5 shrink-0 text-amber-400" />
                  <div>
                    <div className="font-bold text-amber-200">Off Duty Shift Guard</div>
                    <div className="text-[11px] text-amber-400/80">
                      Calls and tracking are locked until you clock in.
                    </div>
                  </div>
                </div>
                <button
                  onClick={handleClockIn}
                  disabled={clockLoading}
                  className="px-3 py-1.5 rounded-xl bg-amber-500 text-slate-950 font-bold text-xs shadow-md shadow-amber-500/20 active:scale-95 transition shrink-0"
                >
                  Start Shift
                </button>
              </div>
            )}

            {/* Daily Quota Card */}
            <div className="p-4 rounded-2xl bg-gradient-to-br from-slate-900 to-slate-900/80 border border-slate-800 shadow-sm space-y-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Target className="h-4 w-4 text-indigo-400" />
                  <span className="text-xs font-bold text-white uppercase tracking-wider">
                    Today&apos;s Quota Progress
                  </span>
                </div>
                <span className="text-xs font-semibold text-slate-400">
                  Target: <strong className="text-white">{quotaTarget}</strong> calls
                </span>
              </div>

              {/* Progress Bar */}
              <div className="w-full bg-slate-800 h-2.5 rounded-full overflow-hidden">
                <div
                  className="h-full bg-indigo-500 transition-all duration-500"
                  style={{ width: `${Math.min(100, (callsToday / quotaTarget) * 100)}%` }}
                />
              </div>

              {/* Metrics Grid */}
              <div className="grid grid-cols-4 gap-2 pt-1 text-center">
                <div className="p-2 rounded-xl bg-slate-800/60 border border-slate-800/80">
                  <div className="text-base font-extrabold text-white">{callsToday}</div>
                  <div className="text-[10px] text-slate-400 uppercase font-semibold">Calls</div>
                </div>
                <div className="p-2 rounded-xl bg-slate-800/60 border border-slate-800/80">
                  <div className="text-base font-extrabold text-emerald-400">{connectedToday}</div>
                  <div className="text-[10px] text-slate-400 uppercase font-semibold">Conn. (≥10s)</div>
                </div>
                <div className="p-2 rounded-xl bg-slate-800/60 border border-slate-800/80">
                  <div className="text-base font-extrabold text-indigo-400">{interestedToday}</div>
                  <div className="text-[10px] text-slate-400 uppercase font-semibold">Interested</div>
                </div>
                <div className="p-2 rounded-xl bg-slate-800/60 border border-slate-800/80">
                  <div className="text-base font-extrabold text-amber-400">{Math.round(talkSecondsToday / 60)}m</div>
                  <div className="text-[10px] text-slate-400 uppercase font-semibold">Talk Time</div>
                </div>
              </div>
            </div>

            {/* Search and Filters */}
            <div className="space-y-2.5">
              <div className="relative">
                <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                <input
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Search lead name, company, or phone..."
                  className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-slate-900 border border-slate-800 text-sm text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition"
                />
              </div>

              {/* Status Filter Chips */}
              <div className="flex items-center gap-1.5 overflow-x-auto pb-1 text-xs no-scrollbar">
                {[
                  { id: "all", label: `All (${leads.length})` },
                  { id: "pending", label: "To Call" },
                  { id: "callbacks", label: "Callbacks" },
                  { id: "interested", label: "Interested" },
                  { id: "not_interested", label: "Dropped" },
                ].map((f) => (
                  <button
                    key={f.id}
                    onClick={() => setStatusFilter(f.id)}
                    className={`px-3 py-1.5 rounded-xl font-medium shrink-0 transition ${
                      statusFilter === f.id
                        ? "bg-indigo-600 text-white shadow-sm shadow-indigo-600/30"
                        : "bg-slate-900 text-slate-400 hover:text-white border border-slate-800"
                    }`}
                  >
                    {f.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Lead Queue Cards */}
            <div className="space-y-3">
              {leadsLoading ? (
                <div className="py-12 text-center text-slate-500 text-sm flex items-center justify-center gap-2">
                  <Loader2 className="h-4 w-4 animate-spin text-indigo-400" />
                  Loading assigned leads...
                </div>
              ) : filteredLeads.length === 0 ? (
                <div className="p-8 text-center rounded-2xl bg-slate-900/60 border border-slate-800/80 text-slate-400 text-sm space-y-2">
                  <PhoneOff className="h-8 w-8 mx-auto text-slate-600" />
                  <div className="font-semibold text-white">No Leads in This Queue</div>
                  <div className="text-xs text-slate-500">
                    {searchQuery
                      ? "No leads matched your search query."
                      : "You have completed all leads in this filter!"}
                  </div>
                </div>
              ) : (
                filteredLeads.map((lead) => {
                  const norm = normalizePhoneE164(lead.phone_e164);
                  const displayPhone = norm.formatted || lead.phone_e164;
                  const cleanPhone = lead.phone_e164.replace(/\D/g, "");

                  return (
                    <div
                      key={lead.id}
                      className="p-4 rounded-2xl bg-slate-900 border border-slate-800/90 shadow-sm space-y-3 transition hover:border-slate-700"
                    >
                      {/* Lead Title & Meta */}
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <div className="font-bold text-white text-base leading-tight">
                            {lead.name || "Business Lead"}
                          </div>
                          {(lead.company || lead.city) && (
                            <div className="text-xs text-slate-400 mt-0.5">
                              {[lead.company, lead.city].filter(Boolean).join(" • ")}
                            </div>
                          )}
                        </div>

                        {/* Status Badge */}
                        <span
                          className={`text-[10px] font-bold px-2 py-0.5 rounded-full uppercase tracking-wider shrink-0 ${
                            lead.status === "interested"
                              ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/25"
                              : lead.status === "in_progress"
                              ? "bg-sky-500/10 text-sky-400 border border-sky-500/25"
                              : lead.status === "not_interested"
                              ? "bg-slate-800 text-slate-400 border border-slate-700"
                              : "bg-indigo-500/10 text-indigo-400 border border-indigo-500/25"
                          }`}
                        >
                          {lead.status.replace("_", " ")}
                        </span>
                      </div>

                      {/* Phone & Local Time */}
                      <div className="flex items-center justify-between text-xs text-slate-400 pt-1">
                        <div className="font-mono text-slate-300 font-semibold tracking-wide flex items-center gap-1.5">
                          <Phone className="h-3.5 w-3.5 text-indigo-400" />
                          {displayPhone}
                        </div>
                        <div className="flex items-center gap-1 text-[11px] text-slate-500">
                          <Clock className="h-3 w-3" />
                          <span>Attempt: {lead.attempt_count}</span>
                        </div>
                      </div>

                      {/* Notes snippet if any */}
                      {lead.notes && (
                        <div className="p-2 rounded-xl bg-slate-950/60 border border-slate-800/60 text-[11px] text-slate-300 italic">
                          &ldquo;{lead.notes}&rdquo;
                        </div>
                      )}

                      {/* Action Buttons: WhatsApp & Call Now */}
                      <div className="flex items-center gap-2 pt-1">
                        {/* WhatsApp Button */}
                        <a
                          href={`https://wa.me/${cleanPhone}?text=${encodeURIComponent(
                            `Hi ${lead.name || ""}, this is ${profile?.full_name || "Orvyqmedia"}. Following up regarding our discussion.`
                          )}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="flex-1 flex items-center justify-center gap-1.5 py-2.5 px-3 rounded-xl bg-emerald-950/40 hover:bg-emerald-900/40 border border-emerald-500/30 text-emerald-400 text-xs font-semibold transition active:scale-95"
                        >
                          <MessageSquare className="h-3.5 w-3.5" />
                          <span>WhatsApp</span>
                        </a>

                        {/* Call Now Button */}
                        <button
                          onClick={() => handleInitiateCall(lead)}
                          className="flex-2 flex items-center justify-center gap-2 py-2.5 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold shadow-md shadow-indigo-600/30 transition active:scale-95"
                        >
                          <PhoneCall className="h-4 w-4" />
                          <span>Call Now</span>
                        </button>
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        )}

        {/* ================================================================= */}
        {/* TAB 2: CALL HISTORY                                              */}
        {/* ================================================================= */}
        {activeTab === "history" && (
          <div className="space-y-3">
            <div className="flex items-center justify-between pb-1">
              <h2 className="text-sm font-bold text-white uppercase tracking-wider">
                Today&apos;s Verified Call History
              </h2>
              <span className="text-xs text-slate-400">{callHistory.length} calls logged</span>
            </div>

            {callHistory.length === 0 ? (
              <div className="p-8 text-center rounded-2xl bg-slate-900 border border-slate-800 text-slate-400 text-sm space-y-2">
                <Clock className="h-8 w-8 mx-auto text-slate-600" />
                <div className="font-semibold text-white">No Calls Logged Yet Today</div>
                <div className="text-xs text-slate-500">
                  Calls you place and record will appear here in chronological order.
                </div>
              </div>
            ) : (
              callHistory.map((item) => (
                <div
                  key={item.id}
                  className="p-3.5 rounded-2xl bg-slate-900 border border-slate-800/80 space-y-2"
                >
                  <div className="flex items-start justify-between">
                    <div>
                      <div className="font-bold text-white text-sm">
                        {item.lead?.name || "Business Lead"}
                      </div>
                      <div className="text-xs text-slate-400 font-mono">
                        {item.lead?.phone_e164 || "Phone"}
                      </div>
                    </div>
                    <span
                      className={`text-[10px] font-bold px-2 py-0.5 rounded-full uppercase ${
                        item.disposition?.outcome === "interested"
                          ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/30"
                          : item.disposition?.outcome === "not_interested"
                          ? "bg-slate-800 text-slate-400 border border-slate-700"
                          : "bg-amber-500/10 text-amber-400 border border-amber-500/30"
                      }`}
                    >
                      {item.disposition?.outcome?.replace("_", " ") || "Logged"}
                    </span>
                  </div>

                  <div className="flex items-center justify-between text-xs text-slate-500 pt-1 border-t border-slate-800/60">
                    <div className="flex items-center gap-1 font-medium text-slate-400">
                      <Clock className="h-3 w-3 text-indigo-400" />
                      <span>Talk Duration: {formatTime(item.talk_secs)}</span>
                    </div>
                    <div>{new Date(item.initiated_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</div>
                  </div>

                  {item.disposition?.note && (
                    <div className="p-2 rounded-xl bg-slate-950/60 text-[11px] text-slate-300 italic">
                      Note: {item.disposition.note}
                    </div>
                  )}
                </div>
              ))
            )}
          </div>
        )}

        {/* ================================================================= */}
        {/* TAB 3: TEAM CHAT                                                 */}
        {/* ================================================================= */}
        {activeTab === "chat" && (
          <div className="flex flex-col h-[calc(100dvh-170px)] bg-slate-900 rounded-2xl border border-slate-800 overflow-hidden">
            {/* Chat Header */}
            <div className="px-4 py-3 bg-slate-950/80 border-b border-slate-800/80 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <MessageSquare className="h-4 w-4 text-teal-400" />
                <span className="text-xs font-bold text-white uppercase tracking-wider">
                  Orvyq Team Channel
                </span>
              </div>
              <span className="text-[10px] text-slate-400 bg-slate-800 px-2 py-0.5 rounded-full font-medium">
                Admin Moderated
              </span>
            </div>

            {/* Messages Feed */}
            <div
              ref={chatScrollRef}
              className="flex-1 p-3 overflow-y-auto space-y-2.5 text-xs text-slate-200"
            >
              {messages.length === 0 ? (
                <div className="text-center py-16 text-slate-500 text-xs">
                  No messages yet. Send a greeting to the team!
                </div>
              ) : (
                messages.map((msg) => {
                  const isMine = msg.sender_id === profile?.id;
                  const isOwner = msg.sender_role === "owner";

                  return (
                    <div
                      key={msg.id}
                      className={`flex flex-col ${isMine ? "items-end" : "items-start"}`}
                    >
                      <div className="flex items-center gap-1.5 text-[10px] text-slate-400 mb-1 px-1">
                        <span className="font-semibold text-slate-300">
                          {isMine ? "You" : msg.sender_name}
                        </span>
                        {isOwner && (
                          <span className="px-1.5 py-0.2 rounded bg-amber-500/20 text-amber-300 font-bold text-[9px] border border-amber-500/30">
                            Owner
                          </span>
                        )}
                        <span>
                          {new Date(msg.created_at).toLocaleTimeString([], {
                            hour: "2-digit",
                            minute: "2-digit",
                          })}
                        </span>
                        {msg.is_edited && (
                          <span className="text-slate-500 italic">(edited)</span>
                        )}
                      </div>

                      <div
                        className={`max-w-[82%] px-3.5 py-2.5 rounded-2xl text-xs leading-relaxed break-words ${
                          isMine
                            ? "bg-indigo-600 text-white rounded-tr-none shadow-md shadow-indigo-600/20"
                            : "bg-slate-800 text-slate-100 rounded-tl-none border border-slate-700/60"
                        }`}
                      >
                        {msg.content}
                      </div>
                    </div>
                  );
                })
              )}
            </div>

            {/* Input Bar */}
            <form
              onSubmit={handleSendMessage}
              className="p-2.5 bg-slate-950/80 border-t border-slate-800/80 flex items-center gap-2"
            >
              <input
                type="text"
                value={newMessageText}
                onChange={(e) => setNewMessageText(e.target.value)}
                placeholder="Type message to team..."
                className="flex-1 px-3.5 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition"
              />
              <button
                type="submit"
                disabled={sendingMessage || !newMessageText.trim()}
                className="p-2.5 rounded-xl bg-indigo-600 text-white disabled:opacity-50 active:scale-95 transition shadow-md shadow-indigo-600/30"
              >
                {sendingMessage ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Send className="h-4 w-4" />
                )}
              </button>
            </form>
          </div>
        )}

        {/* ================================================================= */}
        {/* TAB 4: SHIFT & PROFILE                                           */}
        {/* ================================================================= */}
        {activeTab === "shift" && (
          <div className="space-y-4">
            {/* User Profile Card */}
            <div className="p-4 rounded-2xl bg-slate-900 border border-slate-800 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-12 w-12 rounded-2xl bg-indigo-600 flex items-center justify-center text-white text-lg font-bold shadow-md shadow-indigo-600/30">
                  {profile?.full_name?.charAt(0) || "U"}
                </div>
                <div>
                  <div className="font-bold text-white text-base">{profile?.full_name}</div>
                  <div className="text-xs text-slate-400">{profile?.email}</div>
                  <div className="mt-1 flex items-center gap-1.5">
                    <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded-md bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                      {profile?.role === "owner" ? "Owner / Administrator" : "Telecaller"}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* Shift Session Summary */}
            <div className="p-4 rounded-2xl bg-slate-900 border border-slate-800 space-y-3">
              <div className="flex items-center justify-between pb-1 border-b border-slate-800">
                <div className="text-xs font-bold text-white uppercase tracking-wider flex items-center gap-2">
                  <ShieldCheck className="h-4 w-4 text-emerald-400" />
                  Work Shift Tracker
                </div>
                <span
                  className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                    isClockedIn ? "bg-emerald-500/20 text-emerald-400" : "bg-slate-800 text-slate-400"
                  }`}
                >
                  {isClockedIn ? "Active Shift" : "Off Duty"}
                </span>
              </div>

              <div className="grid grid-cols-2 gap-2 text-xs">
                <div className="p-2.5 rounded-xl bg-slate-950/60 border border-slate-800/80">
                  <div className="text-slate-400 text-[11px]">Active Time Today</div>
                  <div className="text-base font-extrabold text-white mt-0.5">
                    {formatTime(activeSecondsToday)}
                  </div>
                </div>

                <div className="p-2.5 rounded-xl bg-slate-950/60 border border-slate-800/80">
                  <div className="text-slate-400 text-[11px]">Shift Goal (2 hrs)</div>
                  <div className="text-base font-extrabold text-indigo-400 mt-0.5">
                    {Math.round((activeSecondsToday / 7200) * 100)}%
                  </div>
                </div>
              </div>

              {/* Big Shift Toggle Button */}
              {isClockedIn ? (
                <button
                  onClick={handleClockOut}
                  disabled={clockLoading}
                  className="w-full flex items-center justify-center gap-2 py-3 px-4 rounded-xl font-bold text-sm bg-rose-600 hover:bg-rose-500 text-white shadow-lg shadow-rose-600/30 active:scale-95 transition"
                >
                  <Square className="h-4 w-4 fill-white" />
                  Clock Out (End Shift)
                </button>
              ) : (
                <button
                  onClick={handleClockIn}
                  disabled={clockLoading}
                  className="w-full flex items-center justify-center gap-2 py-3 px-4 rounded-xl font-bold text-sm bg-emerald-600 hover:bg-emerald-500 text-white shadow-lg shadow-emerald-600/30 active:scale-95 transition"
                >
                  <Play className="h-4 w-4 fill-white" />
                  Clock In (Start Work Shift)
                </button>
              )}
            </div>

            {/* Privacy & Accountability Guarantee */}
            <div className="p-4 rounded-2xl bg-slate-900/60 border border-slate-800/60 space-y-2 text-xs text-slate-400">
              <div className="font-bold text-slate-200 flex items-center gap-1.5">
                <ShieldCheck className="h-4 w-4 text-indigo-400" />
                Employee Privacy & Tracking Policy
              </div>
              <p className="leading-relaxed text-[11px]">
                To ensure worker privacy, Orvyqmedia only tracks call attempts, talk duration, and dispositions while you are actively clocked in. Personal calls placed while off duty are never recorded or inspected.
              </p>
            </div>

            {/* Desktop Switcher for Owners */}
            {profile?.role === "owner" && (
              <button
                onClick={() => router.push("/")}
                className="w-full flex items-center justify-center gap-2 py-3 px-4 rounded-xl font-semibold text-xs bg-slate-800 hover:bg-slate-700 text-indigo-300 border border-indigo-500/25 transition"
              >
                <LayoutDashboard className="h-4 w-4" />
                Switch to Admin Desktop Dashboard
              </button>
            )}

            {/* Sign Out Button */}
            <form action="/api/auth/signout" method="POST">
              <button
                type="submit"
                className="w-full flex items-center justify-center gap-2 py-3 px-4 rounded-xl font-semibold text-xs bg-slate-900 hover:bg-rose-950/40 text-rose-400 border border-rose-500/20 transition"
              >
                <LogOut className="h-4 w-4" />
                Sign Out from App
              </button>
            </form>
          </div>
        )}
      </main>

      {/* =================================================================== */}
      {/* ACTIVE CALL FLOATING HUD (IN-CALL OVERLAY)                         */}
      {/* =================================================================== */}
      {activeCall && (
        <div className="fixed inset-x-0 bottom-16 z-50 p-4 max-w-lg mx-auto">
          <div className="p-4 rounded-3xl bg-slate-900 border-2 border-indigo-500/80 shadow-2xl shadow-indigo-600/40 text-white space-y-3 animate-in slide-in-from-bottom-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2.5">
                <div className="h-9 w-9 rounded-2xl bg-indigo-600 flex items-center justify-center text-white animate-pulse">
                  <PhoneCall className="h-5 w-5" />
                </div>
                <div>
                  <div className="font-bold text-sm text-white">
                    Calling: {activeCall.lead.name || "Lead"}
                  </div>
                  <div className="text-xs text-slate-400 font-mono">
                    {activeCall.lead.phone_e164}
                  </div>
                </div>
              </div>

              {/* In-Call Live Stopwatch */}
              <div className="font-mono text-xl font-black text-emerald-400 bg-slate-950 px-3 py-1 rounded-xl border border-slate-800">
                {formatStopwatch(callElapsedSecs)}
              </div>
            </div>

            {/* Pitch Cheat Sheet Accordion */}
            <div className="rounded-2xl bg-slate-950/80 border border-slate-800/80 overflow-hidden">
              <button
                onClick={() => setIsPitchExpanded(!isPitchExpanded)}
                className="w-full px-3.5 py-2 flex items-center justify-between text-xs font-semibold text-indigo-300 hover:bg-slate-900 transition"
              >
                <span className="flex items-center gap-1.5">
                  <Sparkles className="h-3.5 w-3.5 text-indigo-400" />
                  Live Pitch & Objection Guide
                </span>
                {isPitchExpanded ? (
                  <ChevronUp className="h-4 w-4" />
                ) : (
                  <ChevronDown className="h-4 w-4" />
                )}
              </button>

              {isPitchExpanded && (
                <div className="p-3 border-t border-slate-800/80 space-y-2 text-xs">
                  {/* Category Tabs */}
                  <div className="flex items-center gap-1">
                    {["opener", "objection", "closing"].map((cat) => (
                      <button
                        key={cat}
                        onClick={() => setSelectedScriptTab(cat)}
                        className={`px-2.5 py-1 rounded-lg text-[10px] font-bold uppercase transition ${
                          selectedScriptTab === cat
                            ? "bg-indigo-600 text-white"
                            : "bg-slate-800 text-slate-400"
                        }`}
                      >
                        {cat}
                      </button>
                    ))}
                  </div>

                  {/* Pitch Script Content */}
                  <div className="p-2.5 rounded-xl bg-slate-900 border border-slate-800/80 text-[11px] leading-relaxed text-slate-300 max-h-36 overflow-y-auto">
                    {pitchScripts
                      .filter((s) => s.category.toLowerCase().includes(selectedScriptTab))
                      .map((script) => (
                        <div key={script.id} className="space-y-1 mb-2">
                          <div className="font-bold text-white">{script.title}</div>
                          <div className="text-slate-300 whitespace-pre-line">{script.content}</div>
                        </div>
                      ))}
                  </div>
                </div>
              )}
            </div>

            {/* Finish Call & Log Disposition Button */}
            <button
              onClick={handleEndCall}
              className="w-full flex items-center justify-center gap-2 py-3 px-4 rounded-2xl bg-rose-600 hover:bg-rose-500 font-bold text-sm text-white shadow-lg shadow-rose-600/40 active:scale-95 transition"
            >
              <PhoneOff className="h-4 w-4" />
              Finish Call & Record Disposition
            </button>
          </div>
        </div>
      )}

      {/* =================================================================== */}
      {/* POST-CALL DISPOSITION MODAL (IOS BOTTOM SHEET)                     */}
      {/* =================================================================== */}
      {dispositionOpen && postCallLead && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-end justify-center p-0 md:p-4">
          <div className="w-full max-w-lg bg-slate-900 border-t md:border border-slate-800 rounded-t-3xl md:rounded-3xl p-5 space-y-4 max-h-[90dvh] overflow-y-auto animate-in slide-in-from-bottom-8">
            {/* Sheet Handle */}
            <div className="w-12 h-1 bg-slate-700 rounded-full mx-auto" />

            <div className="flex items-start justify-between">
              <div>
                <h3 className="text-lg font-bold text-white">Call Disposition</h3>
                <div className="text-xs text-slate-400">
                  Lead: <strong className="text-white">{postCallLead.name || postCallLead.phone_e164}</strong>
                </div>
              </div>
              <button
                onClick={() => setDispositionOpen(false)}
                className="p-1 rounded-full text-slate-500 hover:text-white"
              >
                <XCircle className="h-5 w-5" />
              </button>
            </div>

            {/* Measured Duration Selector */}
            <div className="space-y-2">
              <label className="text-xs font-semibold text-slate-300 uppercase tracking-wider block">
                Talk Duration (Seconds)
              </label>
              <div className="flex items-center gap-1.5 overflow-x-auto pb-1 no-scrollbar">
                {[
                  { label: "0s (No Answer)", secs: 0 },
                  { label: "15s", secs: 15 },
                  { label: "30s", secs: 30 },
                  { label: "1m", secs: 60 },
                  { label: "2m", secs: 120 },
                  { label: "5m", secs: 300 },
                ].map((item) => (
                  <button
                    key={item.secs}
                    type="button"
                    onClick={() => {
                      setPostCallDuration(item.secs);
                      setCallerClaimedConnected(item.secs >= 10);
                    }}
                    className={`px-3 py-1.5 rounded-xl text-xs font-bold shrink-0 transition ${
                      postCallDuration === item.secs
                        ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/30"
                        : "bg-slate-800 text-slate-400 border border-slate-700"
                    }`}
                  >
                    {item.label}
                  </button>
                ))}
              </div>

              {/* Exact Seconds Input */}
              <div className="flex items-center gap-2 pt-1">
                <input
                  type="number"
                  min="0"
                  value={postCallDuration}
                  onChange={(e) => {
                    const val = parseInt(e.target.value) || 0;
                    setPostCallDuration(val);
                    setCallerClaimedConnected(val >= 10);
                  }}
                  className="w-24 px-3 py-2 rounded-xl bg-slate-950 border border-slate-800 text-sm font-mono text-white text-center focus:ring-2 focus:ring-indigo-500"
                />
                <span className="text-xs text-slate-400">
                  {postCallDuration >= 10 ? (
                    <span className="text-emerald-400 font-semibold">✓ Verified Connected (≥10s)</span>
                  ) : (
                    <span className="text-amber-400">Under 10s (Unconnected)</span>
                  )}
                </span>
              </div>
            </div>

            {/* Connected Toggle */}
            <div className="p-3 rounded-xl bg-slate-950/60 border border-slate-800 flex items-center justify-between">
              <div>
                <div className="text-xs font-bold text-white">Spoke with Contact / Connected</div>
                <div className="text-[11px] text-slate-400">Decision maker or team answered</div>
              </div>
              <input
                type="checkbox"
                checked={callerClaimedConnected}
                onChange={(e) => setCallerClaimedConnected(e.target.checked)}
                className="h-5 w-5 rounded accent-indigo-600"
              />
            </div>

            {/* Outcome Selection Grid */}
            <div className="space-y-2">
              <label className="text-xs font-semibold text-slate-300 uppercase tracking-wider block">
                Call Outcome
              </label>
              <div className="grid grid-cols-2 gap-2">
                {[
                  { id: "interested", label: "Interested (Lead)", color: "text-emerald-400 border-emerald-500/30 bg-emerald-950/30" },
                  { id: "callback", label: "Schedule Callback", color: "text-sky-400 border-sky-500/30 bg-sky-950/30" },
                  { id: "no_answer", label: "No Answer / Ringing", color: "text-amber-400 border-amber-500/30 bg-amber-950/30" },
                  { id: "busy", label: "Busy / Line Engaged", color: "text-orange-400 border-orange-500/30 bg-orange-950/30" },
                  { id: "not_interested", label: "Not Interested", color: "text-slate-300 border-slate-700 bg-slate-800/40" },
                  { id: "wrong_number", label: "Wrong / Invalid", color: "text-rose-400 border-rose-500/30 bg-rose-950/30" },
                ].map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => setSelectedOutcome(item.id as any)}
                    className={`p-2.5 rounded-xl border text-xs font-bold text-left transition ${
                      selectedOutcome === item.id
                        ? `${item.color} ring-2 ring-indigo-500`
                        : "bg-slate-950 border-slate-800 text-slate-400 hover:text-white"
                    }`}
                  >
                    {item.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Follow-up Date Time if Callback or Interested */}
            {(selectedOutcome === "callback" || selectedOutcome === "interested") && (
              <div className="space-y-1.5 animate-in fade-in">
                <label className="text-xs font-semibold text-sky-400 block">
                  Follow-up Callback Date & Time
                </label>
                <input
                  type="datetime-local"
                  value={followUpDate}
                  onChange={(e) => setFollowUpDate(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-xs text-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>
            )}

            {/* Drop / Rejection Reasons Multi-Select */}
            {activeReasons.length > 0 && (
              <div className="space-y-2">
                <label className="text-xs font-semibold text-slate-300 uppercase tracking-wider block">
                  Select Specific Reason(s)
                </label>
                <div className="space-y-1.5 max-h-32 overflow-y-auto">
                  {activeReasons.map((r) => {
                    const isChecked = selectedReasonIds.includes(r.id);
                    return (
                      <label
                        key={r.id}
                        className="flex items-center gap-2.5 p-2 rounded-xl bg-slate-950/60 border border-slate-800/80 text-xs text-slate-300 cursor-pointer"
                      >
                        <input
                          type="checkbox"
                          checked={isChecked}
                          onChange={(e) => {
                            if (e.target.checked) {
                              setSelectedReasonIds([...selectedReasonIds, r.id]);
                            } else {
                              setSelectedReasonIds(selectedReasonIds.filter((id) => id !== r.id));
                            }
                          }}
                          className="h-4 w-4 rounded accent-indigo-600"
                        />
                        <span>{r.label}</span>
                      </label>
                    );
                  })}
                </div>
              </div>
            )}

            {/* Call Notes */}
            <div className="space-y-1.5">
              <label className="text-xs font-semibold text-slate-300 uppercase tracking-wider block">
                Call Notes
              </label>
              <textarea
                rows={2}
                value={callNotes}
                onChange={(e) => setCallNotes(e.target.value)}
                placeholder="Key conversation points, objections, next steps..."
                className="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-800 text-xs text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>

            {/* Submit Disposition Button */}
            <button
              onClick={handleSubmitDisposition}
              disabled={submittingDisposition}
              className="w-full flex items-center justify-center gap-2 py-3.5 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-sm shadow-xl shadow-indigo-600/30 disabled:opacity-50 active:scale-95 transition"
            >
              {submittingDisposition ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Recording & Verifying...
                </>
              ) : (
                <>
                  <CheckCircle2 className="h-4 w-4" />
                  Submit Call Disposition
                </>
              )}
            </button>
          </div>
        </div>
      )}

      {/* =================================================================== */}
      {/* OFF-DUTY BLOCKING MODAL                                             */}
      {/* =================================================================== */}
      {offDutyModalOpen && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="w-full max-w-sm bg-slate-900 border border-slate-800 rounded-3xl p-6 text-center space-y-4 animate-in zoom-in-95">
            <div className="h-12 w-12 rounded-2xl bg-amber-500/20 border border-amber-500/30 flex items-center justify-center mx-auto text-amber-400">
              <ShieldAlert className="h-6 w-6" />
            </div>

            <div>
              <h3 className="text-lg font-bold text-white">Clock In to Start Shift</h3>
              <p className="text-xs text-slate-400 mt-1 leading-relaxed">
                You are currently off duty. To protect employee privacy, calls and work tracking can only be started while on active duty.
              </p>
            </div>

            <div className="space-y-2 pt-2">
              <button
                onClick={handleClockIn}
                disabled={clockLoading}
                className="w-full py-3 px-4 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs shadow-md shadow-emerald-600/30 active:scale-95 transition"
              >
                {clockLoading ? "Clocking In..." : "Clock In & Begin Calling"}
              </button>
              <button
                onClick={() => setOffDutyModalOpen(false)}
                className="w-full py-2.5 px-4 rounded-xl text-slate-400 hover:text-white text-xs font-semibold"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* =================================================================== */}
      {/* BOTTOM TAB NAVIGATION (IOS FIXED SAFE-AREA BAR)                     */}
      {/* =================================================================== */}
      <nav className="fixed bottom-0 inset-x-0 z-40 bg-slate-900/95 backdrop-blur-md border-t border-slate-800/80 px-2 pb-safe max-w-lg mx-auto">
        <div className="grid grid-cols-4 py-2">
          {/* Queue Tab */}
          <button
            onClick={() => setActiveTab("queue")}
            className={`flex flex-col items-center gap-1 py-1 px-2 rounded-xl transition ${
              activeTab === "queue" ? "text-indigo-400 font-bold" : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <PhoneCall className={`h-5 w-5 ${activeTab === "queue" ? "stroke-[2.5]" : ""}`} />
            <span className="text-[10px]">Queue</span>
          </button>

          {/* History Tab */}
          <button
            onClick={() => setActiveTab("history")}
            className={`flex flex-col items-center gap-1 py-1 px-2 rounded-xl transition ${
              activeTab === "history" ? "text-indigo-400 font-bold" : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <Clock className={`h-5 w-5 ${activeTab === "history" ? "stroke-[2.5]" : ""}`} />
            <span className="text-[10px]">History</span>
          </button>

          {/* Team Chat Tab */}
          <button
            onClick={() => setActiveTab("chat")}
            className={`flex flex-col items-center gap-1 py-1 px-2 rounded-xl transition ${
              activeTab === "chat" ? "text-indigo-400 font-bold" : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <MessageSquare className={`h-5 w-5 ${activeTab === "chat" ? "stroke-[2.5]" : ""}`} />
            <span className="text-[10px]">Team Chat</span>
          </button>

          {/* Shift / Profile Tab */}
          <button
            onClick={() => setActiveTab("shift")}
            className={`flex flex-col items-center gap-1 py-1 px-2 rounded-xl transition ${
              activeTab === "shift" ? "text-indigo-400 font-bold" : "text-slate-400 hover:text-slate-200"
            }`}
          >
            <ShieldCheck className={`h-5 w-5 ${activeTab === "shift" ? "stroke-[2.5]" : ""}`} />
            <span className="text-[10px]">Shift & You</span>
          </button>
        </div>
      </nav>
    </div>
  );
}
