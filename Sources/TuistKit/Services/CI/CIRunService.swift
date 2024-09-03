import Foundation
import tart
import Virtualization
import TuistSupport

struct CIRunService {
    func run() async throws {
        let path = FileHandler.shared.currentPath
        let client = WebSocketClient()
        client.connect()

        // Wait for the connection to be established
        sleep(2)

        let command = "echo 'Hello from Elixir!' && sleep 1 && echo 'Again hello!'"
        client.runCommand(command)

        // Keep the main thread alive to receive messages
        sleep(10000)
    }
}

final class WebSocketClient {
    private var webSocketTask: URLSessionWebSocketTask?

    func connect() {
        let url = URL(string: "ws://localhost:8080/socket/websocket")!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()

        joinChannel()
        receiveMessages()
    }

    private func joinChannel() {
        let joinMessage = """
        {"topic":"ci:lobby","event":"phx_join","payload":{},"ref":"1"}
        """
        sendMessage(joinMessage)
    }

    func runCommand(_ command: String) {
        let commandMessage = """
        {"topic":"ci:lobby","event":"run_command","payload":{"command":"\(command)"},"ref":"2"}
        """
        sendMessage(commandMessage)
    }

    private func sendMessage(_ message: String) {
        let message = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    print("Received message: \(text)")
                case .data(let data):
                    print("Received data: \(data)")
                @unknown default:
                    fatalError()
                }
                self?.receiveMessages()
            }
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }
}
