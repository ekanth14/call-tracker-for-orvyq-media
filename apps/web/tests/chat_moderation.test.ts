import { describe, it, expect } from "vitest";

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

// Emulates client/server deduplication and moderation logic
function deduplicateMessages(messages: MessageItem[]): MessageItem[] {
  const uniqueMap = new Map<string, MessageItem>();
  for (const msg of messages) {
    if (msg.id) {
      uniqueMap.set(msg.id, msg);
    }
  }
  return Array.from(uniqueMap.values()).sort(
    (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  );
}

function canModerateMessage(userRole: string | null | undefined): boolean {
  return userRole === "owner";
}

function applyAdminEdit(
  message: MessageItem,
  newContent: string,
  userRole: string
): { success: boolean; message?: MessageItem; error?: string } {
  if (!canModerateMessage(userRole)) {
    return {
      success: false,
      error: "Forbidden: Only owners/admins can edit team messages.",
    };
  }

  if (!newContent || !newContent.trim()) {
    return { success: false, error: "Message content cannot be empty." };
  }

  return {
    success: true,
    message: {
      ...message,
      content: newContent.trim(),
      is_edited: true,
      edited_at: new Date().toISOString(),
    },
  };
}

function applyAdminDelete(
  messages: MessageItem[],
  messageIdToDelete: string,
  userRole: string
): { success: boolean; remainingMessages?: MessageItem[]; error?: string } {
  if (!canModerateMessage(userRole)) {
    return {
      success: false,
      error: "Forbidden: Only owners/admins can delete team messages.",
    };
  }

  return {
    success: true,
    remainingMessages: messages.filter((m) => m.id !== messageIdToDelete),
  };
}

describe("Team Chat Moderation & Deduplication Rules", () => {
  const sampleMessages: MessageItem[] = [
    {
      id: "msg-1",
      sender_id: "caller-1",
      sender_name: "ekanth",
      sender_role: "caller",
      content: "Hey what are you guys doing?",
      is_announcement: false,
      created_at: "2026-10-18T15:19:36.826Z",
    },
    {
      id: "msg-2",
      sender_id: "caller-2",
      sender_name: "nishchal",
      sender_role: "caller",
      content: "Crazy",
      is_announcement: false,
      created_at: "2026-10-19T19:09:31.294Z",
    },
    {
      id: "msg-3",
      sender_id: "owner-1",
      sender_name: "Owner Admin",
      sender_role: "owner",
      content: "Official notice",
      is_announcement: true,
      created_at: "2026-10-19T20:00:17.302Z",
    },
  ];

  it("deduplicates messages having identical IDs (fixing the 'goes twice' bug)", () => {
    const rawWithDuplicates = [
      ...sampleMessages,
      // Duplicate of msg-2 arriving from stream/websocket re-entry
      { ...sampleMessages[1] },
      { ...sampleMessages[1] },
    ];

    expect(rawWithDuplicates.length).toBe(5);
    const deduped = deduplicateMessages(rawWithDuplicates);
    expect(deduped.length).toBe(3);
    expect(deduped.map((m) => m.id)).toEqual(["msg-1", "msg-2", "msg-3"]);
  });

  it("strictly forbids caller/employee from editing any message", () => {
    const res = applyAdminEdit(sampleMessages[0], "Tampered content", "caller");
    expect(res.success).toBe(false);
    expect(res.error).toMatch(/Forbidden.*owners\/admins/i);
  });

  it("strictly forbids anonymous or unassigned roles from editing", () => {
    const res = applyAdminEdit(sampleMessages[0], "Tampered content", "");
    expect(res.success).toBe(false);
    expect(res.error).toMatch(/Forbidden.*owners\/admins/i);
  });

  it("allows admin/owner to edit their own message or employee message", () => {
    // Admin editing an employee's message
    const editCallerMsg = applyAdminEdit(
      sampleMessages[0],
      "Moderated content by Admin",
      "owner"
    );
    expect(editCallerMsg.success).toBe(true);
    expect(editCallerMsg.message?.content).toBe("Moderated content by Admin");
    expect(editCallerMsg.message?.is_edited).toBe(true);
    // Sender identity is preserved
    expect(editCallerMsg.message?.sender_name).toBe("ekanth");
    expect(editCallerMsg.message?.sender_id).toBe("caller-1");

    // Admin editing an announcement
    const editAnnouncement = applyAdminEdit(
      sampleMessages[2],
      "Updated official notice",
      "owner"
    );
    expect(editAnnouncement.success).toBe(true);
    expect(editAnnouncement.message?.content).toBe("Updated official notice");
    expect(editAnnouncement.message?.is_edited).toBe(true);
  });

  it("strictly forbids caller/employee from deleting messages of others or themselves", () => {
    const res = applyAdminDelete(sampleMessages, "msg-1", "caller");
    expect(res.success).toBe(false);
    expect(res.error).toMatch(/Forbidden.*owners\/admins/i);
  });

  it("allows admin/owner to delete any message (employee or owner)", () => {
    // Admin deletes employee message msg-2
    const delEmployeeMsg = applyAdminDelete(sampleMessages, "msg-2", "owner");
    expect(delEmployeeMsg.success).toBe(true);
    expect(delEmployeeMsg.remainingMessages?.length).toBe(2);
    expect(
      delEmployeeMsg.remainingMessages?.some((m) => m.id === "msg-2")
    ).toBe(false);

    // Admin deletes an announcement msg-3
    const delAnnouncement = applyAdminDelete(sampleMessages, "msg-3", "owner");
    expect(delAnnouncement.success).toBe(true);
    expect(delAnnouncement.remainingMessages?.length).toBe(2);
    expect(
      delAnnouncement.remainingMessages?.some((m) => m.id === "msg-3")
    ).toBe(false);
  });
});
