import React from "react";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  PhoneCall,
  LayoutDashboard,
  Users,
  UserCheck,
  History,
  LogOut,
  ShieldCheck,
} from "lucide-react";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Fetch owner profile
  const { data: profile } = await supabase
    .from("profiles")
    .select("full_name, role, email")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "owner") {
    // If signed in user is not an owner, deny access
    redirect("/login?error=unauthorized");
  }

  return (
    <div className="flex min-h-screen bg-slate-50 text-slate-900">
      {/* Sidebar */}
      <aside className="w-64 bg-slate-900 text-slate-300 flex flex-col border-r border-slate-800 shrink-0">
        {/* Brand Header */}
        <div className="h-16 flex items-center px-6 gap-3 border-b border-slate-800 bg-slate-950/40">
          <div className="h-9 w-9 rounded-xl bg-indigo-600 flex items-center justify-center text-white shadow-md shadow-indigo-600/30">
            <PhoneCall className="h-5 w-5" />
          </div>
          <div>
            <div className="font-bold text-white tracking-tight leading-none text-base">
              Orvyqmedia
            </div>
            <div className="text-[10px] uppercase font-semibold text-indigo-400 tracking-wider mt-1 flex items-center gap-1">
              <ShieldCheck className="h-3 w-3" /> Call Tracker
            </div>
          </div>
        </div>

        {/* Navigation Links */}
        <nav className="flex-1 px-3 py-6 space-y-1 text-sm font-medium">
          <Link
            href="/"
            className="flex items-center gap-3 px-3 py-2.5 rounded-xl text-slate-300 hover:text-white hover:bg-slate-800/80 transition"
          >
            <LayoutDashboard className="h-4 w-4 text-indigo-400" />
            Overview
          </Link>

          <Link
            href="/leads"
            className="flex items-center gap-3 px-3 py-2.5 rounded-xl text-slate-300 hover:text-white hover:bg-slate-800/80 transition"
          >
            <Users className="h-4 w-4 text-emerald-400" />
            Leads & Assignment
          </Link>

          <Link
            href="/callers"
            className="flex items-center gap-3 px-3 py-2.5 rounded-xl text-slate-300 hover:text-white hover:bg-slate-800/80 transition"
          >
            <UserCheck className="h-4 w-4 text-amber-400" />
            Caller Accounts
          </Link>

          <Link
            href="/calls"
            className="flex items-center gap-3 px-3 py-2.5 rounded-xl text-slate-300 hover:text-white hover:bg-slate-800/80 transition"
          >
            <History className="h-4 w-4 text-purple-400" />
            Call Log
          </Link>
        </nav>

        {/* User Footer */}
        <div className="p-4 border-t border-slate-800 bg-slate-950/30">
          <div className="flex items-center justify-between">
            <div className="truncate mr-2">
              <div className="text-xs font-semibold text-white truncate">
                {profile?.full_name || "Owner"}
              </div>
              <div className="text-[11px] text-slate-500 truncate">
                {user.email}
              </div>
            </div>
            <form action="/api/auth/signout" method="POST">
              <button
                type="submit"
                title="Sign out"
                className="p-2 rounded-lg text-slate-400 hover:text-rose-400 hover:bg-slate-800 transition"
              >
                <LogOut className="h-4 w-4" />
              </button>
            </form>
          </div>
        </div>
      </aside>

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col min-w-0 overflow-y-auto">
        {children}
      </main>
    </div>
  );
}
