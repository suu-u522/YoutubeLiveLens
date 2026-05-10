import Foundation
import FirebaseFirestore

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var job: AnalysisJob?

    private let jobId: String
    private var listener: ListenerRegistration?

    init(jobId: String) {
        self.jobId = jobId
        startListening()
    }

    deinit {
        listener?.remove()
    }

    private func startListening() {
        listener = FirebaseService.shared.listenJob(jobId: jobId) { [weak self] job in
            Task { @MainActor in
                self?.job = job
            }
        }
    }
}
