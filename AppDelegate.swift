import AppKit
import Network
import os
import ServiceManagement
import UserNotifications

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FlagSentry", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Settings

    // Why plain HTTP: the free tier of ip-api.com is HTTP-only (HTTPS requires a paid key), and the
    // HTTPS alternatives have daily limits (~1000 requests/day) far below one request per 30 s.
    // The ATS exception in Info.plist is limited to this single domain. Because the response can be
    // spoofed on an untrusted network, ResponseParser validates every field before it is displayed.
    private let endpoint = URL(string: "http://ip-api.com/json/?fields=status,country,countryCode,query")!
    private let debounceDelay: TimeInterval = 0.03      // coalesces bursts of network events
    private let timerInterval: TimeInterval = 30        // periodic check
    private let minRequestGap: TimeInterval = 2         // at most 1 request per 2 s (30/min, limit is 45)
    private let autoLaunchKey = "autoLaunchRegistrationAttempted"

    // MARK: - State

    private var statusItem: NSStatusItem!
    private var ipMenuItem: NSMenuItem!
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "FlagSentry.NWPathMonitor")
    private var timer: Timer?
    private var pendingWork: DispatchWorkItem?
    private var requestTask: Task<Void, Never>?
    private var isRequestInFlight = false
    private var recheckRequested = false
    private var lastRequestStart: Date?
    private var tracker = IPChangeTracker()
    private var autoLaunchError: String?

    // nonisolated so the delegate can be created from the top-level code in main.swift.
    nonisolated override init() { super.init() }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerAutoLaunchOnce()
        updateTooltip()
        requestNotificationPermission()
        startNetworkMonitor()

        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.check() }
        }

        check()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.cancel()
        timer?.invalidate()
        pendingWork?.cancel()
        requestTask?.cancel()
    }

    // MARK: - UI

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "?"

        let menu = NSMenu()
        ipMenuItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
        ipMenuItem.isEnabled = false
        menu.addItem(ipMenuItem)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func refreshAction() { check() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    private func updateTooltip() {
        statusItem.button?.toolTip = autoLaunchError.map { "Launch at login: \($0)" }
    }

    private func showSuccess(_ lookup: IPLookup) {
        let flag = Flag.emoji(for: lookup.countryCode ?? "")
        statusItem.button?.title = flag.isEmpty ? "?" : flag
        ipMenuItem.title = "\(lookup.ip) · \(lookup.country ?? "—")"
    }

    private func showFailure() {
        statusItem.button?.title = "?"
        ipMenuItem.title = "No connection"
    }

    // MARK: - Network

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] _ in
            // The callback arrives on a background queue; hop to the main actor.
            Task { @MainActor in self?.scheduleCheck(after: self?.debounceDelay ?? 0) }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Replaces any pending check with a new one fired after `delay`.
    private func scheduleCheck(after delay: TimeInterval) {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.check() }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Checks the IP. If a request is already running, one more check is queued for when it ends
    /// (so a network change during a request is not lost). A request sooner than `minRequestGap`
    /// after the previous one is postponed for the remaining time instead of being dropped.
    private func check() {
        guard !isRequestInFlight else {
            recheckRequested = true
            return
        }

        let wait = RateLimiter.delay(lastStart: lastRequestStart, now: Date(), minGap: minRequestGap)
        if wait > 0 {
            scheduleCheck(after: wait)
            return
        }

        isRequestInFlight = true
        lastRequestStart = Date()
        requestTask = Task { await performRequest() }
    }

    private func performRequest() async {
        defer {
            isRequestInFlight = false
            if recheckRequested {
                recheckRequested = false
                check()
            }
        }
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let lookup = try ResponseParser.parse(data: data, statusCode: status)
            handleSuccess(lookup)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            // The last known IP is kept, so recovering from an outage does not trigger a false notification.
            log.error("IP lookup failed: \(String(describing: error), privacy: .public)")
            showFailure()
        }
    }

    private func handleSuccess(_ lookup: IPLookup) {
        showSuccess(lookup)
        if let old = tracker.record(lookup.ip) {
            notifyChange(old: old, new: lookup.ip, country: lookup.country)
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                log.notice("Notification permission denied")
            }
        }
    }

    private func notifyChange(old: String, new: String, country: String?) {
        let text = NotificationText.ipChanged(old: old, new: new, country: country)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Launch at login

    /// Registration is attempted until it succeeds once. If the user later disables launch at login
    /// in System Settings, it is not re-enabled.
    private func registerAutoLaunchOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: autoLaunchKey) else { return }

        let service = SMAppService.mainApp
        do {
            if service.status != .enabled {
                try service.register()
            }
            defaults.set(true, forKey: autoLaunchKey)
            if service.status == .requiresApproval {
                autoLaunchError = "approval required in System Settings → General → Login Items"
            }
        } catch {
            // The flag is not set, so registration is retried on the next launch.
            log.error("Launch at login registration failed: \(error.localizedDescription, privacy: .public)")
            autoLaunchError = error.localizedDescription
        }
    }
}
