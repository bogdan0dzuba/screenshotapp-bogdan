import Foundation
import ScreenshotCore

func checkScreenCapturePermission() throws {
    func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }
    var gate = ScreenCapturePermission()
    var allowed = false
    var requests = 0
    let denied = gate.requestIfNeeded(preflight: { allowed }, request: { requests += 1; return false })
    try expect(!denied && requests == 1, "missing permission requests access and blocks capture")
    let repeated = gate.requestIfNeeded(preflight: { allowed }, request: { requests += 1; return false })
    try expect(!repeated && requests == 1, "repeated denial does not repeat the system request")
    allowed = true
    let enabled = gate.requestIfNeeded(preflight: { allowed }, request: { requests += 1; return false })
    try expect(enabled && requests == 1, "grant from Settings is read again on the next capture")
    allowed = false
    let revoked = gate.requestIfNeeded(preflight: { allowed }, request: { requests += 1; return true })
    try expect(!revoked, "revoked permission cannot reuse previously granted access")

    var alreadyAllowed = ScreenCapturePermission()
    try expect(alreadyAllowed.requestIfNeeded(preflight: { true }, request: { requests += 1; return false }),
               "existing permission passes without prompting")
    try expect(requests == 1, "existing permission never prompts")
    var notApplied = ScreenCapturePermission()
    try expect(!notApplied.requestIfNeeded(preflight: { false }, request: { true }),
               "request result alone does not prove effective access before restart")
    var immediatelyApplied = ScreenCapturePermission()
    var newlyAllowed = false
    try expect(immediatelyApplied.requestIfNeeded(preflight: { newlyAllowed }, request: { newlyAllowed = true; return true }),
               "immediately effective grant permits capture")
    do {
        try ScreenCapturePermission.requireAccess(preflight: { false })
        throw NSError(domain: "capture backend must reject missing permission", code: 1)
    } catch ScreenCapturePermissionError.denied { }
    try ScreenCapturePermission.requireAccess(preflight: { true })
}
