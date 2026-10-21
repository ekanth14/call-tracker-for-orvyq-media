"use client";

import React, { useEffect, useState, useRef } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  MessageSquare,
  Send,
  Megaphone,
  Sparkles,
  Users,
  Loader2,
  CheckCheck,
  Pencil,
  Trash2,
  X,
  Check,
  AlertTriangle,
} from "lucide-react";

interface MessageItem {
  id: string;
  sender_id: string;
  sender_name: string;
  sender_role: string;
  content: string;
  is_announcement: boolean;
  is_edited?: boolean;
  edited_at?: string;
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
  const [currentUserRole, setCurrentUserRole] = useState("owner");

  // Moderation state (Admin only)
  const [editingMessageId, setEditingMessageId] = useState<string | null>(null);
  const [editContent, setEditContent] = useState("");
  const [savingEdit, setSavingEdit] = useState(false);
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const messagesEndRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    const supabase = createClient();

    // 1. Get current user & role
    const initUserAndChat = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (user) {
        setCurrentUserId(user.id);
        const { data: profile } = await supabase
          .from("profiles")
          .select("full_name, role")
          .eq("id", user.id)
          .single();
        if (profile?.full_name) {
          setCurrentUserName(profile.full_name);
        }
        if (profile?.role) {
          setCurrentUserRole(profile.role);
        }
      }

      // 2. Fetch existing messages
      const { data, error } = await supabase
        .from("team_messages")
        .select("*")
        .order("created_at", { ascending: true })
        .limit(100);

