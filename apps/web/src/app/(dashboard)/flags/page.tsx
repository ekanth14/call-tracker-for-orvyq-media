"use client";

import React, { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  AlertTriangle,
  ShieldAlert,
  CheckCircle2,
  XCircle,
  Search,
  Filter,
  RefreshCw,
  Loader2,
  Clock,
  Eye,
  Check,
  Ban,
  ArrowRight,
} from "lucide-react";

interface FlagRow {
  id: string;
  rule_code: string;
  severity: string;
  details: any;
  status: string;
  review_note: string | null;
  created_at: string;
  caller?: {
    id: string;
    full_name: string;
    email: string | null;
  };
  call?: {
    id: string;
    talk_secs: number;
    lead?: {
      phone_e164: string;
      name: string | null;
      company: string | null;
    };
    disposition?: {
      outcome: string;
      connected: boolean;
      caller_claimed_connected: boolean | null;
    };
  };
}

export default function FlagsPage() {
  const [flags, setFlags] = useState<FlagRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState("open");
  const [severityFilter, setSeverityFilter] = useState("all");
  const [search, setSearch] = useState("");

  // Review modal state
  const [selectedFlag, setSelectedFlag] = useState<FlagRow | null>(null);
  const [reviewNote, setReviewNote] = useState("");
  const [actionLoading, setActionLoading] = useState(false);

  const fetchFlags = async () => {
    setLoading(true);
    const supabase = createClient();

    const { data, error } = await supabase
      .from("flags")
      .select(`
        id,
        rule_code,
        severity,
        details,
        status,
        review_note,
        created_at,
        caller:profiles!flags_caller_id_fkey(id, full_name, email),
        call:calls(
          id,
          talk_secs,
          lead:leads(phone_e164, name, company),
          disposition:dispositions(outcome, connected, caller_claimed_connected)
        )
      `)
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Error fetching flags:", error);
    } else if (data) {
      setFlags(data as any);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchFlags();
  }, []);

  const handleUpdateStatus = async (status: "reviewed" | "dismissed") => {
    if (!selectedFlag) return;
    setActionLoading(true);

    try {
      const res = await fetch("/api/flags", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          flag_id: selectedFlag.id,
          status,
          review_note: reviewNote,
        }),
      });

      if (res.ok) {
        setSelectedFlag(null);
        setReviewNote("");
        await fetchFlags();
      } else {
        const err = await res.json();
        alert(err.error || "Failed to update flag");
      }
    } catch (e) {
      alert("Network error updating flag");
    } finally {
      setActionLoading(false);
    }
  };

  // Metrics
  const openCount = flags.filter((f) => f.status === "open").length;
  const highCount = flags.filter((f) => f.severity === "high" && f.status === "open").length;
  const reviewedCount = flags.filter((f) => f.status === "reviewed").length;

  const filteredFlags = flags.filter((f) => {
    const matchesStatus = statusFilter === "all" || f.status === statusFilter;
    const matchesSeverity =
      severityFilter === "all" || f.severity === severityFilter;

    const callerMatch =
      f.caller?.full_name.toLowerCase().includes(search.toLowerCase()) ||
      f.caller?.email?.toLowerCase().includes(search.toLowerCase());
    const ruleMatch = f.rule_code.toLowerCase().includes(search.toLowerCase());

    return matchesStatus && matchesSeverity && (callerMatch || ruleMatch);
  });

  const getRuleDescription = (ruleCode: string) => {
    switch (ruleCode) {
      case "CLAIM_MISMATCH":
        return "Caller marked call as connected, but device call log talk time was below the 10-second threshold.";
      case "MANUAL_UNVERIFIED_ENTRY":
        return "No SIM call log matched; duration was self-reported by caller and requires manual review.";
      case "NO_LOG_ENTRY":
        return "Post-call dialog submitted with no matching outgoing phone call detected in the SIM call log.";
      case "SHORT_INTERESTED":
        return "Caller claimed lead was 'Interested' on an exceptionally brief call.";
      case "CLOCK_SKEW":
        return "Phone device clock deviated significantly (>120s) from the server timestamp.";
      case "LOG_GAP":
        return "Multiple dial attempts recorded without matching log uploads (possible sync failure).";
      case "PERMISSION_REVOKED":
        return "Device reports that call-log or telephony permission was revoked.";
      default:
        return "Audit anomaly flagged by verification engine.";
    }
  };

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Compliance & Audit Flags
          </h1>
          <p className="mt-1 text-sm text-slate-500">
            Review automated discrepancies detected between caller claims and Android SIM call-log proofs (§8).
          </p>
        </div>

        <button
          onClick={fetchFlags}
          className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm text-slate-700 bg-white border border-slate-200 hover:bg-slate-50 transition shadow-sm"
        >
          <RefreshCw className="h-4 w-4" />
          Refresh Flags
        </button>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm flex items-center justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wider text-slate-500">
              Open Flags
            </div>
            <div className="mt-2 text-3xl font-extrabold text-amber-600">
              {openCount}
            </div>
            <div className="text-xs text-slate-400 mt-1">Awaiting owner review</div>
          </div>
          <div className="p-3 bg-amber-50 text-amber-600 rounded-xl">
            <AlertTriangle className="h-6 w-6" />
          </div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm flex items-center justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wider text-slate-500">
              High Severity
            </div>
            <div className="mt-2 text-3xl font-extrabold text-rose-600">
              {highCount}
            </div>
            <div className="text-xs text-slate-400 mt-1">Proof mismatches & fakes</div>
          </div>
          <div className="p-3 bg-rose-50 text-rose-600 rounded-xl">
            <ShieldAlert className="h-6 w-6" />
          </div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm flex items-center justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wider text-slate-500">
              Resolved & Cleared
            </div>
            <div className="mt-2 text-3xl font-extrabold text-emerald-600">
              {reviewedCount}
            </div>
            <div className="text-xs text-slate-400 mt-1">Audited by manager</div>
          </div>
          <div className="p-3 bg-emerald-50 text-emerald-600 rounded-xl">
            <CheckCircle2 className="h-6 w-6" />
          </div>
        </div>
      </div>

      {/* Filters Bar */}
      <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-sm flex flex-col md:flex-row items-center gap-4 justify-between">
        <div className="relative flex-1 w-full">
          <Search className="h-4 w-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search by caller name, email, or rule code..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-4 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:bg-white transition"
          />
        </div>

        <div className="flex items-center gap-3 w-full md:w-auto">
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-xs font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <option value="open">Status: Open Flags</option>
            <option value="reviewed">Status: Reviewed</option>
            <option value="dismissed">Status: Dismissed</option>
            <option value="all">Status: All</option>
          </select>

          <select
            value={severityFilter}
            onChange={(e) => setSeverityFilter(e.target.value)}
            className="px-3 py-2 rounded-xl border border-slate-200 bg-slate-50 text-xs font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          >
            <option value="all">Severity: All</option>
            <option value="high">High Severity</option>
            <option value="warn">Warnings</option>
          </select>
        </div>
      </div>

      {/* Flags List Table */}
      <div className="bg-white rounded-2xl border border-slate-200/80 shadow-sm overflow-hidden">
        {loading ? (
          <div className="p-16 text-center text-slate-500 flex flex-col items-center justify-center gap-3">
            <Loader2 className="h-6 w-6 animate-spin text-indigo-600" />
            <span className="text-sm">Fetching audit flags...</span>
          </div>
        ) : filteredFlags.length === 0 ? (
          <div className="p-16 text-center text-slate-500">
            <div className="h-12 w-12 rounded-2xl bg-emerald-50 text-emerald-600 flex items-center justify-center mx-auto mb-3">
              <CheckCircle2 className="h-6 w-6" />
            </div>
            <h3 className="font-bold text-slate-800 text-base">No Flags Match Filter</h3>
            <p className="text-xs text-slate-400 mt-1 max-w-sm mx-auto">
              Any discrepancies between caller submitted notes and verified Android call logs will be surfaced here automatically.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-sm">
              <thead>
                <tr className="bg-slate-50/80 border-b border-slate-200 text-xs font-semibold text-slate-500 uppercase tracking-wider">
                  <th className="py-3.5 px-6">Rule Code</th>
                  <th className="py-3.5 px-6">Caller</th>
                  <th className="py-3.5 px-6">Lead & Call Proof</th>
                  <th className="py-3.5 px-6">Details</th>
                  <th className="py-3.5 px-6">Status</th>
                  <th className="py-3.5 px-6 text-right">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredFlags.map((flag) => {
                  return (
                    <tr key={flag.id} className="hover:bg-slate-50/60 transition">
                      <td className="py-4 px-6">
                        <span
                          className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md text-xs font-bold ${
                            flag.severity === "high"
                              ? "bg-rose-50 text-rose-700 border border-rose-200"
                              : "bg-amber-50 text-amber-700 border border-amber-200"
                          }`}
                        >
                          <AlertTriangle className="h-3.5 w-3.5" />
                          {flag.rule_code}
                        </span>
                        <div className="text-[11px] text-slate-400 mt-1 max-w-xs leading-snug">
                          {getRuleDescription(flag.rule_code)}
                        </div>
                      </td>
                      <td className="py-4 px-6">
                        <div className="font-semibold text-slate-900">
                          {flag.caller?.full_name || "Unknown"}
                        </div>
                        <div className="text-xs text-slate-400">
                          {flag.caller?.email}
                        </div>
                      </td>
                      <td className="py-4 px-6">
                        {flag.call?.lead ? (
                          <div>
                            <div className="font-mono text-xs font-bold text-slate-800">
                              {flag.call.lead.phone_e164}
                            </div>
                            <div className="text-xs text-slate-500">
                              Log Talk Time: {flag.call.talk_secs}s
                            </div>
                          </div>
                        ) : (
                          <span className="text-xs text-slate-400 italic">No call link</span>
                        )}
                      </td>
                      <td className="py-4 px-6">
                        <div className="font-mono text-[11px] bg-slate-50 p-2 rounded-lg border border-slate-200 text-slate-700 max-w-xs truncate">
                          {JSON.stringify(flag.details)}
                        </div>
                        {flag.review_note && (
                          <div className="text-xs text-indigo-600 mt-1 italic">
                            Note: "{flag.review_note}"
                          </div>
                        )}
                      </td>
                      <td className="py-4 px-6">
                        <span
                          className={`inline-block px-2.5 py-0.5 rounded-full text-xs font-medium ${
                            flag.status === "open"
                              ? "bg-amber-50 text-amber-700 border border-amber-200"
                              : flag.status === "reviewed"
                              ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                              : "bg-slate-100 text-slate-500 border border-slate-200"
                          }`}
                        >
                          {flag.status.toUpperCase()}
                        </span>
                      </td>
                      <td className="py-4 px-6 text-right">
                        {flag.status === "open" ? (
                          <button
                            onClick={() => {
                              setSelectedFlag(flag);
                              setReviewNote("");
                            }}
                            className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-semibold text-indigo-600 bg-indigo-50 hover:bg-indigo-100 transition"
                          >
                            Audit
                            <ArrowRight className="h-3 w-3" />
                          </button>
                        ) : (
                          <span className="text-xs text-slate-400">Resolved</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Review Modal */}
      {selectedFlag && (
        <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl p-6 max-w-md w-full shadow-2xl border border-slate-200 space-y-4">
            <div className="flex items-center gap-2 text-rose-600 font-bold text-base">
              <ShieldAlert className="h-5 w-5" />
              Resolve Audit Flag: {selectedFlag.rule_code}
            </div>

            <p className="text-xs text-slate-500 leading-relaxed">
              Caller: <b>{selectedFlag.caller?.full_name}</b> ({selectedFlag.caller?.email})
              <br />
              {getRuleDescription(selectedFlag.rule_code)}
            </p>

            <div className="bg-slate-50 p-3 rounded-xl border border-slate-200 font-mono text-xs text-slate-700">
              {JSON.stringify(selectedFlag.details, null, 2)}
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Owner Audit Note (optional)
              </label>
              <textarea
                rows={2}
                value={reviewNote}
                onChange={(e) => setReviewNote(e.target.value)}
                placeholder="e.g. Verified with caller; network disconnect occurred."
                className="w-full p-2.5 text-xs rounded-xl border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2">
              <button
                disabled={actionLoading}
                onClick={() => setSelectedFlag(null)}
                className="px-3 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl"
              >
                Cancel
              </button>
              <button
                disabled={actionLoading}
                onClick={() => handleUpdateStatus("dismissed")}
                className="px-3 py-2 text-xs font-semibold text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-xl"
              >
                Dismiss Flag
              </button>
              <button
                disabled={actionLoading}
                onClick={() => handleUpdateStatus("reviewed")}
                className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-700 rounded-xl shadow-sm"
              >
                Mark as Reviewed
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
