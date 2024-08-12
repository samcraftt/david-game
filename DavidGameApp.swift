import SwiftUI
import PencilKit
import FirebaseCore
import FirebaseFirestore
import FirebaseAppCheck
import GoogleMobileAds
import AppTrackingTransparency
import AdSupport

// AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        FirebaseApp.configure()
        let providerFactory = DeviceCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        // Request tracking authorization after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.requestTrackingAuthorization()
        }
        return true
    }
    func requestTrackingAuthorization() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                switch status {
                case .authorized:
                    print("Authorized")
                    print(ASIdentifierManager.shared().advertisingIdentifier)
                case .denied:
                    print("Denied")
                case .notDetermined:
                    print("Not Determined")
                case .restricted:
                    print("Restricted")
                @unknown default:
                    print("Unknown")
                }
                // Update UserDefaults to indicate we've requested authorization
                UserDefaults.standard.set(true, forKey: "trackingRequested")
            }
        }
    }
}

// UserDefaultsManager

class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    private let trackingRequestedKey = "trackingRequested"
    var isTrackingRequested: Bool {
        get {
            return UserDefaults.standard.bool(forKey: trackingRequestedKey)
        }
    }
}

// DavidGameApp

@main
struct DavidGameApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// ContentView

struct ContentView: View {
    @StateObject private var gameState = GameState()
    @State private var showingJoinGame = false
    @State private var showingHostGame = false
    @State private var isGameActive = false
    var body: some View {
        VStack {
            Text("The David Game")
                .font(.largeTitle)
                .padding()
            Image("davidgamecircle")
                .resizable()
                .scaledToFit()
                .frame(height: 250)
                .padding()
            Button(action: {
                showingHostGame = true
            }) {
                Text("Host Game")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .sheet(isPresented: $showingHostGame) {
                HostGameView(gameState: gameState)
            }
            Button(action: {
                showingJoinGame = true
            }) {
                Text("Join Game")
                    .font(.title)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .sheet(isPresented: $showingJoinGame) {
                JoinGameView(gameState: gameState)
            }
            .onChange(of: gameState.isGameStarted) { _, newValue in
                isGameActive = newValue
            }
            .onChange(of: gameState.shouldReturnToHome) { _, newValue in
                if newValue {
                    isGameActive = false
                    showingHostGame = false
                    showingJoinGame = false
                    gameState.shouldReturnToHome = false
                }
            }
            BannerView()
                .frame(height: 50)
                .background(Color.gray.opacity(0.2))
        }
    }
}

#Preview {
    ContentView()
}

// BannerView

struct BannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = "ca-app-pub-6149836240028020/1409106664"
        banner.rootViewController = getRootViewController()
        if #available(iOS 17.5, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    banner.load(GADRequest())
                }
            }
        } else {
            banner.load(GADRequest())
        }
        return banner
    }
    func updateUIView(_ uiView: GADBannerView, context: Context) {}
    private func getRootViewController() -> UIViewController? {
        // Get the root view controller from the scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        return window.rootViewController
    }
}

// HostGameView

