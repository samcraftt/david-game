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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
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

// BannerView

struct BannerView: UIViewRepresentable {
    @Binding var adLoaded: Bool
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView()
        banner.adUnitID = "ca-app-pub-3940256099942544/2435281174"
        banner.rootViewController = getRootViewController()
        banner.delegate = context.coordinator
        return banner
    }
    func updateUIView(_ bannerView: GADBannerView, context: Context) {
        let frame = { () -> CGRect in
            if let window = getRootViewController()?.view.window {
                return window.frame
            } else {
                return UIScreen.main.bounds
            }
        }()
        let viewWidth = frame.size.width
        // Adaptive banner size
        bannerView.adSize = GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(viewWidth)
        loadAd(for: bannerView)
    }
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    private func loadAd(for bannerView: GADBannerView) {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    let request = GADRequest()
                    // General ads if tracking is not authorized
                    if status != .authorized {
                        let extras = GADExtras()
                        extras.additionalParameters = ["npa": "1"]
                        request.register(extras)
                    }
                    bannerView.load(request)
                }
            }
        } else {
            let request = GADRequest()
            bannerView.load(request)
        }
    }
    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        return window.rootViewController
    }
    class Coordinator: NSObject, GADBannerViewDelegate {
        var parent: BannerView
        init(_ parent: BannerView) {
            self.parent = parent
        }
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            parent.adLoaded = true
        }
        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            print("Failed to load ad: \(error)")
            parent.adLoaded = false
        }
    }
}

// DavidGameApp

@main
struct DavidGameApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            ParentView()
        }
    }
}

// ViewManager

class ViewManager: ObservableObject {
    @Published var currentView: GameView = .home
    @Published var playerName: String = ""
    @Published var pin: Int = 0
    @Published var resultsCopy: [String: [String]] = [:]
    @Published var playersCopy: [String] = []
    @Published var anyInactive: Bool = false
    enum GameView {
        case home
        case host
        case join
        case waitingRoom
        case game
        case results
    }
    func moveToView(_ view: GameView) {
        currentView = view
    }
    func resetGame() {
        currentView = .home
        playerName = ""
        pin = 0
        resultsCopy = [:]
        playersCopy = []
        anyInactive = false
    }
}

// ParentView

struct ParentView: View {
    @StateObject private var viewManager = ViewManager()
    @StateObject private var gameState = GameState()
    var body: some View {
        switch viewManager.currentView {
        case .home:
            HomeView(gameState: gameState)
                .environmentObject(viewManager)
        case .host:
            HostGameView(gameState: gameState)
                .environmentObject(viewManager)
        case .join:
            JoinGameView(gameState: gameState)
                .environmentObject(viewManager)
        case .waitingRoom:
            WaitingRoomView(gameState: gameState)
                .environmentObject(viewManager)
        case .game:
            GameView(gameState: gameState)
                .environmentObject(viewManager)
        case .results:
            ResultsView(gameState: gameState)
                .environmentObject(viewManager)
        }
    }
}

// HomeView

