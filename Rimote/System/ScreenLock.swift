import Foundation

/// Locks the screen immediately.
///
/// Uses `SACLockScreenImmediate` from the private `login` framework, which
/// requires **no** TCC permission — unlike driving a Ctrl-Cmd-Q keystroke through
/// System Events (Automation) or CGEvent (Accessibility). Rimote ships outside the
/// Mac App Store (a notarized `.dmg`), so the private symbol is acceptable here.
enum ScreenLock {
    private typealias LockFn = @convention(c) () -> Int32

    @discardableResult
    static func lock() -> Bool {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        guard let handle = dlopen(path, RTLD_NOW) else { return false }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else { return false }
        let lock = unsafeBitCast(symbol, to: LockFn.self)
        return lock() == 0
    }
}
