# NimbiKit

The shared code behind every nimbi app: the cloud, the design tokens and the small pieces of
chrome that make a nimbi app look like one. Relay was the first app; its cloud and UI moved here
so the next ones import them instead of copying.

The design itself lives in [`DESIGN.md`](https://github.com/behkha/nimbi/blob/main/DESIGN.md) in the
nimbi site repo. This package is its SwiftUI half: when the two disagree, DESIGN.md is the target.

- Swift 5.9, macOS 13+, SwiftUI and AppKit.
- Zero dependencies.

## Adding it

In a Swift package:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/behkha/nimbi-kit.git", from: "0.7.0")
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [.product(name: "NimbiKit", package: "nimbi-kit")]
    )
]
```

In an Xcode project: File → Add Package Dependencies…, paste the URL above, and add the
`NimbiKit` library to the app target.

To work on NimbiKit and an app at the same time, point the app at a local checkout instead:
`.package(path: "../nimbi-kit")`.

Then `import NimbiKit` in the files that use it.

## What's inside

### Tokens

- `Color(hex:)`: `"#RRGGBB"` in sRGB.
- `ViewState`: `SwiftUI.State` under another name. `@State` is a macro whose plugin ships only with
  full Xcode, so `@ViewState private var hover = false` builds with the Command Line Tools alone.
- `Nimbi`: the tokens from DESIGN.md 15.1, extended with the rest of section 4.
  - `Nimbi.Surface` (`void`, `panel`, `panelBlack`, `window`, `sidebar`, `well`, `row`, …)
  - `Nimbi.Line` (`rim`, `row`, `card`, `pill`, `pillActive`)
  - `Nimbi.Text` (`primary`, `message`, `strong`, `dim`, `faint`, `ghost`)
  - `Nimbi.Aurora` (`sky`, `lavender`, `blush`, `glow`, `ink`, `gradient`)
  - `Nimbi.State` (`working`, `waiting`, `done`, `destructive`, `asking`, `listening`, `rain`, bubbles, …)
  - `Nimbi.Heat` (`core` … `coal`)
  - `Nimbi.Radius` (`keyHint` 5 … `card` 20)
  - `Nimbi.Motion` (`enter`, `bounce`, `panel`, `mood`, `gaze`, `leave`, `hover`, undo windows, …)

### The cloud

```swift
NimbiCloud(size: 40, mood: .busy, working: 3)
NimbiCloud(size: 20, mood: mood, glance: 1, followsCursor: false, lively: false)
```

- `NimbiCloud(size:mood:working:glance:blinks:followsCursor:lively:)`: the mascot. It follows
  the cursor, blinks, plays (giggly, dizzy) over the playful moods, pauses while its window is
  hidden, and with `lively: false` holds still and only stirs for a moment after a mood change.
  Under Reduce Motion it changes mood but doesn't hop, shake or sway.
- `Mood`: the eleven moods from DESIGN.md 3.3. Map your app's states onto them; don't add new ones
  here before they're in DESIGN.md.
- `NimbiCloud(…, weather:)`: weather drawn around the cloud (DESIGN.md 3.5: the cloud stays the
  cloud, props sit next to it). `CloudWeather`: `.clear` (a sun behind it), `.partlyCloudy`,
  `.clearNight` (moon and stars), `.rain(0…1)`, `.thunder` (a bolt beside it), `.snow`, `.sleet`,
  `.fog`, `.wind`, `.hot`. Drawn from 36 pt up, still under Reduce Motion, paused while hidden.
- `NimbiCloud(…, form:, progress:)`: the shape it takes (DESIGN.md 3.5, Tempo only). `CloudForm`:
  `.cloud`, `.hourglass` (its sand runs down with `progress`, 0…1), `.bell` (swings, ringing),
  `.mug` (steaming), `.moon`. Skin, face, eyes and moods stay; the outline springs from one form to
  the next point by point, overshooting a little for a squash and stretch.
- `FormShape(form)`: a form's outline on its own, animatable (`Outline` is its `VectorArithmetic`).
- `CloudShape`: the outline on its own (icons, masks, glows).
- `VisibilityProbe`: tells a view when its window is hidden or covered, to pause animation.

### Look settings

The app owns and saves its settings; NimbiKit's components read them from one object that the app
keeps in step:

```swift
let look = NimbiAppearance.shared
look.theme = .black          // NimbiTheme: .dark, .black
look.textScale = 1.1         // 0.9 … 1.25
look.pillScale = 1           // 0.8 … 1.3
look.dock = .notch           // NimbiDock: .right, .left, .notch
look.showTooltips = true
```

`look.font(size, weight)` is the system font grown with the text size.

### Components

- `PanelBackground(cornerRadius:)`: the solid panel (panel or panelBlack, with a rim). At the
  notch, with `.environment(\.hangsFromPill, true)`, it turns into the black flat-topped `IslandBody`.
- `.floatingPanelShadow()`: the one panel shadow, with room so the window never clips it.
- `IslandShape(bottomRadius:ear:)`: the notch island's outline, flat on top with concave ears.
  `NSScreen.hasNotch`, `.notchSize`, `.notchMidX` and `NSScreen.islandScreen` measure where it goes.
- `SizeReportingHostingView`: an `NSHostingView` that calls `onFittingSizeChange` when the content
  wants a new size, so a borderless panel can resize around it.
- `KeyHint(key:onLight:)`
- `UndoBar(label:systemImage:tint:started:duration:onUndo:)`: "Timer reset · esc to undo" with the
  draining blue line (DESIGN.md 8). The app keeps the pending action; this only draws it.
- `PrimaryButtonStyle()`, `SecondaryButtonStyle()`,
  `PillButtonStyle(prominent:light:destructive:hint:)`
- `StatusGlyph(_:working:color:hot:size:pop:)`: working arc, colored dot or ember; pops when
  its value changes to something that isn't working. `StatusGlyph(working:color:)` pops on color.
- `.popOnChange(of:strength:when:)` / `StatusPop`
- `ListeningBars(color:height:)`
- `EdgeTab(radius:flare:mirrored:)`: the collapsed pill's shape.
- `.pillChrome(_:active:id:in:smoke:)` / `PillChrome` and `.glassGroup(spacing:)`: Liquid Glass on
  macOS 26+, a flat pill fill before.
- `.hoverTip(_:)` / `HoverTip`, `.hoverHalo(_:)` / `HoverHalo`: the pill's hover label and glow.
- `PointerTracker`, `\.pointerTracker`, `.pointerHover(perform:)`: hover that works while the
  app isn't active (feed the tracker from your panel's tracking area).

### Shared surfaces

`SurfaceClaim` is phase 1 of DESIGN.md 18.2: who draws at the notch and the edge.

```swift
let claim = SurfaceClaim(surface: .notch)            // this app's bundle ID
let watching = SurfaceClaim.observe { other in ... } // every app's claims, on the main queue
if claim.claim() { /* draw the island */ } else { /* fall back to the menu bar */ }
claim.take()                                         // the user picked this app: owner, and tell everyone
SurfaceClaim.owner(of: .edge)                        // bundle ID or nil
SurfaceClaim.setOwner("app.nimbi.skyline", of: .notch)
```

Claims travel as the distributed notification `app.nimbi.surface.claim`. Owners live in the
`group.app.nimbi` defaults (standard defaults when the group can't be opened). Relay and Skyline act on the notch's owner.

For an app with its own island (phase 1, until the shared island exists), `NotchOwnership` and
`NotchIsland` do the rest:

```swift
let notch = NotchOwnership(appName: "Tempo")          // owner, line, take(), giveBack(), giveBackTitle
let island = NotchIsland(ownership: notch, closed: { state in
    IslandWings(state: state) { NimbiCloud(size: 24, mood: mood) } right: { Text("18′") }
}, open: { state in MyPage() })
island.onShown = { shown in statusItem.isVisible = !shown }  // one glyph at a time
island.onKey = { keyCode in false }                          // keys while it has the keyboard; esc closes
island.attach(width:) / island.detach() / island.hangPoint   // a panel hanging from it
```

It shows only while the user has picked this app as the notch's owner, opens after 0.2 s of hover,
closes 0.6 s after the pointer leaves, and opens at once on a click (DESIGN.md 18.6).

### Swiping between apps

Every app keeps its own island; a swipe moves the notch to the next running nimbi app (DESIGN.md
18.2a). `NotchIsland` does it on its own: a two-finger swipe, a drag or ← → on the open island hands
the notch on, the next app's island opens with its page drifting in, and page dots show the ring.
`NotchRing.shared` keeps the ring (running apps that can be at the notch, in install order; Relay
first while its pill is at the notch), answers ⌃⌥← / ⌃⌥→ from anywhere, and watches for swipes over
Relay's own island while Relay has the notch.

```swift
NimbiCloud(size: 92, mood: mood).islandDrift(.cloud)   // the page's cloud drifts furthest
VStack { /* title, subtitle, actions */ }.islandDrift(.text)
island.setNeedsYou(urgency == .needsYou)              // this app's dot glows amber elsewhere
```
