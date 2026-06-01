# Cousebara

A macOS menu bar app for monitoring Claude subscription usage — session (5-hour) and weekly quotas.

## Features

- Menu bar shows two color-coded vertical bars: Session (5-hour) and Weekly (7-day)
- Click to open a popover with per-window usage, reset time, and pace (ahead/behind a linear burn)
- Auto-refresh every 15 minutes + manual refresh
- Reads your existing Claude Code login — no separate sign-in
- No Dock icon — lives entirely in the menu bar

## Install

```sh
brew tap oronbz/tap && brew install --cask cousebara
```

Or download `Cousebara.zip` from the [latest release](https://github.com/oronbz/Cousebara/releases/latest), unzip, and move `Cousebara.app` to `/Applications`.

## Update

```sh
brew update && brew upgrade --cask cousebara
```

## Requirements

- macOS 14.0 (Sonoma) or later
- A Claude subscription, logged in via Claude Code

## How It Works

Cousebara reads your Claude OAuth token from the macOS Keychain (the credentials
Claude Code stores after you log in) and calls Anthropic's usage endpoint to show
your Session (5-hour) and Weekly (7-day) utilization. The first read triggers a
one-time macOS Keychain permission prompt — click Always Allow.

If you're not logged in to Claude Code, Cousebara shows a "Log in with Claude
Code first" prompt; run `claude` and sign in, then click Refresh.

### Progress Bar Colors

| Usage     | Color  |
|-----------|--------|
| 0-60%     | Green  |
| 60-85%    | Yellow |
| 85-100%   | Orange |
| 100%      | Red    |

## Building from Source

1. Clone the repo
2. Open `Cousebara.xcodeproj` in Xcode
3. Build and run (Cmd+R)

## Releasing a New Version

```sh
make release VERSION=1.6.0
```

This bumps the version in all source files, runs tests, commits, builds a Release archive, creates a GitHub release with the zip attached, and updates the Homebrew tap formula with the new sha256. Omit `VERSION=` to be prompted interactively.
