"use client";

import React, { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { normalizePhoneE164 } from "@/lib/phone";
import {
  UserPlus,
  Search,
  UserCheck,
  UserX,
  Phone,
  Mail,
  Loader2,
  CheckCircle2,
  X,
  Shield,
  Smartphone,
  Pencil,
} from "lucide-react";

interface CallerItem {
  id: string;
  full_name: string;
  email: string | null;
  mobile_e164: string | null;
  role?: string;
  is_active: boolean;
  created_at: string;
  assigned_count?: number;
  completed_count?: number;
  today_active_seconds?: number;
  today_quota_met?: boolean;
}

export default function CallersPage() {
  const [callers, setCallers] = useState<CallerItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [modalOpen, setModalOpen] = useState(false);

  // Form states (Create)
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mobile, setMobile] = useState("");
  const [formLoading, setFormLoading] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState(false);

  // Form states (Edit Caller)
  const [editModalOpen, setEditModalOpen] = useState(false);
  const [editingCaller, setEditingCaller] = useState<CallerItem | null>(null);
  const [editFullName, setEditFullName] = useState("");
  const [editMobile, setEditMobile] = useState("");
  const [editRole, setEditRole] = useState("caller");
  const [editIsActive, setEditIsActive] = useState(true);
  const [editLoading, setEditLoading] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);
  const [editSuccess, setEditSuccess] = useState(false);

  const fetchCallers = async () => {
    setLoading(true);
    const supabase = createClient();

    // Fetch callers
    const { data: profiles, error } = await supabase
      .from("profiles")
      .select("*")
      .eq("role", "caller")
      .order("created_at", { ascending: false });

    if (error) {
      console.error("Error fetching callers:", error);
      setLoading(false);
      return;
    }

    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    // Fetch counts and daily quota tracking for each caller
    const enhanced = await Promise.all(
      (profiles || []).map(async (c) => {
        try {
          const [
            { count: assignedCount },
            { count: callCount },
            { data: quotaData },
          ] = await Promise.all([
            supabase
              .from("leads")
              .select("*", { count: "exact", head: true })
              .eq("assigned_to", c.id),
            supabase
              .from("calls")
              .select("*", { count: "exact", head: true })
              .eq("caller_id", c.id),
            supabase.rpc("get_daily_caller_quota", {
              p_caller_id: c.id,
            }),
          ]);

          const totalSeconds = quotaData?.active_seconds ?? 0;
          const quotaMet = quotaData?.quota_met ?? false;

          return {
            ...c,
            assigned_count: assignedCount || 0,
            completed_count: callCount || 0,
            today_active_seconds: totalSeconds,
            today_quota_met: quotaMet,
          };
        } catch {
          return {
            ...c,
            assigned_count: 0,
            completed_count: 0,
            today_active_seconds: 0,
            today_quota_met: false,
          };
        }
      })
    );

    setCallers(enhanced);
    setLoading(false);
  };

  useEffect(() => {
    fetchCallers();
  }, []);

  const handleCreateCaller = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormLoading(true);
    setFormError(null);

    // Normalize phone if provided
    let normMobile = null;
    if (mobile.trim()) {
      const res = normalizePhoneE164(mobile);
      if (!res.success) {
        setFormError("Invalid mobile number format. Enter a valid 10-digit Indian phone number.");
        setFormLoading(false);
        return;
      }
      normMobile = res.e164;
    }

    try {
      const res = await fetch("/api/callers", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          full_name: fullName,
          email,
          password,
          mobile_e164: normMobile,
        }),
      });

      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.error || "Failed to create caller.");
      }

      setFormSuccess(true);
      setTimeout(() => {
        setModalOpen(false);
        setFormSuccess(false);
        setFullName("");
        setEmail("");
        setPassword("");
        setMobile("");
        fetchCallers();
      }, 1000);
    } catch (err: unknown) {
      setFormError(err instanceof Error ? err.message : "Error creating caller");
    } finally {
      setFormLoading(false);
    }
  };

  const toggleStatus = async (caller: CallerItem) => {
    const newStatus = !caller.is_active;
    try {
      const res = await fetch("/api/callers", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          caller_id: caller.id,
          is_active: newStatus,
        }),
      });

      if (res.ok) {
        setCallers((prev) =>
          prev.map((c) => (c.id === caller.id ? { ...c, is_active: newStatus } : c))
        );
      }
    } catch (err) {
      console.error("Failed to toggle caller status:", err);
    }
  };

  const startEditingCaller = (caller: CallerItem) => {
    setEditingCaller(caller);
    setEditFullName(caller.full_name);
    setEditMobile(caller.mobile_e164 || "");
    setEditRole(caller.role || "caller");
    setEditIsActive(caller.is_active);
    setEditError(null);
    setEditSuccess(false);
    setEditModalOpen(true);
  };

  const handleUpdateCaller = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingCaller) return;
    setEditLoading(true);
    setEditError(null);

    let normMobile = null;
    if (editMobile.trim()) {
      const res = normalizePhoneE164(editMobile);
      if (!res.success) {
        setEditError("Invalid mobile number format. Enter a valid 10-digit Indian phone number.");
        setEditLoading(false);
        return;
      }
      normMobile = res.e164;
    }

    try {
      const res = await fetch("/api/callers", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          caller_id: editingCaller.id,
          full_name: editFullName.trim(),
          mobile_e164: normMobile,
          role: editRole,
          is_active: editIsActive,
        }),
      });

      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.error || "Failed to update caller.");
      }

      setEditSuccess(true);
      setTimeout(() => {
        setEditModalOpen(false);
        setEditSuccess(false);
        setEditingCaller(null);
        fetchCallers();
      }, 700);
    } catch (err: unknown) {
      setEditError(err instanceof Error ? err.message : "Error updating caller");
    } finally {
      setEditLoading(false);
    }
  };

  const filteredCallers = callers.filter(
    (c) =>
      c.full_name.toLowerCase().includes(search.toLowerCase()) ||
      c.email?.toLowerCase().includes(search.toLowerCase()) ||
      c.mobile_e164?.includes(search)
  );

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-6">
      {/* Page Title & Action Bar */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Caller Accounts
          </h1>
          <p className="mt-1 text-sm text-slate-500">
            Manage employees who make outbound cold calls via the Android app.
          </p>
        </div>

        <button
          onClick={() => setModalOpen(true)}
          className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm text-white bg-indigo-600 hover:bg-indigo-700 transition shadow-sm"
        >
          <UserPlus className="h-4 w-4" />
          Add Caller Account
        </button>
      </div>

      {/* Search & Filter Bar */}
      <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-sm flex items-center gap-4">
        <div className="relative flex-1">
          <Search className="h-4 w-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search callers by name, email, or mobile..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-4 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:bg-white transition"
          />
        </div>
      </div>

      {/* Callers List */}
      <div className="bg-white rounded-2xl border border-slate-200/80 shadow-sm overflow-hidden">
        {loading ? (
          <div className="p-12 text-center text-slate-500 flex flex-col items-center justify-center gap-3">
            <Loader2 className="h-6 w-6 animate-spin text-indigo-600" />
            <span className="text-sm">Loading caller roster...</span>
          </div>
        ) : filteredCallers.length === 0 ? (
          <div className="p-12 text-center text-slate-500">
            <UserX className="h-8 w-8 mx-auto text-slate-300 mb-2" />
            <h3 className="font-semibold text-slate-700">No Callers Found</h3>
            <p className="text-xs text-slate-400 mt-1 max-w-sm mx-auto">
              Create your first caller account so employees can log into the Flutter app and receive assigned leads.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-sm">
              <thead>
                <tr className="bg-slate-50/80 border-b border-slate-200 text-xs font-semibold text-slate-500 uppercase tracking-wider">
                  <th className="py-3.5 px-6">Caller</th>
                  <th className="py-3.5 px-6">Mobile SIM</th>
                  <th className="py-3.5 px-6 text-center">Assigned Leads</th>
                  <th className="py-3.5 px-6 text-center">Verified Calls</th>
                  <th className="py-3.5 px-6">Daily 2h Quota</th>
                  <th className="py-3.5 px-6">Status</th>
                  <th className="py-3.5 px-6 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredCallers.map((caller) => (
                  <tr key={caller.id} className="hover:bg-slate-50/60 transition">
                    <td className="py-4 px-6">
                      <div className="font-semibold text-slate-900">{caller.full_name}</div>
                      <div className="text-xs text-slate-400 flex items-center gap-1 mt-0.5">
                        <Mail className="h-3 w-3" />
                        {caller.email}
                      </div>
                    </td>
                    <td className="py-4 px-6">
                      {caller.mobile_e164 ? (
                        <span className="inline-flex items-center gap-1 font-mono text-xs text-slate-700 bg-slate-100 px-2.5 py-1 rounded-md">
                          <Phone className="h-3 w-3 text-slate-400" />
                          {caller.mobile_e164}
                        </span>
                      ) : (
                        <span className="text-xs text-slate-400 italic">Not set</span>
                      )}
                    </td>
                    <td className="py-4 px-6 text-center">
                      <span className="inline-block px-2.5 py-1 rounded-full text-xs font-semibold bg-indigo-50 text-indigo-700 border border-indigo-100">
                        {caller.assigned_count ?? 0}
                      </span>
                    </td>
                    <td className="py-4 px-6 text-center">
                      <span className="inline-block px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700 border border-emerald-100">
                        {caller.completed_count ?? 0}
                      </span>
                    </td>
                    <td className="py-4 px-6 min-w-[170px]">
                      {(() => {
                        const totalSecs = caller.today_active_seconds || 0;
                        const hours = Math.floor(totalSecs / 3600);
                        const minutes = Math.floor((totalSecs % 3600) / 60);
                        const pct = Math.min(100, Math.round((totalSecs / 7200) * 100));
                        const isMet = caller.today_quota_met;

                        return (
                          <div className="space-y-1.5">
                            <div className="flex items-center justify-between text-xs">
                              <span className="font-medium text-slate-700">
                                {hours > 0 ? `${hours}h ` : ""}{minutes}m / 2h
                              </span>
                              <span
                                className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${
                                  isMet
                                    ? "bg-emerald-100 text-emerald-800"
                                    : totalSecs > 0
                                    ? "bg-amber-100 text-amber-800"
                                    : "bg-slate-100 text-slate-500"
                                }`}
                              >
                                {isMet ? "Quota Met 🎉" : `${pct}%`}
                              </span>
                            </div>
                            <div className="w-full bg-slate-100 rounded-full h-1.5 overflow-hidden">
                              <div
                                className={`h-full rounded-full transition-all duration-500 ${
                                  isMet ? "bg-emerald-500" : "bg-amber-500"
                                }`}
                                style={{ width: `${pct}%` }}
                              />
                            </div>
                          </div>
                        );
                      })()}
                    </td>
                    <td className="py-4 px-6">
                      {caller.is_active ? (
                        <span className="inline-flex items-center gap-1 text-xs font-medium text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
                          <UserCheck className="h-3 w-3" /> Active
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 text-xs font-medium text-slate-500 bg-slate-100 px-2 py-0.5 rounded-full border border-slate-200">
                          <UserX className="h-3 w-3" /> Deactivated
                        </span>
                      )}
                    </td>
                    <td className="py-4 px-6 text-right">
                      <div className="flex items-center justify-end gap-2">
                        <button
                          onClick={() => startEditingCaller(caller)}
                          className="inline-flex items-center gap-1 text-xs font-semibold px-2.5 py-1.5 rounded-lg border border-slate-200 bg-white text-slate-700 hover:bg-slate-50 transition shadow-sm"
                          title="Modify Employee Information"
                        >
                          <Pencil className="h-3.5 w-3.5 text-indigo-600" />
                          Edit
                        </button>
                        <button
                          onClick={() => toggleStatus(caller)}
                          className={`text-xs font-medium px-3 py-1.5 rounded-lg border transition ${
                            caller.is_active
                              ? "text-rose-600 bg-rose-50 border-rose-200 hover:bg-rose-100"
                              : "text-emerald-700 bg-emerald-50 border-emerald-200 hover:bg-emerald-100"
                          }`}
                        >
                          {caller.is_active ? "Deactivate" : "Reactivate"}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Add Caller Modal */}
      {modalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="bg-white rounded-2xl max-w-md w-full shadow-2xl border border-slate-200 overflow-hidden">
            <div className="flex items-center justify-between p-6 border-b border-slate-100 bg-slate-50/50">
              <div className="flex items-center gap-2.5">
                <div className="p-2 rounded-xl bg-indigo-50 text-indigo-600">
                  <UserPlus className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-slate-900">Add Caller Account</h3>
                  <p className="text-xs text-slate-500">Provide credentials for the employee app</p>
                </div>
              </div>
              <button
                onClick={() => setModalOpen(false)}
                className="p-1 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <form onSubmit={handleCreateCaller} className="p-6 space-y-4">
              {formError && (
                <div className="p-3.5 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs">
                  {formError}
                </div>
              )}

              {formSuccess && (
                <div className="p-3.5 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-700 text-xs flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4" />
                  Caller account created successfully!
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Full Name *
                </label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Ramesh Kumar"
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Login Email *
                </label>
                <input
                  type="email"
                  required
                  placeholder="ramesh@orvyqmedia.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Temporary Password *
                </label>
                <input
                  type="password"
                  required
                  placeholder="Minimum 6 characters"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1 flex items-center justify-between">
                  <span>Caller Mobile SIM Number</span>
                  <span className="text-[10px] text-slate-400 font-normal">Optional</span>
                </label>
                <input
                  type="text"
                  placeholder="e.g. 9876543210 (India)"
                  value={mobile}
                  onChange={(e) => setMobile(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
                <p className="mt-1 text-[11px] text-slate-400">
                  Used by the caller on their Android phone to place calls.
                </p>
              </div>

              <div className="pt-4 border-t border-slate-100 flex items-center justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setModalOpen(false)}
                  className="px-4 py-2 rounded-xl text-xs font-semibold text-slate-600 hover:bg-slate-100 transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={formLoading}
                  className="px-5 py-2.5 rounded-xl text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-700 transition shadow-sm disabled:opacity-50 flex items-center gap-2"
                >
                  {formLoading && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                  Create Account
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Caller Modal */}
      {editModalOpen && editingCaller && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="bg-white rounded-2xl max-w-md w-full shadow-2xl border border-slate-200 overflow-hidden">
            <div className="p-6 border-b border-slate-100 flex items-center justify-between bg-slate-50/50">
              <div className="flex items-center gap-2">
                <div className="p-2 rounded-lg bg-indigo-50 text-indigo-600">
                  <Pencil className="h-5 w-5" />
                </div>
                <div>
                  <h3 className="font-bold text-slate-800">Modify Employee Info</h3>
                  <p className="text-xs text-slate-400">Update caller profile and system role</p>
                </div>
              </div>
              <button
                onClick={() => setEditModalOpen(false)}
                className="p-1 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <form onSubmit={handleUpdateCaller} className="p-6 space-y-4">
              {editError && (
                <div className="p-3.5 rounded-xl bg-rose-50 border border-rose-200 text-rose-700 text-xs">
                  {editError}
                </div>
              )}

              {editSuccess && (
                <div className="p-3.5 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-700 text-xs flex items-center gap-2">
                  <CheckCircle2 className="h-4 w-4" />
                  Employee information updated successfully!
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Full Name *
                </label>
                <input
                  type="text"
                  required
                  value={editFullName}
                  onChange={(e) => setEditFullName(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Login Email
                </label>
                <input
                  type="email"
                  disabled
                  value={editingCaller.email || ""}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 bg-slate-100 text-slate-500 text-sm cursor-not-allowed"
                />
                <p className="mt-1 text-[11px] text-slate-400">
                  Email addresses are linked to auth credentials and immutable here.
                </p>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Caller Mobile SIM Number
                </label>
                <input
                  type="text"
                  placeholder="e.g. 9876543210 (India)"
                  value={editMobile}
                  onChange={(e) => setEditMobile(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  System Role
                </label>
                <select
                  value={editRole}
                  onChange={(e) => setEditRole(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 bg-white"
                >
                  <option value="caller">Caller (Mobile App User)</option>
                  <option value="owner">Owner / Admin (Web Portal Manager)</option>
                </select>
              </div>

              <div className="pt-2">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={editIsActive}
                    onChange={(e) => setEditIsActive(e.target.checked)}
                    className="h-4 w-4 rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                  />
                  <span className="text-sm font-medium text-slate-700">Account Active (Authorized to log in)</span>
                </label>
              </div>

              <div className="pt-4 border-t border-slate-100 flex items-center justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setEditModalOpen(false)}
                  className="px-4 py-2 rounded-xl text-xs font-semibold text-slate-600 hover:bg-slate-100 transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={editLoading}
                  className="px-5 py-2.5 rounded-xl text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-700 transition shadow-sm disabled:opacity-50 flex items-center gap-2"
                >
                  {editLoading && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                  Save Changes
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
