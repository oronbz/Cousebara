# Cousebara

A macOS menu bar app for monitoring GitHub Copilot premium interaction usage.

## Features

- Menu bar icon with color-coded progress bar (green / yellow / orange / red overshoot)
- Over-usage visualization: red overshoot portion extends beyond the bar when over-limit
- Click to open a popover with detailed usage stats
- Auto-refresh every 15 minutes + manual refresh on click
- Shows used/entitlement, remaining (or "over by X"), and quota reset date
- No Dock icon -- lives entirely in the menu bar

## Install

```sh
brew install --cask oronbz/tap/cousebara
```

Or download `Cousebara.zip` from the [latest release](https://github.com/oronbz/Cousebara/releases/latest), unzip, and move `Cousebara.app` to `/Applications`.

## Update

```sh
brew update && brew upgrade --cask cousebara
```

## Requirements

- macOS 14.0 (Sonoma) or later
- A GitHub Copilot subscription

## How It Works

On first launch, Cousebara checks for an existing Copilot OAuth token at `~/.config/github-copilot/apps.json`. If one is found (e.g., from VS Code, Neovim, or JetBrains Copilot plugins), usage data loads immediately -- no extra login needed.

If no token is found, Cousebara walks you through a quick GitHub sign-in using the Device Flow: you get a one-time code, authorize on github.com in your browser, and the app saves the token to `apps.json` automatically.

### Progress Bar Colors

| Usage     | Color          |
|-----------|----------------|
| 0-60%     | Green          |
| 60-85%    | Yellow         |
| 85-100%   | Orange         |
| Over 100% | Orange + Red overshoot |

## Building from Source

1. Clone the repo
2. Open `Cousebara.xcodeproj` in Xcode
3. Build and run (Cmd+R)

## Releasing a New Version

1. Build a Release archive:
   ```sh
   xcodebuild -project Cousebara.xcodeproj -scheme Cousebara -configuration Release \
     -archivePath /tmp/Cousebara.xcarchive archive
   ```
2. Zip the `.app`:
   ```sh
   cd /tmp/Cousebara.xcarchive/Products/Applications/
   ditto -c -k --sequesterRsrc --keepParent Cousebara.app /tmp/Cousebara.zip
   ```
3. Create a GitHub release:
   ```sh
   gh release create v1.x.0 /tmp/Cousebara.zip --repo oronbz/Cousebara --title "Cousebara v1.x.0"
   ```
4. Update the Homebrew tap formula at [`oronbz/homebrew-tap`](https://github.com/oronbz/homebrew-tap):
   - Update `version` and `sha256` in `Casks/cousebara.rb`
   - `sha256` can be computed with `shasum -a 256 /tmp/Cousebara.zip`
5. Users upgrade with `brew update && brew upgrade --cask cousebara`
