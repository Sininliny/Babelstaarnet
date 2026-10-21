# Windows presentation

Windows shares reading behavior with Mac and uses its own presentation. Keep
lookup compact so it does not become a second application over the text.

## Native host and theme

Settings and Word Book use the .NET built-in Fluent window theme. Native
caption, resize, system menu, keyboard and platform backdrop behavior remain
under Windows control. `WindowsTheme` isolates the experimental `ThemeMode`
API; it applies only to ordinary windows, not transparent lookup panels.
See [Microsoft's Fluent theme documentation](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/whats-new/net90)
and [ThemeMode reference](https://learn.microsoft.com/en-us/dotnet/api/system.windows.window.thememode?view=windowsdesktop-10.0).

Appearance defaults to the Windows setting, with explicit Light and Dark
choices. Accent colors follow Windows and are adjusted for readable text.
High contrast uses Windows foreground, background and highlight colors;
reduced motion suppresses the known-word animation.

All custom controls use the palette in `Presentation/Theme/WindowsTheme.cs`.
Its bound brushes update existing surfaces without rebuilding their visual
trees. A bound brush cannot be frozen when a WPF template is sealed. Keep
icon decoder caches on their owning dispatcher, including frozen icon frames
whose decoders Windows may revisit while creating an HWND.

## Surfaces and controls

| Element | Convention |
| --- | --- |
| Settings | Resizable 880-point window, 210-point navigation rail, one page at a time |
| Page heading | 28-point Segoe UI Variable / Segoe UI, semibold |
| Word lookup | 280-point compact card, 8-point corners, 16-point meaning and 12-point source |
| Sentence lookup | Separate 420-point card, 12-point running text and restrained English tint |
| Quick actions | Small rectangular Known, Learn and Pin actions with shortcut hints |
| Focus | Windows accent underline on the actual source occurrence |
| Word Book | Recycling list; search/filter without constructing every row |
| Tray | Contrast-aware tower logo, matching light/dark popover |

Keep native WPF control types and automation peers. Styling must preserve
Tab, Enter/Space, arrow navigation and shortcut recording. Popups need palette
resources too. Use a visible keyboard focus treatment, not just hover color.
All text remains live WPF text; shadows sit behind the panel so small type
does not become a scaled bitmap.

The lookup surface uses an opaque, readable fill rather than expensive blur
over the text being studied. Screen capture temporarily excludes only the
app's own panels; ordinary screenshots can include them. Exclusion is restored
on completion, cancellation and failure.

## Verification

Render actual production controls with `WindowsChecks.exe --render-ui` in
light and dark modes. Inspect long meanings, sentence wrapping, shortcut
labels, selected navigation, empty/loading states and Word Book review. Native
checks exercise live theme updates, palette contrast, appearance persistence,
navigation callbacks and container recycling. They also exercise repeated
tray-to-settings opening on invisible windows.

Fixture rendering does not prove every user's screen scaling, display setup
or accessibility combination. Native behavior still warrants real-device
testing when those integrations change.
