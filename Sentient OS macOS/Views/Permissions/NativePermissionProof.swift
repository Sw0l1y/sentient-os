// A display-only record that the computer-use helper's Accessibility and Screen Recording passed a
// live check (NativePermissionCheck or a passing Test & Repair) for this helper install and this
// Sentient build. It only decides what the helper rows SAY between launches. It never admits a task:
// ComputerUseGate.allRequiredGranted reads the live, in-memory snapshot alone.
// Cleared on a confirmed denial, a helper reinstall or build change (identity mismatch), and by
// ComputerUseDoctor.clear (Factory Reset, Uninstall).
// Scripts/test_native_permission_proof.py compiles this file standalone.
import Foundation
import Observation

nonisolated struct NativePermissionProof: Codable, Equatable, Sendable {
    static let defaultsKey = "computerUse.helperProof.v1"

    /// What was verified. A different helper build, a reinstalled helper (new Info.plist file) or a
    /// different Sentient executable makes the record stale.
    struct Identity: Codable, Equatable, Sendable {
        var helperBuild: String
        var helperInstall: String
        var sentientBuild: String
    }
    enum Source: String, Codable, Sendable { case check, doctor }

    var verifiedAt: Date
    var identity: Identity
    var source: Source

    /// One helper capability row (Accessibility or Screen Recording).
    enum Row: Equatable, Sendable {
        case verified              // the live check passed in this session
        case verifiedEarlier(Date) // a saved proof for this helper install and Sentient build
        case pending               // nothing proven yet; a task start checks it
        case failed                // the last check could not finish (an error, not a denial)
        case denied                // a confirmed denial

        /// The only state that sends the user to System Settings.
        var offersSettingsFix: Bool { self == .denied }
        var isOK: Bool {
            switch self { case .verified, .verifiedEarlier: true; default: false }
        }
        /// Orange or red: only a real denial or error.
        var warns: Bool { self == .denied || self == .failed }
    }

    /// The live snapshot always wins. A saved proof only fills in for "unknown", and only when it
    /// was made for the current identity. A failed check outranks an old proof.
    static func row(live: NativePermissionReadiness.State, proof: NativePermissionProof?,
                    current: Identity, checkFailed: Bool) -> Row {
        switch live {
        case .verified: return .verified
        case .denied: return .denied
        case .unknown:
            if checkFailed { return .failed }
            if let proof, proof.identity == current { return .verifiedEarlier(proof.verifiedAt) }
            return .pending
        }
    }

    static func detail(_ row: Row, now: Date = Date(), locale: Locale = .current) -> String {
        switch row {
        case .verified: return "Verified"
        case .verifiedEarlier(let date): return "Verified " + relative(date, now: now, locale: locale)
        case .pending: return "Checked when a task starts"
        case .failed: return "Couldn’t check"
        case .denied: return "Not allowed"
        }
    }

    static func relative(_ date: Date, now: Date, locale: Locale = .current) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// The saved proof, observable so the helper rows redraw when a check or Test & Repair records one.
@MainActor @Observable final class NativePermissionProofStore {
    static let shared = NativePermissionProofStore(defaults: .standard, current: NativePermissionProof.liveIdentity)

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let current: @MainActor () -> NativePermissionProof.Identity
    /// Only a record for the current identity is ever held.
    private(set) var proof: NativePermissionProof?

    init(defaults: UserDefaults, current: @escaping @MainActor () -> NativePermissionProof.Identity) {
        self.defaults = defaults
        self.current = current
        if let data = defaults.data(forKey: NativePermissionProof.defaultsKey), data.count < 4_096,
           let saved = try? JSONDecoder().decode(NativePermissionProof.self, from: data) {
            proof = saved
        } else if defaults.object(forKey: NativePermissionProof.defaultsKey) != nil {
            defaults.removeObject(forKey: NativePermissionProof.defaultsKey)
        }
        prune()
    }

    func row(live: NativePermissionReadiness.State, checkFailed: Bool) -> NativePermissionProof.Row {
        NativePermissionProof.row(live: live, proof: proof, current: current(), checkFailed: checkFailed)
    }

    /// A successful live check or a passing Test & Repair.
    func record(_ source: NativePermissionProof.Source, at date: Date = Date()) {
        let proof = NativePermissionProof(verifiedAt: date, identity: current(), source: source)
        self.proof = proof
        if let data = try? JSONEncoder().encode(proof) {
            defaults.set(data, forKey: NativePermissionProof.defaultsKey)
        }
    }

    /// Forget a record made for another helper install or Sentient build. Never called from a
    /// view body; passive refreshes call it.
    func prune() {
        guard let proof, proof.identity != current() else { return }
        clear()
    }

    func clear() {
        if proof != nil { proof = nil }
        defaults.removeObject(forKey: NativePermissionProof.defaultsKey)
    }
}

extension NativePermissionProof {
    /// The helper build Sentient ships, the file identity of the installed helper's Info.plist (a
    /// reinstall writes a new file) and this executable's build identity.
    @MainActor static func liveIdentity() -> Identity {
        let plist = OpenAIComputerUse.appURL.appendingPathComponent("Contents/Info.plist").path
        let attributes = try? FileManager.default.attributesOfItem(atPath: plist)
        let install = (attributes?[.systemFileNumber] as? NSNumber).map { "\($0)" } ?? "missing"
        return Identity(helperBuild: String(CodexRuntime.release.helperBuild), helperInstall: install,
                        sentientBuild: BuildIdentity.identifier)
    }
}
