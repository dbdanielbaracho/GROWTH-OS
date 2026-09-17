import React, { useEffect, useState } from "react";
import {
  fetchWorkspaceMembers,
  inviteWorkspaceMember,
  updateWorkspaceMember,
  RadarApiError,
  type WorkspaceInvitationRole,
  type WorkspaceMember,
  type WorkspaceSummary
} from "./api.js";
import "./team-management.css";

type MemberDraft = {
  role: WorkspaceInvitationRole;
  canPublish: boolean;
  status: "active" | "revoked";
};

function memberLabel(member: WorkspaceMember): string {
  return `Member ${member.user_id.slice(0, 8)}`;
}

function errorCopy(error: unknown, fallback: string): string {
  if (!(error instanceof RadarApiError)) return fallback;
  if (error.httpStatus === 403) return "Your current role cannot perform this team action.";
  if (error.httpStatus === 404) return "This member is no longer available.";
  if (error.httpStatus === 409) return "The invitation or membership conflicts with its current state.";
  if (error.apiStatus === "identity_email_unavailable") return "Invitation email delivery is not configured.";
  return fallback;
}

export function TeamManagement({
  workspace,
  onClose
}: {
  workspace: WorkspaceSummary;
  onClose: () => void;
}) {
  const [members, setMembers] = useState<WorkspaceMember[]>([]);
  const [drafts, setDrafts] = useState<Record<string, MemberDraft>>({});
  const [loading, setLoading] = useState(true);
  const [busyMember, setBusyMember] = useState<string | null>(null);
  const [inviteBusy, setInviteBusy] = useState(false);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<WorkspaceInvitationRole>(
    workspace.role === "owner" ? "admin" : "editor"
  );
  const [canPublish, setCanPublish] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setLoading(true);
    fetchWorkspaceMembers(workspace.id)
      .then((rows) => {
        if (!active) return;
        setMembers(rows);
        setDrafts(Object.fromEntries(rows
          .filter((member) => member.role !== "owner")
          .map((member) => [member.user_id, {
            role: member.role as WorkspaceInvitationRole,
            canPublish: member.can_publish,
            status: member.status === "revoked" ? "revoked" : "active"
          }])));
        setLoading(false);
      })
      .catch((caught) => {
        if (!active) return;
        setError(errorCopy(caught, "The team list could not be loaded."));
        setLoading(false);
      });
    return () => { active = false; };
  }, [workspace.id]);

  function canEdit(member: WorkspaceMember): boolean {
    if (member.role === "owner") return false;
    if (workspace.role === "owner") return true;
    return member.role !== "admin";
  }

  async function submitInvitation(event: React.FormEvent) {
    event.preventDefault();
    setInviteBusy(true);
    setMessage(null);
    setError(null);
    try {
      await inviteWorkspaceMember({
        workspaceId: workspace.id,
        email,
        role,
        canPublish
      });
      setEmail("");
      setCanPublish(false);
      setMessage(`Invitation sent to ${email.trim().toLowerCase()}.`);
    } catch (caught) {
      setError(errorCopy(caught, "The invitation could not be sent."));
    } finally {
      setInviteBusy(false);
    }
  }

  async function saveMember(member: WorkspaceMember) {
    const draft = drafts[member.user_id];
    if (!draft || !canEdit(member)) return;
    setBusyMember(member.user_id);
    setMessage(null);
    setError(null);
    try {
      const updated = await updateWorkspaceMember({
        workspaceId: workspace.id,
        userId: member.user_id,
        ...draft
      });
      setMembers((current) => current.map((item) =>
        item.user_id === updated.user_id ? updated : item
      ));
      setMessage(`${memberLabel(updated)} updated.`);
    } catch (caught) {
      setError(errorCopy(caught, "The member could not be updated."));
    } finally {
      setBusyMember(null);
    }
  }

  return (
    <div className="team-overlay" role="presentation">
      <section className="team-dialog" role="dialog" aria-modal="true" aria-labelledby="team-title">
        <header className="team-header">
          <div>
            <p className="eyebrow">Workspace access</p>
            <h2 id="team-title">Team and invitations</h2>
            <p>Manage who can collaborate in {workspace.name}. Provider credentials are never shown here.</p>
          </div>
          <button className="team-close" type="button" onClick={onClose} aria-label="Close team management">×</button>
        </header>

        <form className="team-invite" onSubmit={submitInvitation}>
          <div>
            <h3>Invite a teammate</h3>
            <p>The link is valid for seven days and can only be accepted by the invited verified email.</p>
          </div>
          <label>
            <span>Email</span>
            <input
              type="email"
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
            />
          </label>
          <label>
            <span>Role</span>
            <select value={role} onChange={(event) => setRole(event.target.value as WorkspaceInvitationRole)}>
              {workspace.role === "owner" && <option value="admin">Admin</option>}
              <option value="editor">Editor</option>
              <option value="viewer">Viewer</option>
            </select>
          </label>
          <label className="team-check">
            <input
              type="checkbox"
              checked={canPublish}
              onChange={(event) => setCanPublish(event.target.checked)}
            />
            <span>Allow controlled publishing</span>
          </label>
          <button className="team-primary" type="submit" disabled={inviteBusy}>
            {inviteBusy ? "Sending…" : "Send invitation"}
          </button>
        </form>

        <div className="team-members">
          <div className="team-members-heading">
            <div>
              <h3>Current members</h3>
              <p>Changes remain constrained by owner/admin authority and the database policy.</p>
            </div>
            <span>{members.length} total</span>
          </div>

          {loading && <p className="team-status" role="status">Loading team…</p>}
          {!loading && members.length === 0 && <p className="team-status">No members are visible.</p>}

          {members.map((member) => {
            const draft = drafts[member.user_id];
            const editable = canEdit(member);
            return (
              <article className="team-member" key={member.user_id}>
                <div className="team-member-identity">
                  <strong>{memberLabel(member)}</strong>
                  <code>{member.user_id}</code>
                  <span>{member.role === "owner" ? "Workspace owner" : "Verified workspace member"}</span>
                </div>
                {member.role === "owner" || !draft ? (
                  <div className="team-owner-lock">
                    <span>Owner</span>
                    <small>Protected role</small>
                  </div>
                ) : (
                  <div className="team-member-controls">
                    <label>
                      <span>Role</span>
                      <select
                        aria-label={`Role for ${memberLabel(member)}`}
                        value={draft.role}
                        disabled={!editable || busyMember === member.user_id}
                        onChange={(event) => setDrafts((current) => ({
                          ...current,
                          [member.user_id]: { ...draft, role: event.target.value as WorkspaceInvitationRole }
                        }))}
                      >
                        {workspace.role === "owner" && <option value="admin">Admin</option>}
                        <option value="editor">Editor</option>
                        <option value="viewer">Viewer</option>
                      </select>
                    </label>
                    <label>
                      <span>Status</span>
                      <select
                        aria-label={`Status for ${memberLabel(member)}`}
                        value={draft.status}
                        disabled={!editable || busyMember === member.user_id}
                        onChange={(event) => setDrafts((current) => ({
                          ...current,
                          [member.user_id]: { ...draft, status: event.target.value as "active" | "revoked" }
                        }))}
                      >
                        <option value="active">Active</option>
                        <option value="revoked">Revoked</option>
                      </select>
                    </label>
                    <label className="team-check compact">
                      <input
                        type="checkbox"
                        aria-label={`Publishing permission for ${memberLabel(member)}`}
                        checked={draft.canPublish}
                        disabled={!editable || busyMember === member.user_id}
                        onChange={(event) => setDrafts((current) => ({
                          ...current,
                          [member.user_id]: { ...draft, canPublish: event.target.checked }
                        }))}
                      />
                      <span>Can publish</span>
                    </label>
                    <button
                      type="button"
                      className="team-save"
                      disabled={!editable || busyMember !== null}
                      onClick={() => void saveMember(member)}
                    >
                      {busyMember === member.user_id ? "Saving…" : "Save"}
                    </button>
                    {!editable && <small>Admins cannot change another admin.</small>}
                  </div>
                )}
              </article>
            );
          })}
        </div>

        {message && <p className="team-success" role="status">{message}</p>}
        {error && <p className="team-error" role="alert">{error}</p>}
      </section>
    </div>
  );
}
