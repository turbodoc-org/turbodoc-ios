import Foundation
import Network
import Combine

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.turbodoc.networkmonitor")
    
    private(set) var isConnected: Bool = true
    private(set) var connectionType: ConnectionType = .unknown
    private(set) var isExpensive: Bool = false
    
    // Publisher for connection state changes
    let connectionStatusChanged = PassthroughSubject<Bool, Never>()
    
    enum ConnectionType {
        case wifi
        case cellular
        case wiredEthernet
        case unknown
    }
    
    private init() {
        monitor = NWPathMonitor()
    }
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            let wasConnected = self.isConnected
            let newConnectionStatus = path.status == .satisfied
            
            DispatchQueue.main.async {
                self.isConnected = newConnectionStatus
                self.isExpensive = path.isExpensive
                self.updateConnectionType(path)
                
                // Notify observers if connection status changed
                if wasConnected != newConnectionStatus {
                    self.connectionStatusChanged.send(newConnectionStatus)
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
    
    private func updateConnectionType(_ path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else {
            connectionType = .unknown
        }
    }
    
    // Check if we should allow expensive operations (e.g., large syncs)
    var allowExpensiveOperations: Bool {
        return isConnected && !isExpensive
    }
}
