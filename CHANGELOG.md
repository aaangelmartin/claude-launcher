# Changelog

All notable changes to Claude Launcher. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-14

### Added

- A global shortcut (⌥C by default) that brings up Claude Launcher, styled after Claude's own quick entry.
- Every Claude Code session running on this Mac, with its state (Needs input, Working, Completed); ↵ brings its Terminal tab forward.
- Folder search, fuzzy or by path, with each folder's git branch, last use and session count; the best match is lit, so the shortcut again starts a session there.
- A folder's step: a new session, its running sessions and its past ones to resume.
- New folders for new projects: a name that is no folder yet can be created, and Claude starts in it.
- Launch options: model (numbers read from the installed `claude`), effort (each model's default marked), permission mode.
- The plan's five-hour and weekly use, with the time left until each resets.
- A first-run setup: what it does, a check of Claude Code, Terminal permission, sign-in, the Claude app and start at login, and a shortcut recorder.

[1.0.0]: https://github.com/aaangelmartin/claude-launcher/releases/tag/v1.0.0
