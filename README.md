# RecShot

A tiny Mac menu-bar app. Capture a region, and the shot stacks in the bottom-left corner. Click the toggle to fan the stack into thumbnails, then drag any one into Slack, Notes, Figma, Finder, or anywhere else that accepts an image.

## Use

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed (`brew install xcodegen`), then:

   ```sh
   make run
   ```

2. RecShot lives in the menu bar (camera icon). There is no Dock icon.
3. Grant **Screen & System Audio Recording** when macOS asks (System Settings › Privacy & Security › Screen & System Audio Recording).
4. Press **⌥⌘S**, or click the coral camera on the corner pill, and drag out a region.
5. Press **⌥⌘R** and choose **Application** or **Full Display** to start a video recording. Press **⌥⌘R** again, or click the red stop control, to finish it.
6. Click the stack toggle on the pill to show the 10 most recent captures.
7. Drag a capture into another app. Click one to copy. Right-click for Copy / Show in Finder / Delete.

Full-display capture is in the menu-bar menu.

Screenshots and recordings are saved in `~/Pictures/RecShot`. Existing captures from the old `~/Library/Application Support/RecShot/captures` location are migrated there on the next launch. RecShot does not automatically delete older captures; use **Clear All** or delete individual items when needed.

## Quit

Menu bar camera → **Quit RecShot**.
