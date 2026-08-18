# RecShot

A tiny Mac menu-bar app. Capture a region, and the shot stacks in the bottom-left corner. Click the toggle to fan the stack into thumbnails, then drag any one into Slack, Notes, Figma, Finder, or anywhere else that accepts an image.

## Use

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) if needed (`brew install xcodegen`), then:

   ```sh
   make run
   ```

2. RecShot lives in the menu bar (camera icon). There is no Dock icon.
3. Grant **Screen Recording** when macOS asks (System Settings › Privacy & Security › Screen Recording).
4. Press **⌥⌘S**, or click the coral camera on the corner pill, and drag out a region.
5. Click the stack toggle on the pill to show every screenshot as a small thumbnail.
6. Drag a thumbnail into another app. Click one to copy. Right-click for Copy / Show in Finder / Delete.

Full-display capture is in the menu-bar menu.

## Quit

Menu bar camera → **Quit RecShot**.