struct HomeView: View {
    @EnvironmentObject var viewManager: ViewManager
    @ObservedObject var gameState: GameState
    @State private var adLoaded = false
    var body: some View {
        VStack {
            Text("")
            Spacer()
            Text("The David Game")
                .font(.largeTitle)
                .padding()
            Image("davidgamecircle")
                .resizable()
                .scaledToFit()
                .frame(height: 250)
                .padding()
            Button(action: {
                viewManager.moveToView(.host)
            }) {
                Text("Host Game")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            Button(action: {
                viewManager.moveToView(.join)
            }) {
                Text("Join Game")
                    .font(.title)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            Spacer()
            Text("For smooth gameplay, all players should update the David Game to its latest version on the App Store.")
                .padding()
            BannerView(adLoaded: $adLoaded)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.gray.opacity(0.2))
                .opacity(adLoaded ? 1 : 0)
        }
    }
}

// HostGameView

struct HostGameView: View {
    @EnvironmentObject var viewManager: ViewManager
    @ObservedObject var gameState: GameState
    @State private var pin = Int.random(in: 1000...9999)
    @State private var playerName = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isButtonDisabled = false
    var body: some View {
        VStack {
            Button(action: {
                viewManager.moveToView(.home)
            }) {
                Text("Return to Home")
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            Spacer()
            Text("Host Game")
                .font(.largeTitle)
                .padding()
            Text("Game PIN: \(String(format: "%04d", pin))")
                .font(.title)
                .padding()
            TextField("Your Name", text: $playerName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.title)
                .padding()
            Spacer()
            Button(action: {
                isButtonDisabled = true
                gameState.hostGame(pin: pin, playerName: playerName) { result in
                    if result == 0 {
                        viewManager.playerName = playerName
                        viewManager.pin = pin
                        viewManager.moveToView(.waitingRoom)
                    } else {
                        showError(message: "An unknown error occurred.")
                    }
                }
                isButtonDisabled = false
            }) {
                Text("Create Waiting Room")
                    .font(.title)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .disabled(isButtonDisabled)
            .alert(isPresented: $showError) {
                Alert(title: Text("Failed to host game."), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

// JoinGameView

struct JoinGameView: View {
    @EnvironmentObject var viewManager: ViewManager
    @ObservedObject var gameState: GameState
    @State private var pin = ""
    @State private var playerName = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isButtonDisabled = false
    var body: some View {
        VStack {
            Button(action: {
                viewManager.moveToView(.home)
            }) {
                Text("Return to Home")
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            Spacer()
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
            Spacer()
            Button(action: {
                isButtonDisabled = true
                gameState.joinGame(pin: Int(pin) ?? 0, playerName: playerName) { result in
                    switch result {
                    case 0:
                        viewManager.playerName = playerName
                        viewManager.pin = Int(pin) ?? 0
                        viewManager.moveToView(.waitingRoom)
                    case 1:
                        showError(message: "Invalid PIN.")
                    case 2:
                        showError(message: "The game is full.")
                    case 3:
                        showError(message: "A player with that name is already in the game.")
                    case 4:
                        showError(message: "Game in progress.")
                    default:
                        showError(message: "An unknown error occurred.")
                    }
                }
                isButtonDisabled = false
            }) {
                Text("Join")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .disabled(isButtonDisabled)
            .alert(isPresented: $showError) {
                Alert(title: Text("Failed to join game."), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}

// WaitingRoomView

struct WaitingRoomView: View {
    @EnvironmentObject var viewManager: ViewManager
    @ObservedObject var gameState: GameState
    @State private var isButtonDisabled = false
    @State private var showCancelAlert = false
    @State private var showLeaveAlert = false
    var body: some View {
        VStack {
            Text("Waiting Room")
                .font(.largeTitle)
                .padding()
            Text("Game PIN: \(String(format: "%04d", viewManager.pin))")
                .padding()
            List(gameState.players, id: \.self) { player in
                Text(player)
            }
            if viewManager.playerName == gameState.host && gameState.players.count >= 2 && gameState.players.count <= 15 {
                Button(action: {
                    isButtonDisabled = true
                    gameState.startGame()
                }) {
                    Text("Start Game")
                        .font(.title)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                .disabled(isButtonDisabled)
            } else if gameState.players.count < 15 {
                Text("Waiting for more players...")
                    .font(.title2)
                    .padding()
            }
            if gameState.players.count == 15 {
                Text("15 Players - Game at capacity.")
                    .font(.title2)
                    .padding()
            }
            if viewManager.playerName == gameState.host {
                Button(action: {
                    showCancelAlert = true
                }) {
                    Text("Cancel Game")
                        .font(.title)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                .alert(isPresented: $showCancelAlert) {
                    Alert(
                        title: Text("Cancel Game"),
                        message: Text("Are you sure you want to cancel the game? This will send all players back to the home screen."),
                        primaryButton: .destructive(Text("Cancel Game")) {
                            gameState.cancelGame()
                        },
                        secondaryButton: .cancel(Text("Back to Game"))
                    )
                }
            } else {
                Button(action: {
                    showLeaveAlert = true
                }) {
                    Text("Leave Game")
                        .font(.title)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                .alert(isPresented: $showLeaveAlert) {
                    Alert(
                        title: Text("Leave Game"),
                        message: Text("Are you sure you want to leave the game?"),
                        primaryButton: .destructive(Text("Leave Game")) {
                            gameState.leaveGame(playerName: viewManager.playerName)
                            viewManager.resetGame()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                gameState.completelyResetGame()
                            }
                        },
                        secondaryButton: .cancel(Text("Back to Game"))
                    )
                }
            }
        }
        .onReceive(gameState.$isGameStarted) { started in
            if started {
                viewManager.moveToView(.game)
            }
        }
        .onReceive(gameState.$cancelled) { cancelled in
            if cancelled {
                viewManager.resetGame()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    gameState.completelyResetGame()
                }
            }
        }
    }
}

// GameView

struct GameView: View {
    @EnvironmentObject var viewManager: ViewManager
    @ObservedObject var gameState: GameState
    @State private var inputText = ""
    @State private var currentDrawing: UIImage?
    @State private var canvasView = PKCanvasView()
    @State private var isButtonDisabled = false
    var body: some View {
        VStack {
            if let task = gameState.currentTasks[viewManager.playerName] {
                switch task.taskType {
                    case .writeSentence:
                    writeSentenceView(for: viewManager.playerName, rootPlayer: task.rootPlayer, previousContent: task.previousContent)
                    case .drawPicture:
                    drawPictureView(for: viewManager.playerName, rootPlayer: task.rootPlayer, previousContent: task.previousContent)
                    default:
                    if let currentPlayerIndex = gameState.players.firstIndex(of: viewManager.playerName) {
                        let previousPlayerIndex = (currentPlayerIndex - 1 + gameState.players.count) % gameState.players.count
                        let previousPlayer = gameState.players[previousPlayerIndex]
                        if gameState.currentTasks[previousPlayer]?.taskType != .waiting {
                            Text("Waiting for \(previousPlayer) to complete their task...")
                                .font(.title)
                                .padding()
                        } else {
                            Text("Waiting for other players...")
                                .font(.title)
                                .padding()
                            Text("Don't tell \(previousPlayer) to hurry up, because they're also waiting...")
                                .padding()
                            }
                        }
                }
            } else {
                Text("Waiting for other players...")
                    .font(.title)
                    .padding()
            }
        }
        .onReceive(gameState.$complete) { complete in
            if complete {
                if gameState.listener != nil {
                    gameState.removeListener()
                }
                viewManager.resultsCopy = gameState.results
                viewManager.playersCopy = gameState.players
                viewManager.anyInactive = gameState.anyInactive
                gameState.stopInactivityCheck()
                viewManager.moveToView(.results)
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    self.gameState.deleteGameReference()
                }
            }
        }
    }
    private func writeSentenceView(for player: String, rootPlayer: String, previousContent: String) -> some View {
        VStack {
            if gameState.results[rootPlayer]?.count ?? 0 > 0 {
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
                Text("Submit a sentence that the next person can draw.")
                    .font(.title)
                    .padding()
            }
            TextField("Enter your sentence", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.title)
                .padding()
            if let currentPlayerIndex = gameState.players.firstIndex(of: player) {
                let nextPlayerIndex = (currentPlayerIndex + 1) % gameState.players.count
                let nextPlayer = gameState.players[nextPlayerIndex]
                if gameState.results[rootPlayer]?.count == 6 {
                    Text("Submit this sentence to complete \(rootPlayer)'s story!")
                } else {
                    Text("Pass your sentence to \(nextPlayer)!")
                }
            }
            Button(action: {
                isButtonDisabled = true
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
            .disabled(isButtonDisabled)
        }
        .onAppear {
            isButtonDisabled = false
        }
    }
    private func drawPictureView(for player: String, rootPlayer: String, previousContent: String) -> some View {
        VStack {
            if let previousContent = gameState.getPreviousContent(for: rootPlayer) {
                if let currentPlayerIndex = gameState.players.firstIndex(of: player) {
                    let previousPlayerIndex = (currentPlayerIndex - 1 + gameState.players.count) % gameState.players.count
                    let previousPlayer = gameState.players[previousPlayerIndex]
                    Text("\(previousPlayer)'s sentence:")
                    ScrollView {
                        Text(previousContent)
                            .font(.title2)
                            .padding()
                    }
                    .frame(height: 100)
                    Text("Draw this sentence. No words allowed!")
                }
            }
            let drawingView = DrawingView(currentDrawing: $currentDrawing, canvasView: canvasView)
            drawingView
                .frame(height: 300)
                .padding()
                .border(Color.gray, width: 2)
            HStack {
                Button(action: {
                    drawingView.undo()
                }) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Undo")
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                Spacer()
                Button(action: {
                    isButtonDisabled = true
                    if let drawing = currentDrawing {
                        let drawingData = drawing.jpegData(compressionQuality: 0.8)?.base64EncodedString() ?? ""
                        gameState.submitTask(for: player, rootPlayer: rootPlayer, task: .drawPicture, content: drawingData)
                        canvasView.drawing = PKDrawing()
                    }
                }) {
                    Text("Submit")
                        .font(.title)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding()
            .disabled(isButtonDisabled)
            if let currentPlayerIndex = gameState.players.firstIndex(of: player) {
                let nextPlayerIndex = (currentPlayerIndex + 1) % gameState.players.count
                let nextPlayer = gameState.players[nextPlayerIndex]
                Text("Pass your drawing to \(nextPlayer)!")
            }
        }
        .onAppear {
            isButtonDisabled = false
        }
    }
}

// DrawingView

struct DrawingView: UIViewRepresentable {
    @Binding var currentDrawing: UIImage?
    let canvasView: PKCanvasView
    init(currentDrawing: Binding<UIImage?>, canvasView: PKCanvasView) {
        self._currentDrawing = currentDrawing
        self.canvasView = canvasView
    }
    func makeUIView(context: Context) -> PKCanvasView {
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
    func undo() {
        if canvasView.undoManager?.canUndo ?? false {
            canvasView.undoManager?.undo()
        }
    }
}

// ResultsView

struct ResultsView: View {
    @EnvironmentObject var viewManager: ViewManager
    @ObservedObject var gameState: GameState
    @State private var currentPlayerIndex = 0
    @State private var currentElementIndex = 0
    @State private var revealedElements: [String: [String]] = [:]
    @State private var isGameEnded = false
    @State private var timerPublisher = Timer.publish(every: 6, on: .main, in: .common).autoconnect()
    @State private var isButtonDisabled = false
    @State private var scrollProxy: ScrollViewProxy?
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    Text("The results are in...")
                        .font(.largeTitle)
                        .padding()
                    ForEach(viewManager.resultsCopy.keys.sorted(), id: \.self) { player in
                        if revealedElements[player] != nil {
                            playerStoryView(player: player)
                        }
                    }
                    if isGameEnded {
                        endGameView
                        Color.clear.frame(height: 1).id("bottomID")
                    } else {
                        ThreeDotsAnimation()
                            .id("bottomID")
                            .frame(height: 40)
                            .padding(.bottom)

                    }
                }
                .padding()
            }
            .onChange(of: revealedElements) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottomID", anchor: .bottom)
                }
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: isGameEnded) {
                withAnimation {
                    proxy.scrollTo("bottomID", anchor: .bottom)
                }
            }
        }
        .onReceive(timerPublisher) { _ in
            nextElement()
        }
        .onDisappear {
            timerPublisher.upstream.connect().cancel()
        }
    }
    private func playerStoryView(player: String) -> some View {
        VStack {
            Text("\(player)'s Story")
                .font(.title2)
                .padding(.horizontal)
            let playerIndex = viewManager.playersCopy.firstIndex(of: player)
            ForEach(0..<(revealedElements[player]?.count ?? 0), id: \.self) { index in
                if index % 2 == 0 {
                    storyTextView(playerIndex: playerIndex ?? 0, index: index, player: player)
                } else {
                    storyImageView(playerIndex: playerIndex ?? 0, index: index, player: player)
                }
            }
        }
        .preferredColorScheme(.light)
        .padding()
        .background(Color.white)
        .cornerRadius(15)
        .shadow(radius: 5)
    }
    private func storyTextView(playerIndex: Int, index: Int, player: String) -> some View {
        VStack {
            if !(viewManager.anyInactive) {
                let adjustedIndex = (playerIndex + index) % viewManager.playersCopy.count
                Text("\(viewManager.playersCopy[adjustedIndex]):")
                    .padding()
            }
            Text(revealedElements[player]![index])
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
        }
    }
    private func storyImageView(playerIndex: Int, index: Int, player: String) -> some View {
        VStack {
            if !(viewManager.anyInactive) {
                let adjustedIndex = (playerIndex + index) % viewManager.playersCopy.count
                Text("\(viewManager.playersCopy[adjustedIndex]):")
                    .padding()
            }
            imageView(for: revealedElements[player]![index])
        }
    }
    private var endGameView: some View {
        VStack {
            Button(action: {
                isButtonDisabled = true
                gameState.completelyResetGame()
                gameState.hostGame(pin: viewManager.pin, playerName: viewManager.playerName) { result in
                    switch result {
                    case 0:
                        viewManager.moveToView(.waitingRoom)
                    default:
                        gameState.joinGame(pin: viewManager.pin, playerName: viewManager.playerName) { result in
                            switch result {
                            case 0:
                                viewManager.moveToView(.waitingRoom)
                            default:
                                viewManager.resetGame()
                            }
                        }
                    }
                }
            }) {
                Text("Play Again")
                    .font(.title)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            .disabled(isButtonDisabled)
            Button(action: {
                gameState.completelyResetGame()
                viewManager.resetGame()
            }) {
                Text("Return to Home")
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            Image("davidgamecircle")
                .resizable()
                .scaledToFit()
                .frame(height: 250)
                .padding()
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
        let currentPlayer = viewManager.resultsCopy.keys.sorted()[currentPlayerIndex]
        let playerResults = viewManager.resultsCopy[currentPlayer] ?? []
        if currentElementIndex < playerResults.count {
            if revealedElements[currentPlayer] == nil {
                revealedElements[currentPlayer] = []
            }
            revealedElements[currentPlayer]!.append(playerResults[currentElementIndex])
            currentElementIndex += 1
            // Scroll to bottom after adding new element
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    scrollProxy?.scrollTo("bottomID", anchor: .bottom)
                }
            }
        } else {
            currentElementIndex = 0
            if currentPlayerIndex < viewManager.resultsCopy.keys.sorted().count - 1 {
                currentPlayerIndex += 1
                nextElement()
            } else {
                timerPublisher.upstream.connect().cancel()
                isGameEnded = true
            }
        }
    }
}

// ThreeDotsAnimation

struct ThreeDotsAnimation: View {
    @State private var animationState = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .opacity(animationState == index ? 1 : 0.3)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                withAnimation {
                    animationState = (animationState + 1) % 3
                }
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
    @Published var listener: ListenerRegistration?
    @Published var lastActiveTimestamps: [String: Timestamp] = [:]
    @Published var anyInactive: Bool = false
    @Published var cancelled: Bool = false
    private var inactivityCheckTimer: Timer?
    private let inactivityThreshold: TimeInterval = 300 // 5 minutes
    private var db = Firestore.firestore()
    private var gameDocRef: DocumentReference?
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
    func hostGame(pin: Int, playerName: String, completion: @escaping (Int) -> Void) {
        self.gameDocRef = db.collection("games").document("\(pin)")
        self.gameDocRef?.getDocument { [weak self] (document, error) in
            guard let self = self else { return }
            if let document = document, document.exists {
                completion(1)
                return
            }
            let initialGameState: [String: Any] = [
                "gamePIN": pin,
                "players": [playerName],
                "isGameStarted": false,
                "currentTasks": [playerName: ["taskType": GameTask.writeSentence.rawValue, "rootPlayer": playerName, "previousContent": ""]],
                "results": [playerName: []],
                "todoTasks": [playerName: []],
                "waitingForInput": [playerName: false],
                "hostPlayer": playerName,
                "complete": false,
                "lastActiveTimestamps": [playerName: Timestamp()],
                "anyInactive": false,
                "cancelled": false,
            ]
            self.gameDocRef?.setData(initialGameState) { error in
                if error != nil {
                    completion(1)  // Error creating game
                } else {
                    self.listenForChanges()
                    completion(0)  // Game successfully created
                }
            }
        }
    }
    func joinGame(pin: Int, playerName: String, completion: @escaping (Int) -> Void) {
        self.gameDocRef = db.collection("games").document("\(pin)")
        self.gameDocRef?.getDocument { [weak self] (document, error) in
            guard let self = self, let document = document, document.exists else {
                completion(1) // Game doesn't exist
                return
            }
            if let players = document.data()?["players"] as? [String] {
                if players.count >= 15 {
                    completion(2)  // Game is at max capacity
                    return
                }
                if players.contains(playerName) {
                    completion(3)  // Player with the same name already exists
                    return
                }
            }
            if let inProgress = document.data()?["isGameStarted"] as? Bool, inProgress {
                completion(4) // Game is in progress
                return
            }
            let updateData: [String: Any] = [
                "players": FieldValue.arrayUnion([playerName]),
                "currentTasks.\(playerName)": ["taskType": GameTask.writeSentence.rawValue, "rootPlayer": playerName, "previousContent": ""],
                "results.\(playerName)": [],
                "todoTasks.\(playerName)": [],
                "waitingForInput.\(playerName)": false,
                "lastActiveTimestamps.\(playerName)": Timestamp()
            ]
            self.gameDocRef?.updateData(updateData) { error in
                if error != nil {
                    completion(1)
                } else {
                    completion(0)
                }
            }
        }
        self.listenForChanges()
    }
    func startGame() {
        var updatedPlayers = self.players
        updatedPlayers.shuffle() // Shuffle the order
        self.gameDocRef?.updateData([
            "players": updatedPlayers,
            "isGameStarted": true
        ])
        self.players.forEach { player in
            updateUserActivity(for: player)
        }
        self.startInactivityCheck()
    }
    func submitTask(for player: String, rootPlayer: String, task: GameTask, content: String) {
        updateUserActivity(for: player)
        guard let gameDocRef = self.gameDocRef else {
            return
        }
        db.runTransaction({ [self] (transaction, errorPointer) -> Any? in
            do {
                let gameDoc = try transaction.getDocument(gameDocRef)
                // Read current state
                guard var updatedCurrentTasks = gameDoc.data()?["currentTasks"] as? [String: [String: Any]],
                      var updatedResults = gameDoc.data()?["results"] as? [String: [String]],
                      var updatedTodoTasks = gameDoc.data()?["todoTasks"] as? [String: [[String: Any]]],
                      var updatedWaitingForInput = gameDoc.data()?["waitingForInput"] as? [String: Bool],
                      var updatedComplete = gameDoc.data()?["complete"] as? Bool else {
                    throw NSError(domain: "GameStateError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid game state"])
                }
                let nextPlayerIndex = (self.players.firstIndex(of: player)! + 1) % players.count
                // update results
                updatedResults[rootPlayer]?.append(content)
                // if results[rootPlayer] is not done, relay the next task
                if updatedResults[rootPlayer]?.count ?? 0 < 7 {
                    let nextTask: GameTask = (task == .writeSentence) ? .drawPicture : .writeSentence
                    let nextTaskDict: [String: Any] = ["taskType": nextTask.rawValue, "rootPlayer": rootPlayer, "previousContent": content]
                    // if nextPlayer is waiting, set nextTask as his current task
                    if waitingForInput[players[nextPlayerIndex]] == true {
                        updatedCurrentTasks[players[nextPlayerIndex]] = nextTaskDict
                        updatedWaitingForInput[players[nextPlayerIndex]] = false
                    }
                    // otherwise, add it to their todo
                    else {
                        updatedTodoTasks[players[nextPlayerIndex]]?.append(nextTaskDict)
                    }
                }
                // update player's todo
                // if there is something to do, update player's current task
                if !(updatedTodoTasks[player]?.isEmpty ?? true) {
                    updatedCurrentTasks[player] = updatedTodoTasks[player]?.removeFirst()
                }
                // otherwise, set player's current task to waiting and update waitingForInput
                else {
                    updatedCurrentTasks[player] = ["taskType": GameTask.waiting.rawValue, "rootPlayer": "", "previousContent": ""]
                    updatedWaitingForInput[player] = true
                }
                // if the game is over, indicate that
                updatedComplete = updatedResults.values.allSatisfy { $0.count == 7 }
                // Update document
                transaction.updateData([
                    "results": updatedResults,
                    "currentTasks": updatedCurrentTasks,
                    "todoTasks": updatedTodoTasks,
                    "waitingForInput": updatedWaitingForInput,
                    "complete": updatedComplete
                ], forDocument: gameDocRef)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }) { (_, error) in
            if let error = error {
                print("Transaction failed: \(error)")
            } else {
                print("Transaction successfully committed.")
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
                return
            }
            DispatchQueue.main.async {
                self.updateLocalState(with: document)
            }
        }
    }
    private func updateLocalState(with document: DocumentSnapshot) {
        self.results = document.get("results") as? [String: [String]] ?? [:]
        self.anyInactive = document.get("anyInactive") as? Bool ?? false
        self.complete = document.get("complete") as? Bool ?? false
        self.players = document.get("players") as? [String] ?? []
        self.isGameStarted = document.get("isGameStarted") as? Bool ?? false
        self.currentTasks = (document.get("currentTasks") as? [String: [String: Any]] ?? [:]).compactMapValues(self.decodeTask)
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
        self.lastActiveTimestamps = document.get("lastActiveTimestamps") as? [String: Timestamp] ?? [:]
        self.cancelled = document.get("cancelled") as? Bool ?? false
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
        self.anyInactive = false
        self.lastActiveTimestamps = [:]
        self.anyInactive = false
        self.cancelled = false
        if self.listener != nil {
            removeListener()
        }
    }
    func removeListener() {
        self.listener?.remove()
        self.listener = nil
    }
    func deleteGameReference(){
        if self.listener != nil {
            removeListener()
        }
        self.gameDocRef?.delete { error in
            if let error = error {
                print("Error removing document: \(error)")
            } else {
                print("Document successfully removed.")
            }
        }
    }
    func updateUserActivity(for player: String) {
        var updatedLastActiveTimestamps = self.lastActiveTimestamps
        let currentTimestamp = Timestamp()
        updatedLastActiveTimestamps[player] = currentTimestamp
        gameDocRef?.updateData([
            "lastActiveTimestamps.\(player)": currentTimestamp
        ])
    }
    func startInactivityCheck() {
        inactivityCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkForInactiveUsers()
        }
    }
    func stopInactivityCheck() {
        inactivityCheckTimer?.invalidate()
        inactivityCheckTimer = nil
    }
    private func checkForInactiveUsers() {
        let currentTimestamp = Timestamp()
        for (player, lastActiveTime) in lastActiveTimestamps {
            if currentTasks[player]?.taskType == .waiting {
                updateUserActivity(for: player)
            }
            if currentTimestamp.seconds - lastActiveTime.seconds > Int64(inactivityThreshold) {
                handleInactiveUser(player)
            }
        }
    }
    private func handleInactiveUser(_ inactivePlayer: String) {
        guard let gameDocRef = self.gameDocRef else {
            return
        }
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            do {
                let gameDoc = try transaction.getDocument(gameDocRef)
                // Read current state
                guard var updatedPlayers = gameDoc.data()?["players"] as? [String],
                      var updatedCurrentTasks = gameDoc.data()?["currentTasks"] as? [String: [String: Any]],
                      var updatedTodoTasks = gameDoc.data()?["todoTasks"] as? [String: [[String: Any]]],
                      var updatedWaitingForInput = gameDoc.data()?["waitingForInput"] as? [String: Bool],
                      var updatedResults = gameDoc.data()?["results"] as? [String: [String]],
                      var updatedLastActiveTimestamps = gameDoc.data()?["lastActiveTimestamps"] as? [String: Timestamp],
                      var updatedComplete = gameDoc.data()?["complete"] as? Bool else {
                    throw NSError(domain: "GameStateError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid game state"])
                }
                let inactiveTask = updatedCurrentTasks[inactivePlayer]
                let nextPlayerIndex = ((self.players.firstIndex(of: inactivePlayer) ?? 0) + 1) % self.players.count
                if self.waitingForInput[self.players[nextPlayerIndex]] ?? false {
                    updatedCurrentTasks[self.players[nextPlayerIndex]] = inactiveTask
                    if !self.waitingForInput[inactivePlayer]! {
                        updatedWaitingForInput[self.players[nextPlayerIndex]] = false
                    }
                } else if !self.waitingForInput[inactivePlayer]! {
                    updatedTodoTasks[self.players[nextPlayerIndex]]?.append(inactiveTask!)
                }
                while !(updatedTodoTasks[inactivePlayer]?.isEmpty ?? true) {
                    let fromToDo = updatedTodoTasks[inactivePlayer]?.removeFirst()
                    if updatedWaitingForInput[self.players[nextPlayerIndex]] ?? true {
                        updatedCurrentTasks[self.players[nextPlayerIndex]] = fromToDo
                        updatedWaitingForInput[self.players[nextPlayerIndex]] = false
                    } else {
                        updatedTodoTasks[self.players[nextPlayerIndex]]!.append(fromToDo!)
                    }
                }
                // Remove the inactive player
                updatedPlayers.removeAll { $0 == inactivePlayer }
                updatedCurrentTasks.removeValue(forKey: inactivePlayer)
                updatedResults.removeValue(forKey: inactivePlayer)
                updatedTodoTasks.removeValue(forKey: inactivePlayer)
                updatedWaitingForInput.removeValue(forKey: inactivePlayer)
                updatedLastActiveTimestamps.removeValue(forKey: inactivePlayer)
                updatedComplete = updatedResults.values.allSatisfy { $0.count == 7 }
                // Update document
                transaction.updateData([
                    "players": updatedPlayers,
                    "currentTasks": updatedCurrentTasks,
                    "results": updatedResults,
                    "todoTasks": updatedTodoTasks,
                    "waitingForInput": updatedWaitingForInput,
                    "lastActiveTimestamps": updatedLastActiveTimestamps,
                    "anyInactive": true,
                    "updatedComplete": updatedComplete
                ], forDocument: gameDocRef)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }) { (_, error) in
            if let error = error {
                print("Transaction failed: \(error)")
            } else {
                print("Inactive user \(inactivePlayer) has been removed from the game.")
            }
        }
    }
    func cancelGame() {
        guard let gameDocRef = self.gameDocRef else {
            return
        }
        gameDocRef.updateData(["cancelled": true]) { error in
            if let error = error {
                print("Error updating document: \(error)")
            } else {
                print("Game cancelled successfully")
            }
        }
    }
    func leaveGame(playerName: String) {
        guard let gameDocRef = self.gameDocRef else {
            return
        }
        // Remove the player from the game
        gameDocRef.updateData([
            "players": FieldValue.arrayRemove([playerName]),
            "currentTasks.\(playerName)": FieldValue.delete(),
            "results.\(playerName)": FieldValue.delete(),
            "todoTasks.\(playerName)": FieldValue.delete(),
            "waitingForInput.\(playerName)": FieldValue.delete(),
            "lastActiveTimestamps.\(playerName)": FieldValue.delete()
        ]) { error in
            if let error = error {
                print("Error removing player from game: \(error)")
            } else {
                print("Player \(playerName) has left the game.")
            }
        }
    }
}
