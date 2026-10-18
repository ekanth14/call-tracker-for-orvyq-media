"use client";

import React, { useEffect, useState, useRef } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  MessageSquare,
  Send,
  Megaphone,
  Shield,
  User,
  Clock,
  Sparkles,
  Users,
  Loader2,
} from "lucide-react";

interface MessageItem {
  id: string;
  sender_id: string;
  sender_name: string;
  sender_role: string;
  content: string;
  is_announcement: boolean;
  created_at: string;
}

export default function ChatPage() {
  const [messages, setMessages] = useState<MessageItem[]>([]);
  const [input, setInput] = useState("");
  const [isAnnouncement, setIsAnnouncement] = useState(false);
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [currentUserName, setCurrentUserName] = useState("Owner Admin");
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    const supabase = createClient();

    // 1. Get current user
    const initUserAndChat = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (user) {
        setCurrentUserId(user.id);
        const { data: profile } = await supabase
          .from("profiles")
          .select("full_name")
          .eq("id", user.id)
          .single();
        if (profile?.full_name) {
          setCurrentUserName(profile.full_name);
        }
      }

      // 2. Fetch existing messages
      const { data, error } = await supabase
        .from("team_messages")
        .select("*")
        .order("created_at", { ascending: true })
        .limit(100);

      if (!error && data) {
        setMessages(data);
      }
      setLoading(false);
      setTimeout(scrollToBottom, 100);
    };

    initUserAndChat();

    // 3. Realtime subscription
    const channel = supabase
      .channel("team_chat_channel")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "team_messages" },
        (payload) => {
          const newMsg = payload.new as MessageItem;
          setMessages((prev) => {
            if (prev.some((m) => m.id === newMsg.id)) return prev;
            return [...prev, newMsg];
          });
          setTimeout(scrollToBottom, 50);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || sending || !currentUserId) return;

    setSending(true);
    const content = input.trim();
    setInput("");

    const supabase = createClient();
    const { error } = await supabase.from("team_messages").insert({
      sender_id: currentUserId,
      sender_name: currentUserName,
      sender_role: "owner",
      content,
      is_announcement: isAnnouncement,
    });

    if (error) {
      console.error("Error sending message:", error);
      // restore input on error
      setInput(content);
    } else {
      setIsAnnouncement(false);
      setTimeout(scrollToBottom, 50);
    }
    setSending(false);
  };

  return (
    <div className="flex flex-col h-[calc(100vh-64px)] max-w-6xl mx-auto p-4 sm:p-6">
      {/* Header */}
      <div className="flex items-center justify-between pb-4 border-b border-slate-200">
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 rounded-xl bg-indigo-600 flex items-center justify-center text-white shadow-md shadow-indigo-600/20">
            <MessageSquare className="h-5 w-5" />
          </div>
          <div>
            <h1 className="text-xl font-bold text-slate-900 tracking-tight flex items-center gap-2">
              Team Discussion & Community
              <span className="flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200 font-medium">
                <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse"></span>
                Live Realtime
              </span>
            </h1>
            <p className="text-xs text-slate-500">
              Live discussion channel across Web and Android mobile caller apps
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2 text-xs font-medium text-slate-600 bg-slate-100 px-3 py-1.5 rounded-lg border border-slate-200">
          <Users className="h-3.5 w-3.5 text-slate-500" />
          <span>Team Channel</span>
        </div>
      </div>

      {/* Messages Stream */}
      <div className="flex-1 overflow-y-auto py-4 space-y-3.5 pr-2">
        {loading ? (
          <div className="flex flex-col items-center justify-center h-full text-slate-400 gap-2">
            <Loader2 className="h-6 w-6 animate-spin text-indigo-500" />
            <p className="text-xs">Connecting to team channel...</p>
          </div>
        ) : messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center p-8 bg-slate-50 rounded-2xl border border-dashed border-slate-200">
            <div className="h-12 w-12 rounded-2xl bg-indigo-50 flex items-center justify-center text-indigo-600 mb-3">
              <Sparkles className="h-6 w-6" />
            </div>
            <h3 className="text-sm font-semibold text-slate-800">
              Welcome to the Team Chat!
            </h3>
            <p className="text-xs text-slate-500 max-w-sm mt-1">
              Start the discussion! Send an update, announcement, or greeting to
              your calling team.
            </p>
          </div>
        ) : (
          messages.map((msg) => {
            const isMe = msg.sender_id === currentUserId;
            const timeStr = new Date(msg.created_at).toLocaleTimeString([], {
              hour: "2-digit",
              minute: "2-digit",
            });

            return (
              <div
                key={msg.id}
                className={`flex flex-col ${
                  isMe ? "items-end" : "items-start"
                }`}
              >
                {/* Announcement Card Styling */}
                {msg.is_announcement ? (
                  <div className="w-full my-2 p-4 rounded-xl bg-amber-50 border border-amber-200 shadow-sm flex items-start gap-3">
                    <div className="h-8 w-8 rounded-lg bg-amber-500 text-white flex items-center justify-center shrink-0">
                      <Megaphone className="h-4 w-4" />
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-bold uppercase tracking-wider text-amber-900">
                          Official Team Announcement • {msg.sender_name}
                        </span>
                        <span className="text-[10px] text-amber-700">
                          {timeStr}
                        </span>
                      </div>
                      <p className="text-sm text-amber-950 font-medium mt-1 whitespace-pre-wrap">
                        {msg.content}
                      </p>
                    </div>
                  </div>
                ) : (
                  <div
                    className={`max-w-[78%] sm:max-w-[65%] rounded-2xl p-3.5 shadow-sm text-sm ${
                      isMe
                        ? "bg-indigo-600 text-white rounded-br-xs"
                        : "bg-white text-slate-900 border border-slate-200 rounded-bl-xs"
                    }`}
                  >
                    {/* Header with Sender info */}
                    {!isMe && (
                      <div className="flex items-center gap-1.5 mb-1">
                        <span className="text-xs font-bold text-slate-800">
                          {msg.sender_name}
                        </span>
                        <span
                          className={`text-[9px] px-1.5 py-0.2 rounded font-semibold uppercase ${
                            msg.sender_role === "owner"
                              ? "bg-indigo-100 text-indigo-700"
                              : "bg-emerald-100 text-emerald-700"
                          }`}
                        >
                          {msg.sender_role}
                        </span>
                      </div>
                    )}

                    <div className="whitespace-pre-wrap break-words leading-relaxed text-sm">
                      {msg.content}
                    </div>

                    <div
                      className={`flex items-center justify-end gap-1 mt-1 text-[10px] ${
                        isMe ? "text-indigo-200" : "text-slate-400"
                      }`}
                    >
                      <Clock className="h-2.5 w-2.5" />
                      <span>{timeStr}</span>
                    </div>
                  </div>
                )}
              </div>
            );
          })
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Input Box */}
      <form
        onSubmit={handleSendMessage}
        className="pt-3 border-t border-slate-200 bg-white"
      >
        <div className="flex items-center gap-2 mb-2">
          <label className="flex items-center gap-1.5 text-xs cursor-pointer select-none text-slate-600 font-medium">
            <input
              type="checkbox"
              checked={isAnnouncement}
              onChange={(e) => setIsAnnouncement(e.target.checked)}
              className="h-3.5 w-3.5 text-amber-600 rounded border-slate-300 focus:ring-amber-500"
            />
            <Megaphone
              className={`h-3.5 w-3.5 ${
                isAnnouncement ? "text-amber-500" : "text-slate-400"
              }`}
            />
            <span>Broadcast as Team Announcement</span>
          </label>
        </div>

        <div className="flex items-center gap-2">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder={
              isAnnouncement
                ? "Type an official announcement for all callers..."
                : "Type a message to the team..."
            }
            className="flex-1 px-4 py-3 rounded-xl border border-slate-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent bg-slate-50/50"
          />
          <button
            type="submit"
            disabled={!input.trim() || sending}
            className="px-5 py-3 rounded-xl bg-indigo-600 text-white font-medium text-sm hover:bg-indigo-700 transition flex items-center gap-1.5 shadow-sm shadow-indigo-600/20 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
          >
            {sending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <>
                <span>Send</span>
                <Send className="h-4 w-4" />
              </>
            )}
          </button>
        </div>
      </form>
    </div>
  );
}