struct HostGameView: View {
    @ObservedObject var gameState: GameState
    @State private var pin = Int.random(in: 100000...999999)
    @State private var isWaitingRoomPresented = false
    @State private var playerName = ""
    var body: some View {
        VStack {
            Text("Host Game")
                .font(.largeTitle)
                .padding()
            Text("Game PIN: \(String(format: "%06d", pin))")
                .font(.title)
                .padding()
            TextField("Your Name", text: $playerName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.title)
                .padding()
            Button(action: {
                gameState.hostGame(pin: pin, playerName: playerName)
                isWaitingRoomPresented = true
            }) {
                Text("Create Game")
                    .font(.title)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .fullScreenCover(isPresented: $isWaitingRoomPresented) {
            WaitingRoomView(gameState: gameState, playerName: playerName, pin: pin)
        }
    }
}

#Preview {
    HostGameView(gameState: GameState())
}

// JoinGameView

struct JoinGameView: View {
    @ObservedObject var gameState: GameState
    @State private var pin = ""
    @State private var isWaitingRoomPresented = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var playerName = ""
    var body: some View {
        VStack {
            Text("Join Game")
                .font(.largeTitle)
                .padding()
            TextField("Enter Game PIN", text: $pin)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.title)
                .padding()
            TextField("Your Name", text: $playerName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.title)
                .padding()
            Button(action: {
                gameState.joinGame(pin: Int(pin) ?? 0, playerName: playerName) { result in
                    switch result {
                        case 0:
                            // Success: Game joined successfully
                            isWaitingRoomPresented = true
                        case 1:
                            // Failure: Document doesn't exist (wrong pin)
                            showError = true
                            errorMessage = "Invalid PIN."
                        case 2:
                            // Failure: Game is at max capacity
                            showError = true
                            errorMessage = "The game is full."
                        case 3:
                            // Failure: Player with the same name already in the game
                            showError = true
                            errorMessage = "A player with that name is already in the game."
                        default:
                            // Handle any unexpected result codes
                            showError = true
                            errorMessage = "An unknown error occurred."
                    }
                }
            }) {
                Text("Join")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .sheet(isPresented: $isWaitingRoomPresented) {
                WaitingRoomView(gameState: gameState, playerName: playerName, pin: Int(pin) ?? 0)
            }
            .alert(isPresented: $showError) {
                Alert(title: Text("Failed to join game."), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
}

#Preview {
    JoinGameView(gameState: GameState())
}

// WaitingRoomView

struct WaitingRoomView: View {
    @ObservedObject var gameState: GameState
    let playerName: String
    let pin: Int
    var body: some View {
        VStack {
            Text("Waiting Room")
                .font(.largeTitle)
                .padding()
            Text("Game PIN: \(String(format: "%06d", pin))")
                .padding()
            
            List(gameState.players, id: \.self) { player in
                Text(player)
            }
            if playerName == gameState.host && gameState.players.count >= 2 && gameState.players.count <= 10 {
                Button(action: {
                    gameState.startGame()
                }) {
                    Text("Start Game")
                        .font(.title)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
            } else if gameState.players.count < 10 {
                Text("Waiting for more players...")
                    .font(.title2)
                    .padding()
            }
            if gameState.players.count == 10 {
                Text("10 players - Game at capacity.")
                    .font(.title2)
                    .padding()
            }
        }
        .fullScreenCover(isPresented: $gameState.isGameStarted) {
            GameView(gameState: gameState, playerName: playerName)
        }
    }
}

#Preview {
    WaitingRoomView(gameState: GameState(), playerName: "Player 1", pin: 123456)
}

// GameView

struct GameView: View {
    @ObservedObject var gameState: GameState
    let playerName: String
    @State private var inputText = ""
    @State private var currentDrawing: UIImage?
    var body: some View {
        VStack {
            if let task = gameState.currentTasks[playerName] {
                switch task.taskType {
                    case .writeSentence:
                        writeSentenceView(for: playerName, rootPlayer: task.rootPlayer, previousContent: task.previousContent)
                    case .drawPicture:
                        drawPictureView(for: playerName, rootPlayer: task.rootPlayer, previousContent: task.previousContent)
                    default:
                        Text("Waiting for other players...")
                                .font(.title)
                                .padding()
                }
            }
            else {
                Text("Waiting for other players...")
                    .font(.title)
                    .padding()
            }
        }
        .fullScreenCover(isPresented: $gameState.complete) {
            ResultsView(results: gameState.results) {
                gameState.completelyResetGame()
            }
        }
    }
    private func writeSentenceView(for player: String, rootPlayer: String, previousContent: String) -> some View {
        VStack {
            if gameState.results[player]?.count ?? 0 > 0 {
                if let currentPlayerIndex = gameState.players.firstIndex(of: player) {
                    let previousPlayerIndex = (currentPlayerIndex - 1 + gameState.players.count) % gameState.players.count
                    let previousPlayer = gameState.players[previousPlayerIndex]
                    Text("\(previousPlayer)'s drawing:")
                    Image(uiImage: UIImage(data: Data(base64Encoded: previousContent)!)!)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                    Text("Describe this in one sentence!")
                }
            } else  {
                Text("Submit a sentence that can be drawn.")
                    .font(.title)
                    .padding()
            }
            TextField("Enter your sentence", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.title)
                .padding()
            Button(action: {
                gameState.submitTask(for: player, rootPlayer: rootPlayer, task: .writeSentence, content: inputText)
                inputText = ""
            }) {
                Text("Submit")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
    }
    private func drawPictureView(for player: String, rootPlayer: String, previousContent: String) -> some View {
        VStack {
            if let previousContent = gameState.getPreviousContent(for: rootPlayer) {
                if let currentPlayerIndex = gameState.players.firstIndex(of: player) {
                    let previousPlayerIndex = (currentPlayerIndex - 1 + gameState.players.count) % gameState.players.count
                    let previousPlayer = gameState.players[previousPlayerIndex]
                    Text("\(previousPlayer)'s sentence:")
                    Text(previousContent)
                        .font(.title2)
                        .padding()
                    Text("Draw this sentence. No words allowed!")
                }
            }
            DrawingView(currentDrawing: $currentDrawing)
                .frame(height: 300)
                .padding()
                .border(Color.gray, width: 2)
            Button(action: {
                if let drawing = currentDrawing {
                    let drawingData = drawing.jpegData(compressionQuality: 0.8)?.base64EncodedString() ?? ""
                    gameState.submitTask(for: player, rootPlayer: rootPlayer, task: .drawPicture, content: drawingData)
                    currentDrawing = nil
                }
            }) {
                Text("Submit")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
    }
}

// DrawingView

struct DrawingView: UIViewRepresentable {
    @Binding var currentDrawing: UIImage?
    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.tool = PKInkingTool(.pen, color: .gray, width: 10)
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = context.coordinator
        canvasView.isOpaque = true
        return canvasView
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingView
        init(parent: DrawingView) {
            self.parent = parent
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let drawing = canvasView.drawing
            let image = drawing.image(from: drawing.bounds, scale: 1.0)
            parent.currentDrawing = image
        }
    }
}

// ResultsView

struct ResultsView: View {
    var results: [String: [String]]
    @State private var currentPlayerIndex = 0
    @State private var currentElementIndex = 0
    @State private var timerPublisher = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @Environment(\.dismiss) private var dismiss
    var onDismiss: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Game Results")
                    .font(.largeTitle)
                    .padding()
                if currentPlayerIndex < results.keys.sorted().count {
                    let player = results.keys.sorted()[currentPlayerIndex]
                    VStack(alignment: .center, spacing: 10) {
                        if currentElementIndex == -1 {
                            endGameView
                        } else {
                            playerStoryView(player: player)
                        }
                    }
                    .preferredColorScheme(.light)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(radius: 5)
                }
            }
            .padding()
        }
        .onReceive(timerPublisher) { _ in
            nextElement()
        }
        .onDisappear {
            timerPublisher.upstream.connect().cancel()
        }
    }
    private var endGameView: some View {
        VStack {
            Text("Thanks for playing!")
                .font(.title)
                .padding()
            Image("davidgamecircle")
                .resizable()
                .scaledToFit()
                .frame(height: 250)
                .padding()
            Button(action: {
                onDismiss()
                dismiss()
            }) {
                Text("Return to Home")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
    }
    private func playerStoryView(player: String) -> some View {
        VStack {
            Text("\(player)'s Story")
                .font(.title2)
                .padding(.horizontal)
            ForEach(0...currentElementIndex, id: \.self) { index in
                if index % 2 == 0 {
                    Text(results[player]![index])
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                } else {
                    imageView(for: results[player]![index])
                }
            }
        }
    }
    private func imageView(for base64String: String) -> some View {
        Group {
            if let imageData = Data(base64Encoded: base64String), let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(10)
            } else {
                Text("Unable to load image")
                    .padding()
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(10)
            }
        }
    }
    private func nextElement() {
        if currentElementIndex < (results[results.keys.sorted()[currentPlayerIndex]]?.count ?? 0) - 1 {
            currentElementIndex += 1
        } else {
            currentElementIndex = 0
            if currentPlayerIndex < results.keys.sorted().count - 1 {
                currentPlayerIndex += 1
            } else {
                timerPublisher.upstream.connect().cancel()
                currentElementIndex = -1
            }
        }
    }
}

// GameState

class GameState: ObservableObject {
    @Published var players: [String] = []
    @Published var isGameStarted = false
    @Published var currentTasks: [String: Task] = [:]
    @Published var results: [String: [String]] = [:]
    @Published var todoTasks: [String: [Task]] = [:]
    @Published var waitingForInput: [String: Bool] = [:]
    @Published var host: String = ""
    @Published var gamePIN: Int?
    @Published var complete = false
    @Published var shouldReturnToHome = false
    private var db = Firestore.firestore()
    private var gameDocRef: DocumentReference?
    private var listener: ListenerRegistration?
    enum GameTask: String, Codable {
        case writeSentence
        case drawPicture
        case waiting
    }
    struct Task: Codable {
        let taskType: GameTask
        let rootPlayer: String
        let previousContent: String
    }
    func hostGame(pin: Int, playerName: String) {
        let updatedGamePIN = pin
        let updatedHost = playerName
        let initialGameState: [String: Any] = [
            "gamePIN": updatedGamePIN,
            "players": [updatedHost],
            "isGameStarted": false,
            "currentTasks": [updatedHost: ["taskType": GameTask.writeSentence.rawValue, "rootPlayer": updatedHost, "previousContent": ""]],
            "results": [updatedHost: []],
            "todoTasks": [updatedHost: []],
            "waitingForInput": [updatedHost: false],
            "hostPlayer": updatedHost,
            "complete": false,
            "shouldReturnToHome": false
        ]
        self.gameDocRef = db.collection("games").document("\(pin)")
        self.gameDocRef?.setData(initialGameState) { [weak self] error in
            guard self != nil else { return }
            if let error = error {
                print("Error setting data: \(error)")
            }
        }
        self.listenForChanges()
    }
    func joinGame(pin: Int, playerName: String, completion: @escaping (Int) -> Void) {
        self.gameDocRef = db.collection("games").document("\(pin)")
        self.gameDocRef?.getDocument { [weak self] (document, error) in
            guard let self = self, let document = document, document.exists else {
                completion(1)
                return
            }
            if let players = document.data()?["players"] as? [String] {
                // Check if the game is at max capacity
                if players.count >= 10 {
                    completion(2)  // Game is at max capacity
                    return
                }
                // Check if a player with the same name is already in the game
                if players.contains(playerName) {
                    completion(3)  // Player with the same name already exists
                    return
                }
            }
            let updateData: [String: Any] = [
                "players": FieldValue.arrayUnion([playerName]),
                "currentTasks.\(playerName)": ["taskType": GameTask.writeSentence.rawValue, "rootPlayer": playerName, "previousContent": ""],
                "results.\(playerName)": [],
                "todoTasks.\(playerName)": [],
                "waitingForInput.\(playerName)": false
            ]
            self.gameDocRef?.updateData(updateData) { error in
                if let error = error {
                    print("Error updating data: \(error)")
                    completion(1)
                } else {
                    completion(0)
                }
            }
        }
        self.listenForChanges()
    }
    func startGame() {
        // shuffle the players to randomize the order
        var updatedPlayers = self.players
        updatedPlayers.shuffle()
        self.gameDocRef?.updateData([
            "players": updatedPlayers,
            "isGameStarted": true
        ]) { error in
            if let error = error {
                print("Error updating data: \(error)")
            }
        }
    }
    func submitTask(for player: String, rootPlayer: String, task: GameTask, content: String) {
        var updatedCurrentTasks = self.currentTasks
        var updatedResults = self.results
        var updatedTodoTasks = self.todoTasks
        var updatedWaitingForInput = self.waitingForInput
        var updatedComplete = self.complete
        // update results
        updatedResults[rootPlayer]?.append(content)
        // if results[rootPlayer] is not done, relay the next task
        if updatedResults[rootPlayer]?.count ?? 0 < 7 {
            let nextTask: GameTask = (task == .writeSentence) ? .drawPicture : .writeSentence
            // if nextPlayer is waiting, set nextTask as his current task
            let nextPlayerIndex = (players.firstIndex(of: player)! + 1) % players.count
            if waitingForInput[players[nextPlayerIndex]] == true {
                updatedCurrentTasks[players[nextPlayerIndex]] = Task(taskType: nextTask, rootPlayer: rootPlayer, previousContent: content)
                updatedWaitingForInput[players[nextPlayerIndex]] = false
            }
            // otherwise, add it to their todo
            else {
                updatedTodoTasks[players[nextPlayerIndex]]?.append(Task(taskType: nextTask, rootPlayer: rootPlayer, previousContent: content))
            }
        }
        // if results[rootPlayer] is done, the next task should be "waiting"
        else {
            let nextTask: GameTask = .waiting
            // if nextPlayer is waiting, set nextTask as his current task
            let nextPlayerIndex = (players.firstIndex(of: player)! + 1) % players.count
            if waitingForInput[players[nextPlayerIndex]] == true {
                updatedCurrentTasks[players[nextPlayerIndex]] = Task(taskType: nextTask, rootPlayer: "", previousContent: "")
            }
            // otherwise, add it to their todo
            else {
                updatedTodoTasks[players[nextPlayerIndex]]?.append(Task(taskType: nextTask, rootPlayer: "", previousContent: ""))
            }
        }
        // update player's todo
        // if there is something to do, update player's current task
        if !(updatedTodoTasks[player]?.isEmpty ?? true) {
            updatedCurrentTasks[player] = updatedTodoTasks[player]?.removeFirst()
        }
        // otherwise, set player's current task to waiting and update waitingForInput
        else {
            updatedCurrentTasks[player] = Task(taskType: .waiting, rootPlayer: "", previousContent: "")
            updatedWaitingForInput[player] = true
        }
        // if the game is over, indicate that
        updatedComplete = updatedResults.values.allSatisfy { $0.count == 7 }
        // update database
        let updateData: [String: Any] = [
            "results": updatedResults.mapValues { $0 },
            "currentTasks": updatedCurrentTasks.mapValues { ["taskType": $0.taskType.rawValue, "rootPlayer": $0.rootPlayer, "previousContent": $0.previousContent] },
            "todoTasks": updatedTodoTasks.mapValues { $0.map { ["taskType": $0.taskType.rawValue, "rootPlayer": $0.rootPlayer, "previousContent": $0.previousContent] } },
            "waitingForInput": updatedWaitingForInput,
            "complete": updatedComplete
        ]
        self.gameDocRef?.updateData(updateData) { error in
            if let error = error {
                print("Error updating data: \(error)")
            }
        }
    }
    func getPreviousContent(for rootPlayer: String) -> String? {
        return results[rootPlayer]?.last
    }
    private func listenForChanges() {
        listener?.remove()
        listener = gameDocRef?.addSnapshotListener { [weak self] documentSnapshot, error in
            guard let self = self, let document = documentSnapshot else {
                print("Error fetching document: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            DispatchQueue.main.async {
                self.updateLocalState(with: document)
            }
        }
    }
    private func updateLocalState(with document: DocumentSnapshot) {
        self.complete = document.get("complete") as? Bool ?? false
        self.players = document.get("players") as? [String] ?? []
        self.isGameStarted = document.get("isGameStarted") as? Bool ?? false
        self.currentTasks = (document.get("currentTasks") as? [String: [String: Any]] ?? [:]).compactMapValues(self.decodeTask)
        self.results = document.get("results") as? [String: [String]] ?? [:]
        self.todoTasks = (document.get("todoTasks") as? [String: [[String: Any]]] ?? [:]).mapValues { $0.compactMap { taskDict in
            guard let taskTypeString = taskDict["taskType"] as? String,
                  let taskType = GameTask(rawValue: taskTypeString),
                  let rootPlayer = taskDict["rootPlayer"] as? String,
                  let previousContent = taskDict["previousContent"] as? String else {
                return nil
            }
            return Task(taskType: taskType, rootPlayer: rootPlayer, previousContent: previousContent)
        }}
        self.waitingForInput = document.get("waitingForInput") as? [String: Bool] ?? [:]
        self.host = document.get("hostPlayer") as? String ?? ""
        self.objectWillChange.send()
    }
    private func decodeTask(from dictionary: [String: Any]) -> Task? {
        guard let taskTypeString = dictionary["taskType"] as? String,
              let taskType = GameTask(rawValue: taskTypeString),
              let rootPlayer = dictionary["rootPlayer"] as? String,
              let previousContent = dictionary["previousContent"] as? String else {
            return nil
        }
        return Task(taskType: taskType, rootPlayer: rootPlayer, previousContent: previousContent)
    }
    deinit {
        listener?.remove()
    }
    func completelyResetGame() {
        self.players = []
        self.isGameStarted = false
        self.currentTasks = [:]
        self.results = [:]
        self.todoTasks = [:]
        self.waitingForInput = [:]
        self.host = ""
        self.complete = false
        self.gamePIN = nil
        self.gameDocRef = nil
        self.listener?.remove()
        self.listener = nil
        self.shouldReturnToHome = true
    }
}
