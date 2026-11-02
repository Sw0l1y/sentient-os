#!/usr/bin/env python3
"""Display-only helper permission proof: row mapping, wording and saved-record lifecycle.
Compiles the production NativePermissionProof.swift with an in-memory UserDefaults and a temporary
helper Info.plist; no app state, real preferences, TCC, helper or window is touched.
"""
from pathlib import Path
import platform
import subprocess
import tempfile
APP=Path(__file__).resolve().parents[1]/'Sentient OS macOS'
SUPPORT=r'''
import Foundation
nonisolated enum OpenAIComputerUseProbe {static func validateResult(_ result:[String:Any],requiresCapture:Bool) throws {}}
nonisolated enum OpenAIComputerUse {nonisolated(unsafe) static var appURL=URL(fileURLWithPath:"/nonexistent-helper.app")}
nonisolated enum CodexRuntime {
    struct Release {var helperBuild:Int}
    nonisolated(unsafe) static var release=Release(helperBuild:1001365)
}
nonisolated enum BuildIdentity {nonisolated(unsafe) static var identifier="build-a"}
/// Shadows the persistent store: every read and write stays in this dictionary.
final class MemoryDefaults: UserDefaults {
    var values:[String:Any]=[:]
    init() {super.init(suiteName:nil)!}
    override func object(forKey key:String) -> Any? {values[key]}
    override func data(forKey key:String) -> Data? {values[key] as? Data}
    override func set(_ value:Any?,forKey key:String) {values[key]=value}
    override func removeObject(forKey key:String) {values[key]=nil}
}
'''
TESTS=r'''
import Foundation
@main struct Tests {
    @MainActor static var count=0
    @MainActor static func check(_ value:Bool,_ label:String) {precondition(value,label);count+=1}
    @MainActor static func main() async throws {
        typealias P=NativePermissionProof
        let key=P.defaultsKey
        check(key == "computerUse.helperProof.v1","Stable defaults key")
        let me=P.Identity(helperBuild:"1",helperInstall:"7",sentientBuild:"a")
        let now=Date(timeIntervalSince1970:1_800_000_000)
        let saved=P(verifiedAt:now.addingTimeInterval(-7200),identity:me,source:.check)
        // Live evidence always wins.
        check(P.row(live:.verified,proof:nil,current:me,checkFailed:true) == .verified,"Live verification wins over an error")
        let denied=P.row(live:.denied,proof:saved,current:me,checkFailed:false)
        check(denied == .denied && denied.offersSettingsFix && denied.warns && !denied.isOK,"Confirmed denial warns and offers Settings despite a proof")
        // Unknown this session.
        let pending=P.row(live:.unknown,proof:nil,current:me,checkFailed:false)
        check(pending == .pending && !pending.warns && !pending.offersSettingsFix && !pending.isOK,"No proof is neutral, with no fix")
        let earlier=P.row(live:.unknown,proof:saved,current:me,checkFailed:false)
        check(earlier == .verifiedEarlier(saved.verifiedAt) && earlier.isOK && !earlier.warns && !earlier.offersSettingsFix,"Matching proof shows verified earlier")
        for other in [P.Identity(helperBuild:"2",helperInstall:"7",sentientBuild:"a"),
                      P.Identity(helperBuild:"1",helperInstall:"8",sentientBuild:"a"),
                      P.Identity(helperBuild:"1",helperInstall:"7",sentientBuild:"b")] {
            check(P.row(live:.unknown,proof:saved,current:other,checkFailed:false) == .pending,"Proof for \(other) is not shown")
        }
        let failed=P.row(live:.unknown,proof:saved,current:me,checkFailed:true)
        check(failed == .failed && failed.warns && !failed.offersSettingsFix,"A check error outranks an old proof and is not a denial")
        // Wording.
        let us=Locale(identifier:"en_US")
        check(P.detail(.pending) == "Checked when a task starts","Pending wording")
        check(P.detail(.verified) == "Verified" && P.detail(.denied) == "Not allowed","Live wording")
        check(P.detail(.verifiedEarlier(now.addingTimeInterval(-7200)),now:now,locale:us) == "Verified 2 hours ago","Relative wording")
        check(P.detail(.verifiedEarlier(now.addingTimeInterval(-86_400)),now:now,locale:us) == "Verified yesterday","Named relative wording")
        check(P.detail(.verifiedEarlier(now.addingTimeInterval(-20)),now:now,locale:us) == "Verified just now","Recent wording")
        check(P.detail(.verifiedEarlier(now.addingTimeInterval(300)),now:now,locale:us) == "Verified just now","Clock skew never reads as future")
        // Saved record lifecycle.
        let defaults=MemoryDefaults()
        var identity=me
        let store=NativePermissionProofStore(defaults:defaults,current:{identity})
        check(store.proof == nil && store.row(live:.unknown,checkFailed:false) == .pending,"Fresh store is pending")
        store.record(.doctor,at:now)
        check(store.proof?.source == .doctor && defaults.values[key] is Data,"Record saves the proof")
        let relaunched=NativePermissionProofStore(defaults:defaults,current:{identity})
        check(relaunched.proof == store.proof && relaunched.row(live:.unknown,checkFailed:false) == .verifiedEarlier(now),"Proof survives relaunch")
        identity.sentientBuild="b"
        check(relaunched.row(live:.unknown,checkFailed:false) == .pending,"Build change hides proof at once")
        relaunched.prune()
        check(relaunched.proof == nil && defaults.values[key] == nil,"Prune forgets a proof for another build")
        store.record(.check,at:now)
        identity.helperInstall="9"
        let reinstalled=NativePermissionProofStore(defaults:defaults,current:{identity})
        check(reinstalled.proof == nil && defaults.values[key] == nil,"Launch after a helper reinstall drops the proof")
        reinstalled.record(.check,at:now);reinstalled.clear()
        check(reinstalled.proof == nil && defaults.values[key] == nil,"Clear removes the proof")
        defaults.values[key]=Data("not json".utf8)
        let corrupt=NativePermissionProofStore(defaults:defaults,current:{identity})
        check(corrupt.proof == nil && defaults.values[key] == nil,"Unreadable record is removed")
        // Live identity follows the installed helper's Info.plist file.
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("proof-\(UUID().uuidString)")
        defer {try? FileManager.default.removeItem(at:root)}
        let app=root.appendingPathComponent("Helper.app"),plist=app.appendingPathComponent("Contents/Info.plist")
        OpenAIComputerUse.appURL=app
        check(P.liveIdentity().helperInstall == "missing","Missing helper has no install identity")
        try FileManager.default.createDirectory(at:plist.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("a".utf8).write(to:plist)
        let first=P.liveIdentity()
        check(first.helperBuild == "1001365" && first.sentientBuild == "build-a" && first.helperInstall != "missing","Live identity names builds and install")
        check(P.liveIdentity() == first,"Live identity is stable while nothing changes")
        let held=root.appendingPathComponent("held");try FileManager.default.moveItem(at:plist,to:held)
        try Data("a".utf8).write(to:plist)
        check(P.liveIdentity() != first,"Reinstalled helper file changes the identity")
        print("PASS \(count) native permission proof checks")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='sentient-permission-proof-') as directory:
 p=Path(directory)
 for name,value in [('Support',SUPPORT),('Tests',TESTS)]: (p/(name+'.swift')).write_text(value)
 binary=p/'test'
 subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-target',f'{platform.machine()}-apple-macos15.0',
    str(p/'Support.swift'),str(p/'Tests.swift'),str(APP/'Views/Permissions/NativePermissionProof.swift'),
    str(APP/'Driver/NativePermissionReadiness.swift'),str(APP/'Diagnostics/NativeComputerUseFailure.swift'),'-o',str(binary)],check=True,timeout=60)
 subprocess.run([str(binary)],check=True,timeout=15)
