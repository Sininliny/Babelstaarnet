# Repository guidance

- Read `docs/DEVELOPMENT.md` for the platform map and validation commands.
- Swift app and capability modules live in `Sources/`; Windows domain logic
  lives in `Windows/Babelstaarnet.Core`, and Windows adapters/UI in
  `Windows/Babelstaarnet.Windows`. Keep WPF/Win32 out of the domain project.
- Preserve public script paths and the current Swift package layout. Internal
  source folders may change without moving user data or model installations.
- Danish tables and prompts originate in `Sources/LanguageDanish/Danish.swift`.
  Regenerate the Windows data with `Scripts/sync-windows-language.py`.
- Add cross-platform behavior examples to `Tests/Shared/reading-contract.json`
  and exercise them in both native implementations.
- Run `python Scripts/check-repository.py`, then the relevant native checks.
  Windows uses `Scripts/test-windows.ps1`; Mac uses `make test`.
- Tests must not download models, play audible audio, capture a user's desktop
  or activate visible windows. Use fixture pixels, muted playback and invisible
  application-owned windows. UI errors must fail checks instead of opening dialogs.
- Reading stays offline. Keep setup-only downloads separate from runtime code.
  Preserve vocabulary and profiles across upgrades.
- Use `docs/WINDOWS_DESIGN.md` for Windows styling. Verify light/dark renders and
  keyboard behavior. Honor high contrast and reduced motion.
- Keep `build/`, `dist/`, local environments, models and user data untracked.
  Never describe fixture timing as complete real-desktop latency.
