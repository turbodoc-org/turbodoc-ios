import Foundation

// Sync rules for an open note editor. Port of the web app's `note-sync.ts`.
//
// The editor tracks the last document it agreed on with the server: its
// content and the revision that holds exactly that content. Every save sends
// that revision as `base_revision_id`, so the server merges with anything that
// changed since. The base only moves to a newer revision when the editor also
// holds or loads that revision's content. Otherwise the next save would
// overwrite edits it never saw.

/// What the user edits in a note. A missing title is treated as "".
struct NoteDraft: Equatable, Sendable {
    var title: String
    var content: String

    init(title: String?, content: String) {
        self.title = title ?? ""
        self.content = content
    }
}

/// A document as the server returned it.
struct ServerDocument: Equatable, Sendable {
    var draft: NoteDraft
    var headRevisionId: String?
    var version: Int
}

/// The last document this editor agreed on with the server, and the revision
/// that holds exactly that document.
struct SyncedState: Equatable, Sendable {
    var draft: NoteDraft
    /// Revision holding exactly `draft`. Sent as the next save's base.
    var revisionId: String?
    /// Server version this state came from. Older server data is ignored.
    var version: Int

    init(draft: NoteDraft, revisionId: String?, version: Int) {
        self.draft = draft
        self.revisionId = revisionId
        self.version = version
    }

    init(_ document: ServerDocument) {
        self.init(
            draft: document.draft,
            revisionId: document.headRevisionId,
            version: document.version
        )
    }
}

/// What a save returned, as far as the sync rules are concerned.
struct NoteSaveResponse: Equatable, Sendable {
    var document: ServerDocument
    /// Revision holding exactly what this save sent.
    var submittedRevisionId: String?
}

struct NoteSyncDecision: Equatable, Sendable {
    var synced: SyncedState
    /// Server draft to load into the editor, or nil to keep the editor as is.
    var adopt: NoteDraft?
}

enum NoteSync {
    /// True when the editor holds edits the server has not received.
    static func hasUnsyncedEdits(_ latest: NoteDraft, _ synced: SyncedState) -> Bool {
        latest != synced.draft
    }

    /// After a save returns. If nothing was typed while it was in flight, take
    /// the server's (possibly merged) document. Otherwise keep the editor as
    /// is and rebase on the snapshot that was sent: the next save merges only
    /// the newer typing.
    static func afterSave(
        sent: NoteDraft,
        latest: NoteDraft,
        response: NoteSaveResponse
    ) -> NoteSyncDecision {
        if latest == sent {
            let server = response.document.draft
            return NoteSyncDecision(
                synced: SyncedState(response.document),
                adopt: server == latest ? nil : server
            )
        }
        return NoteSyncDecision(
            synced: SyncedState(
                draft: sent,
                revisionId: response.submittedRevisionId ?? response.document.headRevisionId,
                version: response.document.version
            ),
            adopt: nil
        )
    }

    /// When newer server data arrives (refetch, live update). It is loaded
    /// only if the editor has no unsaved edits and no save is in flight.
    /// Otherwise the pending save merges with it.
    static func onRemote(
        remote: ServerDocument,
        synced: SyncedState,
        latest: NoteDraft,
        saving: Bool
    ) -> NoteSyncDecision? {
        if saving { return nil }
        if remote.version <= synced.version { return nil }
        if let head = remote.headRevisionId, head == synced.revisionId { return nil }
        if hasUnsyncedEdits(latest, synced) { return nil }
        let server = remote.draft
        return NoteSyncDecision(
            synced: SyncedState(remote),
            adopt: server == latest ? nil : server
        )
    }
}

// MARK: - NoteItem bridging

extension NoteDraft {
    init(_ note: NoteItem) {
        self.init(title: note.title, content: note.content)
    }
}

extension ServerDocument {
    init(_ note: NoteItem) {
        self.init(
            draft: NoteDraft(note),
            headRevisionId: note.headRevisionId,
            version: note.version
        )
    }
}

extension SyncedState {
    init(_ note: NoteItem) {
        self.init(ServerDocument(note))
    }
}
