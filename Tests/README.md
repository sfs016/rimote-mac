# Tests

## End-to-end pairing test

`run-e2e.sh` is a black-box integration test that drives the **real** Rimote
agent binary through the full `PROTOCOL.md` handshake over an actual WebSocket —
the same path the iPhone app uses.

```bash
Tests/run-e2e.sh
```

It builds `Rimote.app`, launches it with an isolated test environment, waits for
the WebSocket port, then runs `E2EPairingTest.swift` (a dependency-free
`URLSessionWebSocketTask` client) and asserts:

1. `pair_request` → `pair_challenge` (with device name)
2. `pair_verify` → `pair_result` with a 64-hex token
3. a status push immediately after pairing
4. an authenticated `status` read returns live state
5. a real command (`mute`, toggled twice so system state is restored) is acked
   and pushes updated state
6. a command bearing a bad token is rejected with `unauthorized`

Exit code `0` means every check passed.

### How it stays hermetic

The agent exposes two environment-gated seams (see `Rimote/App/TestSupport.swift`),
both inert unless their variable is set, so shipping builds are unaffected:

- `RIMOTE_TEST_PIN` — fixes the 4-digit pairing PIN so the client can complete
  the handshake without reading the menubar. The PIN is never logged or sent.
- `RIMOTE_TEST_MODE=1` — skips registering the login item.

The runner also points `HOME`/`CFFIXED_USER_HOME` at a throwaway directory, so the
issued token is written to a temporary Application Support location and the real
machine's pairing state is never touched.

> Note: the test binds port `8765`. Stop any other Rimote agent (including the
> PoC `RimoteAgent`) before running.