      if (!error && data) {
        setMessages(data as MessageItem[]);
      }
      setLoading(false);
      setTimeout(scrollToBottom, 100);
    };

    initUserAndChat();

    // 3. Realtime subscription (INSERT, UPDATE, DELETE)
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
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "team_messages" },
        (payload) => {
          const updated = payload.new as MessageItem;
          setMessages((prev) =>
            prev.map((m) =>
              m.id === updated.id
                ? { ...m, ...updated, is_edited: true }
                : m
            )
          );
        }
      )
      .on(
        "postgres_changes",
        { event: "DELETE", schema: "public", table: "team_messages" },
        (payload) => {
          const deletedId = (payload.old as { id: string })?.id;
          if (deletedId) {
            setMessages((prev) => prev.filter((m) => m.id !== deletedId));
          }
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
    const announcementMode = isAnnouncement;
    setInput("");

    const supabase = createClient();
    const { data: inserted, error } = await supabase
      .from("team_messages")
      .insert({
        sender_id: currentUserId,
        sender_name: currentUserName,
        sender_role: currentUserRole,
        content,
        is_announcement: announcementMode,
      })
      .select()
      .single();

    if (error) {
      console.error("Error sending message:", error);
      // restore input on error
      setInput(content);
    } else if (inserted) {
      // Optimistically add immediately to eliminate websocket latency and loading feel
      setMessages((prev) => {
        if (prev.some((m) => m.id === inserted.id)) return prev;
        return [...prev, inserted as MessageItem];
      });
      setIsAnnouncement(false);
      setTimeout(scrollToBottom, 50);
    }
    setSending(false);
  };

  // Moderation: Start Editing
  const startEditing = (msg: MessageItem) => {
    setEditingMessageId(msg.id);
    setEditContent(msg.content);
    setConfirmDeleteId(null);
  };

  const cancelEditing = () => {
    setEditingMessageId(null);
    setEditContent("");
  };

  // Moderation: Save Edited Message
  const saveEdit = async (msgId: string) => {
    if (!editContent.trim() || savingEdit) return;

    setSavingEdit(true);
    try {
      const res = await fetch("/api/chat/messages", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messageId: msgId, content: editContent.trim() }),
      });

      if (res.ok) {
        const data = await res.json();
        setMessages((prev) =>
          prev.map((m) =>
            m.id === msgId
              ? { ...m, content: editContent.trim(), is_edited: true }
              : m
          )
        );
        setEditingMessageId(null);
        setEditContent("");
      } else {
        const err = await res.json();
        alert(`Failed to edit message: ${err.error || "Permission denied"}`);
      }
    } catch (err: any) {
      alert(`Network error: ${err.message}`);
    } finally {
      setSavingEdit(false);
    }
  };

  // Moderation: Delete Message of Everyone
  const deleteMessage = async (msgId: string) => {
    setDeletingId(msgId);
    try {
      const res = await fetch(`/api/chat/messages?id=${msgId}`, {
        method: "DELETE",
      });

      if (res.ok) {
        setMessages((prev) => prev.filter((m) => m.id !== msgId));
        setConfirmDeleteId(null);
      } else {
        const err = await res.json();
        alert(`Failed to delete message: ${err.error || "Permission denied"}`);
      }
    } catch (err: any) {
      alert(`Network error: ${err.message}`);
    } finally {
      setDeletingId(null);
    }
  };

  const isOwner = currentUserRole === "owner";

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
              {isOwner && (
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-indigo-50 text-indigo-700 border border-indigo-200 font-semibold uppercase tracking-wider">
                  Admin Moderation Enabled
                </span>
              )}
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
            const isEditing = editingMessageId === msg.id;
            const isConfirmingDelete = confirmDeleteId === msg.id;
            const isDeleting = deletingId === msg.id;
            const timeStr = new Date(msg.created_at).toLocaleTimeString([], {
              hour: "2-digit",
              minute: "2-digit",
            });

            return (
              <div
                key={msg.id}
                className={`group flex flex-col ${
                  isMe ? "items-end" : "items-start"
                }`}
              >
                {/* Announcement Card Styling */}
                {msg.is_announcement ? (
                  <div className="relative w-full my-2 p-4 rounded-xl bg-amber-50 border border-amber-200 shadow-sm flex items-start gap-3">
                    <div className="h-8 w-8 rounded-lg bg-amber-500 text-white flex items-center justify-center shrink-0">
                      <Megaphone className="h-4 w-4" />
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-bold uppercase tracking-wider text-amber-900">
                          Official Team Announcement • {msg.sender_name}
                        </span>
                        <div className="flex items-center gap-2">
                          <span className="text-[10px] text-amber-700">
                            {timeStr}
                          </span>
                          {msg.is_edited && (
                            <span className="text-[9px] italic text-amber-600 font-medium">
                              (edited)
                            </span>
                          )}
                        </div>
                      </div>

                      {isEditing ? (
                        <div className="mt-2 space-y-2">
                          <textarea
                            value={editContent}
                            onChange={(e) => setEditContent(e.target.value)}
                            className="w-full p-2.5 text-sm bg-white border border-amber-300 rounded-lg text-slate-900 focus:outline-none focus:ring-2 focus:ring-amber-500"
                            rows={3}
                          />
                          <div className="flex items-center gap-2">
                            <button
                              onClick={() => saveEdit(msg.id)}
                              disabled={savingEdit || !editContent.trim()}
                              className="px-3 py-1 bg-amber-600 text-white text-xs font-medium rounded-md hover:bg-amber-700 transition flex items-center gap-1 cursor-pointer disabled:opacity-50"
                            >
                              {savingEdit ? (
                                <Loader2 className="h-3 w-3 animate-spin" />
                              ) : (
                                <Check className="h-3 w-3" />
                              )}
                              Save
                            </button>
                            <button
                              onClick={cancelEditing}
                              className="px-3 py-1 bg-white border border-slate-300 text-slate-700 text-xs font-medium rounded-md hover:bg-slate-50 transition cursor-pointer"
                            >
                              Cancel
                            </button>
                          </div>
                        </div>
                      ) : (
                        <p className="text-sm text-amber-950 font-medium mt-1 whitespace-pre-wrap">
                          {msg.content}
                        </p>
                      )}

                      {/* Admin Moderation Actions for Announcements */}
                      {isOwner && !isEditing && (
                        <div className="mt-2 pt-2 border-t border-amber-200/60 flex items-center justify-end gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                          {isConfirmingDelete ? (
                            <div className="flex items-center gap-2 bg-red-50 px-2 py-1 rounded-md border border-red-200 text-xs">
                              <span className="text-red-700 font-medium">
                                Delete announcement for everyone?
                              </span>
                              <button
                                onClick={() => deleteMessage(msg.id)}
                                disabled={isDeleting}
                                className="px-2 py-0.5 bg-red-600 text-white text-[11px] rounded hover:bg-red-700 transition font-medium cursor-pointer"
                              >
                                {isDeleting ? "Deleting..." : "Yes, Delete"}
                              </button>
                              <button
                                onClick={() => setConfirmDeleteId(null)}
                                className="px-2 py-0.5 bg-white border border-slate-300 text-slate-700 text-[11px] rounded hover:bg-slate-100 transition cursor-pointer"
                              >
                                Cancel
                              </button>
                            </div>
                          ) : (
                            <>
                              <button
                                onClick={() => startEditing(msg)}
                                className="flex items-center gap-1 text-[11px] font-medium text-amber-800 hover:text-amber-950 bg-amber-100/70 hover:bg-amber-200/70 px-2 py-1 rounded transition cursor-pointer"
                                title="Edit announcement (Admin only)"
                              >
                                <Pencil className="h-3 w-3" />
                                <span>Edit</span>
                              </button>
                              <button
                                onClick={() => setConfirmDeleteId(msg.id)}
                                className="flex items-center gap-1 text-[11px] font-medium text-red-600 hover:text-red-800 bg-red-50 hover:bg-red-100 px-2 py-1 rounded transition cursor-pointer"
                                title="Delete announcement (Admin only)"
                              >
                                <Trash2 className="h-3 w-3" />
                                <span>Delete</span>
                              </button>
                            </>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                ) : (
                  /* Standard Chat Bubble */
                  <div className="relative group/bubble flex items-center gap-1.5 max-w-[85%] sm:max-w-[70%]">
                    {/* Admin actions placed to the left for outgoing (isMe) or right for incoming */}
                    {isOwner && isMe && !isEditing && (
                      <div className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1 shrink-0">
                        <button
                          onClick={() => startEditing(msg)}
                          className="p-1 rounded-md text-slate-400 hover:text-indigo-600 hover:bg-slate-100 transition cursor-pointer"
                          title="Edit message (Admin)"
                        >
                          <Pencil className="h-3 w-3" />
                        </button>
                        <button
                          onClick={() => setConfirmDeleteId(msg.id)}
                          className="p-1 rounded-md text-slate-400 hover:text-red-600 hover:bg-red-50 transition cursor-pointer"
                          title="Delete message for everyone (Admin)"
                        >
                          <Trash2 className="h-3 w-3" />
                        </button>
                      </div>
                    )}

                    <div
                      className={`flex-1 rounded-2xl p-3.5 shadow-sm text-sm ${
                        isMe
                          ? "bg-indigo-600 text-white rounded-br-xs"
                          : "bg-white text-slate-900 border border-slate-200 rounded-bl-xs"
                      }`}
                    >
                      {/* Sender info */}
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

                      {/* Content or Edit Form */}
                      {isEditing ? (
                        <div className="space-y-2 my-1">
                          <textarea
                            value={editContent}
                            onChange={(e) => setEditContent(e.target.value)}
                            className="w-full p-2 text-xs text-slate-900 bg-white border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500"
                            rows={2}
                          />
                          <div className="flex items-center justify-end gap-1.5">
                            <button
                              onClick={() => saveEdit(msg.id)}
                              disabled={savingEdit || !editContent.trim()}
                              className="px-2.5 py-1 bg-emerald-600 text-white text-[11px] font-medium rounded hover:bg-emerald-700 transition flex items-center gap-1 cursor-pointer disabled:opacity-50"
                            >
                              {savingEdit ? (
                                <Loader2 className="h-3 w-3 animate-spin" />
                              ) : (
                                <Check className="h-3 w-3" />
                              )}
                              Save
                            </button>
                            <button
                              onClick={cancelEditing}
                              className="px-2.5 py-1 bg-slate-200 text-slate-700 text-[11px] font-medium rounded hover:bg-slate-300 transition cursor-pointer"
                            >
                              Cancel
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="whitespace-pre-wrap break-words leading-relaxed text-sm">
                          {msg.content}
                        </div>
                      )}

                      {/* Confirm Delete Prompt */}
                      {isConfirmingDelete && (
                        <div className="mt-2 pt-2 border-t border-slate-200/40 text-xs">
                          <div className="flex flex-col gap-1.5 bg-red-500/10 p-2 rounded-lg">
                            <span
                              className={`text-[11px] font-medium ${
                                isMe ? "text-indigo-100" : "text-red-700"
                              }`}
                            >
                              Delete this message for everyone?
                            </span>
                            <div className="flex items-center gap-1.5">
                              <button
                                onClick={() => deleteMessage(msg.id)}
                                disabled={isDeleting}
                                className="px-2 py-0.5 bg-red-600 text-white text-[10px] font-semibold rounded hover:bg-red-700 transition cursor-pointer"
                              >
                                {isDeleting ? "Deleting..." : "Delete"}
                              </button>
                              <button
                                onClick={() => setConfirmDeleteId(null)}
                                className={`px-2 py-0.5 text-[10px] rounded font-medium cursor-pointer ${
                                  isMe
                                    ? "bg-indigo-700 text-indigo-100 hover:bg-indigo-800"
                                    : "bg-slate-200 text-slate-700 hover:bg-slate-300"
                                }`}
                              >
                                Cancel
                              </button>
                            </div>
                          </div>
                        </div>
                      )}

                      {/* Footer: Time and Status without misleading Clock icon */}
                      <div
                        className={`flex items-center justify-end gap-1 mt-1 text-[10px] ${
                          isMe ? "text-indigo-200" : "text-slate-400"
                        }`}
                      >
                        {msg.is_edited && (
                          <span className="italic opacity-80 mr-0.5">
                            (edited)
                          </span>
                        )}
                        <span>{timeStr}</span>
                        {isMe && (
                          <span title="Delivered">
                            <CheckCheck className="h-3 w-3 text-indigo-200 inline ml-0.5" />
                          </span>
                        )}
                      </div>
                    </div>

                    {/* Admin actions placed to the right for incoming employee messages */}
                    {isOwner && !isMe && !isEditing && (
                      <div className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1 shrink-0">
                        <button
                          onClick={() => startEditing(msg)}
                          className="p-1 rounded-md text-slate-400 hover:text-indigo-600 hover:bg-slate-100 transition cursor-pointer"
                          title="Edit employee message (Admin moderation)"
                        >
                          <Pencil className="h-3 w-3" />
                        </button>
                        <button
                          onClick={() => setConfirmDeleteId(msg.id)}
                          className="p-1 rounded-md text-slate-400 hover:text-red-600 hover:bg-red-50 transition cursor-pointer"
                          title="Delete message of everyone (Admin moderation)"
                        >
                          <Trash2 className="h-3 w-3" />
                        </button>
                      </div>
                    )}
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
        {isOwner && (
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
        )}

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
