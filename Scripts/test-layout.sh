#!/bin/zsh

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_dir/.build/layout-checks"

mkdir -p "$output_dir"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Overlay/OverlayLayout.swift" \
    "$project_dir/Tests/BabelstaarnetTests/OverlayLayoutTests.swift" \
    -o "$output_dir/OverlayLayoutChecks"

"$output_dir/OverlayLayoutChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Tests/BabelstaarnetTests/HotKeyRegistrationCheck.swift" \
    -framework Carbon \
    -o "$output_dir/HotKeyRegistrationCheck"

"$output_dir/HotKeyRegistrationCheck"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Services/DictionaryService.swift" \
    "$project_dir/Tests/BabelstaarnetTests/DictionaryServiceChecks.swift" \
    -framework CoreServices \
    -o "$output_dir/DictionaryServiceChecks"

"$output_dir/DictionaryServiceChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Models/TextModels.swift" \
    "$project_dir/Tests/BabelstaarnetTests/LearningModeChecks.swift" \
    -o "$output_dir/LearningModeChecks"

"$output_dir/LearningModeChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Services/BeginnerDanishService.swift" \
    "$project_dir/Tests/BabelstaarnetTests/BeginnerDanishServiceChecks.swift" \
    -o "$output_dir/BeginnerDanishServiceChecks"

"$output_dir/BeginnerDanishServiceChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Models/TextModels.swift" \
    "$project_dir/Sources/Babelstaarnet/Overlay/HoverHitTesting.swift" \
    "$project_dir/Tests/BabelstaarnetTests/HoverHitTestingChecks.swift" \
    -o "$output_dir/HoverHitTestingChecks"

"$output_dir/HoverHitTestingChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Models/TextModels.swift" \
    "$project_dir/Sources/Babelstaarnet/Services/AdaptiveCapturePlanner.swift" \
    "$project_dir/Tests/BabelstaarnetTests/AdaptiveCapturePlannerChecks.swift" \
    -o "$output_dir/AdaptiveCapturePlannerChecks"

"$output_dir/AdaptiveCapturePlannerChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Services/SystemIdleMonitor.swift" \
    "$project_dir/Tests/BabelstaarnetTests/PowerSavingPolicyChecks.swift" \
    -o "$output_dir/PowerSavingPolicyChecks"

"$output_dir/PowerSavingPolicyChecks"
