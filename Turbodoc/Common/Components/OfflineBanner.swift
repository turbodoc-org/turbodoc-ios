import SwiftUI

struct OfflineBanner: View {
    let isConnected: Bool
    let pendingOperations: Int
    let onTapSync: () -> Void
    
    var body: some View {
        if !isConnected || pendingOperations > 0 {
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: isConnected ? "arrow.triangle.2.circlepath" : "wifi.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                // Status text
                VStack(alignment: .leading, spacing: 2) {
                    Text(isConnected ? "Syncing..." : "Offline")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if pendingOperations > 0 {
                        Text("\(pendingOperations) pending change\(pendingOperations == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.9))
                    } else if !isConnected {
                        Text("Changes will sync when online")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                
                Spacer()
                
                // Sync button (only when online and has pending ops)
                if isConnected && pendingOperations > 0 {
                    Button(action: onTapSync) {
                        Text("Sync Now")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: isConnected ? [Color.blue, Color.blue.opacity(0.8)] : [Color.orange, Color.orange.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct SyncStatusView: View {
    @State private var isConnected = NetworkMonitor.shared.isConnected
    @State private var pendingCount = SyncQueueManager.shared.pendingOperationsCount
    @State private var lastSyncTime = SyncQueueManager.shared.lastSyncTime
    
    var body: some View {
        HStack(spacing: 8) {
            // Connection indicator
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            // Status text
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Pending operations badge
            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .onReceive(NetworkMonitor.shared.connectionStatusChanged) { connected in
            isConnected = connected
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Update pending count periodically
            pendingCount = SyncQueueManager.shared.pendingOperationsCount
            lastSyncTime = SyncQueueManager.shared.lastSyncTime
        }
    }
    
    private var statusText: String {
        if !isConnected {
            return "Offline"
        } else if pendingCount > 0 {
            return "Syncing"
        } else if let lastSync = lastSyncTime {
            let interval = Date().timeIntervalSince(lastSync)
            if interval < 60 {
                return "Just now"
            } else if interval < 3600 {
                return "\(Int(interval / 60))m ago"
            } else {
                return "\(Int(interval / 3600))h ago"
            }
        } else {
            return "Synced"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        OfflineBanner(
            isConnected: false,
            pendingOperations: 5,
            onTapSync: {}
        )
        
        OfflineBanner(
            isConnected: true,
            pendingOperations: 3,
            onTapSync: {}
        )
        
        SyncStatusView()
    }
    .padding()
}
