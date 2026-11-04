import Testing
@testable import Turbodoc

/// Port of the web app's `note-sync.test.ts`.
private func document(
    title: String = "Plan",
    content: String = "intro",
    version: Int = 1,
    headRevisionId: String? = "r1"
) -> ServerDocument {
    ServerDocument(
        draft: NoteDraft(title: title, content: content),
        headRevisionId: headRevisionId,
        version: version
    )
}

@Suite("afterSave")
struct AfterSaveTests {
    @Test("adopts the merged document when nothing was typed during the save")
    func adoptsMergedDocument() {
        let sent = NoteDraft(title: "Plan", content: "intro + laptop")
        let merged = document(content: "intro + phone + laptop", version: 3, headRevisionId: "r3")
        let decision = NoteSync.afterSave(
            sent: sent,
            latest: sent,
            response: NoteSaveResponse(document: merged, submittedRevisionId: "s1")
        )
        #expect(decision.adopt == merged.draft)
        #expect(decision.synced.revisionId == "r3")
        #expect(decision.synced.version == 3)
    }

    @Test("does not reload the editor when the server kept exactly what was sent")
    func keepsEditorWhenUnchanged() {
        let sent = NoteDraft(title: "Plan", content: "intro!")
        let saved = document(content: "intro!", version: 2, headRevisionId: "r2")
        let decision = NoteSync.afterSave(
            sent: sent,
            latest: sent,
            response: NoteSaveResponse(document: saved, submittedRevisionId: "r2")
        )
        #expect(decision.adopt == nil)
    }

    @Test("rebases on the submitted snapshot when typing continued during the save")
    func rebasesOnSubmittedSnapshot() {
        let sent = NoteDraft(title: "Plan", content: "intro + laptop")
        let latest = NoteDraft(title: "Plan", content: "intro + laptop, more")
        let merged = document(content: "intro + phone + laptop", version: 3, headRevisionId: "r3")
        let decision = NoteSync.afterSave(
            sent: sent,
            latest: latest,
            response: NoteSaveResponse(document: merged, submittedRevisionId: "s1")
        )
        #expect(decision.adopt == nil)
        #expect(decision.synced == SyncedState(draft: sent, revisionId: "s1", version: 3))
        // The newer typing is still unsynced, so it is saved next on top of s1.
        #expect(NoteSync.hasUnsyncedEdits(latest, decision.synced))
    }
}

@Suite("onRemote")
struct OnRemoteTests {
    let synced = SyncedState(document())

    @Test("loads a newer remote version when the editor is idle")
    func loadsNewerRemoteWhenIdle() {
        let remote = document(content: "edited on phone", version: 2, headRevisionId: "r2")
        let decision = NoteSync.onRemote(
            remote: remote,
            synced: synced,
            latest: document().draft,
            saving: false
        )
        #expect(decision?.adopt?.content == "edited on phone")
        #expect(decision?.synced.revisionId == "r2")
    }

    @Test("keeps the base when there are unsaved edits, so the next save merges")
    func keepsBaseWithUnsavedEdits() {
        // Regression: adopting the new head while keeping the old text made
        // the next autosave revert the other device's edit.
        let remote = document(content: "edited on phone", version: 2, headRevisionId: "r2")
        let typing = NoteDraft(title: "Plan", content: "intro, typed on laptop")
        #expect(NoteSync.onRemote(remote: remote, synced: synced, latest: typing, saving: false) == nil)
    }

    @Test("waits while a save is in flight")
    func waitsWhileSaving() {
        let remote = document(content: "edited on phone", version: 2, headRevisionId: "r2")
        #expect(
            NoteSync.onRemote(remote: remote, synced: synced, latest: document().draft, saving: true) == nil
        )
    }

    @Test("ignores server data older than what the editor has seen")
    func ignoresOlderServerData() {
        let current = SyncedState(document(content: "v3", version: 3, headRevisionId: "r3"))
        let lateRefetch = document(content: "v2", version: 2, headRevisionId: "r2")
        #expect(
            NoteSync.onRemote(remote: lateRefetch, synced: current, latest: current.draft, saving: false) == nil
        )
    }
}
