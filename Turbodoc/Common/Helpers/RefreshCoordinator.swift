import Foundation

@MainActor
final class RefreshCoordinator {
    private var inFlight: (id: UUID, task: Task<Void, Never>)?

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        if let inFlight {
            await inFlight.task.value
            return
        }

        let id = UUID()
        let task = Task { await operation() }
        inFlight = (id, task)
        await task.value

        if inFlight?.id == id {
            inFlight = nil
        }
    }
}
