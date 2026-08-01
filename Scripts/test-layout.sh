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
    "$project_dir/Sources/Babelstaarnet/Overlay/BubbleInteractionPolicy.swift" \
    "$project_dir/Tests/BabelstaarnetTests/BubbleInteractionChecks.swift" \
    -o "$output_dir/BubbleInteractionChecks"

"$output_dir/BubbleInteractionChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Models/TextModels.swift" \
    "$project_dir/Sources/Babelstaarnet/Overlay/OverlayState.swift" \
    "$project_dir/Sources/Babelstaarnet/Overlay/OverlayRootView.swift" \
    "$project_dir/Tests/BabelstaarnetTests/BubbleViewSizingChecks.swift" \
    -framework AppKit \
    -framework SwiftUI \
    -o "$output_dir/BubbleViewSizingChecks"

"$output_dir/BubbleViewSizingChecks"

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
    "$project_dir/Sources/Babelstaarnet/Services/HotKeyConfiguration.swift" \
    "$project_dir/Tests/BabelstaarnetTests/HotKeyConfigurationChecks.swift" \
    -framework AppKit \
    -framework Carbon \
    -o "$output_dir/HotKeyConfigurationChecks"

"$output_dir/HotKeyConfigurationChecks"

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
    "$project_dir/Sources/Babelstaarnet/Services/LearnerProfileStore.swift" \
    "$project_dir/Sources/Babelstaarnet/Services/AdaptiveExplanationService.swift" \
    "$project_dir/Tests/BabelstaarnetTests/AdaptiveLearningChecks.swift" \
    -o "$output_dir/AdaptiveLearningChecks"

"$output_dir/AdaptiveLearningChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Services/AdaptiveSentenceBridgeService.swift" \
    "$project_dir/Tests/BabelstaarnetTests/AdaptiveSentenceBridgeChecks.swift" \
    -o "$output_dir/AdaptiveSentenceBridgeChecks"

"$output_dir/AdaptiveSentenceBridgeChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Services/BeginnerDanishService.swift" \
    "$project_dir/Sources/Babelstaarnet/Services/AdaptiveSentenceBridgeService.swift" \
    "$project_dir/Tests/BabelstaarnetTests/AdaptiveWordBridgeChecks.swift" \
    -o "$output_dir/AdaptiveWordBridgeChecks"

"$output_dir/AdaptiveWordBridgeChecks"

swiftc \
    -parse-as-library \
    -module-cache-path "$output_dir/module-cache" \
    "$project_dir/Sources/Babelstaarnet/Services/TranslationQualityService.swift" \
    "$project_dir/Tests/BabelstaarnetTests/TranslationQualityChecks.swift" \
    -o "$output_dir/TranslationQualityChecks"

"$output_dir/TranslationQualityChecks"

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
