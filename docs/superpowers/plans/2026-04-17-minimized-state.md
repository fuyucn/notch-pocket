# Minimized shelf state

**Branch:** continue on `plan-7-airdrop-drop-target` (this lands under v0.4.1 / v0.4.2 — coordinator decides at release time)

## Goal

Give the shelf a small permanent "there's stuff in here" indicator so users don't forget about files they've stashed. The indicator is a pill-shaped mini-panel sitting just below the notch, with a tray icon on the left shoulder and a count badge on the right shoulder.

## Behaviour

- **New `NotchViewModel.Status.minimized`** case (4th status).
- When `.opened` transitions back to a "no file drag in progress, no user interaction" state via `forceClose()` or `didResignKey`:
  - if `shelfCount > 0` → status becomes `.minimized` instead of `.closed`
  - if `shelfCount == 0` → status becomes `.closed` (same as today)
- **On launch**: AppDelegate reads `shelfManager.items.count`; if > 0 sets `vm.status = .minimized`.
- **Click on minimized pill** → `vm.status = .opened` (we'll make the pill itself a Button / onTap).
- **Drag file in** while minimized: behaves exactly like drag-in while closed/popping — drop detection flows through NotchDropForwarder's draggingEntered which already toggles `isDragInside` and triggers `.popping` (we'll need to update `updateMouseLocation` so `.minimized` is also an acceptable starting state).

## Visual

Same pattern as the popping bar but smaller:

- Size: `notch.width + 80pt` wide, `notch.height + 8pt` tall (so it just hangs below the notch)
- Top + bottom corner radii: small (matches `NotchShape.closed*`)
- Layout: `HStack { tray.fill | spacer reserved notch width | Text("N") capsule }` — same notchTopBar approach but no right-shoulder buttons
- Background: same NotchShape, black fill, subtle white stroke

## Files affected

### `NotchViewModel`
- Add `.minimized` case to `Status` enum
- `updateMouseLocation(_:isDragging:)`: allow `.minimized` as an entry state for drag → `.popping` / `.opened`; and when `isFileDragging` becomes false again and we'd transition to `.closed`, stay `.minimized` if `shelfCount > 0`. Simplest: at the end of `updateMouseLocation`, before setting `.closed`, check `shelfCount > 0` and promote to `.minimized`.
- `forceClose()`: now `closeOrMinimize()` logic — if shelf has items, go to `.minimized` instead. Keep `forceClose()` semantics as "user explicitly wants closed, even if shelf has files" (e.g. quit), and add `requestClose()` that does the smart logic. The click-outside / × button call site uses `requestClose()`.

### `NotchPanelRootView`
- `targetSize`: add `.minimized` case → small pill size
- `targetTopRadius` / `targetBottomRadius`: `.minimized` → `closedTopRadius` / `closedBottomRadius` (tight tuck)
- `content`: add `.minimized` case rendering a tappable `HStack { tray.fill | Color.clear notchWidth | Text("N") }` wrapped in the same NotchShape clip, with `.onTapGesture { viewModel.status = .opened }`
- `ignoresMouseEvents` sync: `.closed` → true (click-through); `.minimized` → **false** (we want the tap to register); `.popping` / `.opened` → false

### `NotchPanel`
- `canBecomeKey`: add `.minimized` to the set that can take key status? Actually no — minimized should still NOT steal keyboard focus; keep it only opened. That means click-outside-to-close during minimized doesn't apply (it wasn't key to begin with).

### `AppDelegate`
- Right after `shelfManager.validateItems()` and before the VM init, check items count; after creating vm, set `vm.status = .minimized` if `shelfManager.items.count > 0`.
- Wire: `shelfManager.onItemsChanged` — when items drop to 0 and vm.status == .minimized → go `.closed`.
- Bug to guard against: `didResignKey` observer only fires when opened; minimized isn't key so no spurious close.

## Tests

- `NotchViewModelTests`: new tests exercising minimized transitions
  - Initial `.closed`, then receive `.markDropped()` on first drop → `.opened`
  - forceClose (via click outside) with shelfCount>0 → test that the model resolves to `.minimized`
  - Transitioning `.minimized` → `.opened` via an API call
  - updateMouseLocation while `.minimized` + isFileDragging=true → `.popping`

- `NotchPanelTests`: the `panelIgnoresMouseEventsWhen*` test stays; add "panelReceivesMouseEventsWhenMinimized"

Expect test count to grow by ~4-5.

## Out of scope

- Persistence across app relaunches — items are still in-memory, so the "launch shows minimized if items exist" path fires only when we restore persisted items (future plan).
- Thumbnails in the minimized pill — user explicitly picked the simplest "tray + count" look.
- Minimized-state-only drag-out — no. Reaching minimized means shelf has items; to drag them out the user opens the panel first.

## Commit message

`feat: minimized shelf state — tray + count pill when items are on the shelf`
