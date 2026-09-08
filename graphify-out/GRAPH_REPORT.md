# Graph Report - armario_virtual  (2026-08-22)

## Corpus Check
- 83 files · ~92,126 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1193 nodes · 1631 edges · 65 communities (59 shown, 6 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Win32Window
- add_garment_screen.dart
- outfit_screen.dart
- GeneratedPluginRegistrant.swift
- my_application.cc
- garment.dart
- AppDelegate
- wardrobe_provider.dart
- wWinMain
- manifest.json
- RegisterPlugins
- MainActivity
- color_extraction_service.dart
- calendar_screen.dart
- wardrobe_settings_screen.dart
- wardrobe_settings_provider.dart
- outfit_screen.dart
- garment_autocrop_service.dart
- StatelessWidget
- image_compositor.dart
- profile_sheet.dart
- home_screen.dart
- outfit_flat_lay_view_test.dart
- api_key_dialog.dart
- shimmer_box.dart
- gemini_outfit_service.dart
- WardrobeProvider
- app_palette.dart
- State
- background_removal_service.dart
- pressable_scale.dart
- garment_image.dart
- outfit_flat_lay_view.dart
- outfit_plan_provider.dart
- BackgroundRemovalPlugin
- category_badge.dart
- BackgroundRemovalPlugin.swift
- List
- color_extraction_test.dart
- ApiKeyProvider
- FlutterMacOS
- empty_state.dart
- image_enhancer.dart
- ai_outfit_card.dart
- package:flutter/foundation.dart
- package:flutter/material.dart
- OutfitPlanProvider
- theme_mode_provider.dart
- api_key_service.dart
- package:image/image.dart
- dart:convert
- dart:typed_data
- user_profile_provider.dart
- AppDelegate
- outfit_filters.dart
- package:shared_preferences/shared_preferences.dart
- armario_virtual
- CLAUDE.md
- LaunchImage.imageset/README.md
- AppPalette
- String?

## God Nodes (most connected - your core abstractions)
1. `WardrobeProvider` - 27 edges
2. `Win32Window` - 22 edges
3. `WardrobeSettingsProvider` - 16 edges
4. `OutfitPlanProvider` - 15 edges
5. `MessageHandler` - 12 edges
6. `FlutterWindow` - 10 edges
7. `Create` - 10 edges
8. `WndProc` - 10 edges
9. `MessageHandler` - 9 edges
10. `ApiKeyProvider` - 8 edges

## Surprising Connections (you probably didn't know these)
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `Win32Window::Win32Window()` --calls--> `Destroy`  [INFERRED]
  windows/runner/win32_window.cpp → windows/runner/win32_window.h
- `build` --references--> `ThemeModeProvider`  [EXTRACTED]
  lib/main.dart → lib/providers/theme_mode_provider.dart
- `_ApiKeyDialogState` --references--> `ApiKeyProvider`  [EXTRACTED]
  lib/screens/api_key_dialog.dart → lib/providers/api_key_provider.dart
- `_validateAndSave` --references--> `ApiKeyProvider`  [EXTRACTED]
  lib/screens/api_key_dialog.dart → lib/providers/api_key_provider.dart

## Import Cycles
- None detected.

## Communities (65 total, 6 thin omitted)

### Community 0 - "Win32Window"
Cohesion: 0.06
Nodes (53): PluginRegistry, Point, RECT, Size, unique_ptr, RegisterPlugins(), DartProject, HWND (+45 more)

### Community 1 - "add_garment_screen.dart"
Cohesion: 0.02
Nodes (80): ImageSource, int?, accent, _aiAnalysisFailed, _aiAnalyzing, _ajustando, _analizando, _analyzeGarmentCategory (+72 more)

### Community 2 - "outfit_screen.dart"
Cohesion: 0.07
Nodes (29): ArmarioVirtualApp, _buildTheme, charcoal, createState, _currentIndex, gold, goldSoft, isDark (+21 more)

### Community 3 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.17
Nodes (10): file_selector_macos, flutter_secure_storage_macos, FlutterPluginRegistry, FlutterViewController, Foundation, RegisterGeneratedPlugins(), MainFlutterWindow, NSWindow (+2 more)

### Community 4 - "my_application.cc"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 5 - "garment.dart"
Cohesion: 0.05
Nodes (44): dart:math, gemini_outfit_service.dart, category, color, copyWith, createdAt, fromJson, Garment (+36 more)

### Community 6 - "AppDelegate"
Cohesion: 0.20
Nodes (7): Any, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, FlutterPluginRegistrar, AppDelegate, Bool, UIApplication

### Community 7 - "wardrobe_provider.dart"
Cohesion: 0.17
Nodes (11): addGarment, archivedGarments, archiveOutOfSeason, byCategory, clearAll, _garments, _isLoading, _loadGarments (+3 more)

### Community 8 - "wWinMain"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 9 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 10 - "RegisterPlugins"
Cohesion: 0.02
Nodes (91): dart:async, dart:isolate, Isolate, _alive, _applyMask, _cachedModelFileName, _capResolution, collect (+83 more)

### Community 16 - "color_extraction_service.dart"
Cohesion: 0.02
Nodes (81): int x0, y0, x1,, a, achromatic, achromaticMaxChroma, area, assignments, b, bb (+73 more)

### Community 17 - "calendar_screen.dart"
Cohesion: 0.04
Nodes (47): _aiError, _aiLoading, _aiOutfits, _bottom, _buildExistingPlan, _buildHandle, _buildPicker, byId (+39 more)

### Community 18 - "wardrobe_settings_screen.dart"
Cohesion: 0.06
Nodes (43): WardrobeSettingsProvider, _generateAiOutfits, _accent, _AddReglaField, _AddReglaFieldState, _AdvancedActionsCard, build, _carbonBg (+35 more)

### Community 19 - "wardrobe_settings_provider.dart"
Cohesion: 0.05
Nodes (38): EstacionActiva get, EstiloPrincipal get, activa, CategoriaArmario, categoriaEmojiOptions, copyWith, defaultCategorias, defaultReglas (+30 more)

### Community 20 - "outfit_screen.dart"
Cohesion: 0.05
Nodes (36): dart:ui, _addCustomOutfit, _aiError, _aiLoading, _aiOutfits, _blob, bottoms, _buildQuickOutfits (+28 more)

### Community 21 - "garment_autocrop_service.dart"
Cohesion: 0.06
Nodes (32): image_storage.dart, _byName, entryFor, family, GarmentColorEntry, garmentColorOptions, GarmentPalette, isAchromatic (+24 more)

### Community 22 - "StatelessWidget"
Cohesion: 0.07
Nodes (30): _AutoDetectedCard, _ChipShimmer, _EditableAiChip, _FavoriteChip, _FieldLabel, _ImagePickerCard, _StyleTipCard, _UserFieldsCard (+22 more)

### Community 23 - "image_compositor.dart"
Cohesion: 0.07
Nodes (29): alphaPixel, alphaSource, applyCutoutAlpha, argb, backgroundColorArgb, bgB, bgG, bgR (+21 more)

### Community 24 - "profile_sheet.dart"
Cohesion: 0.07
Nodes (28): api_key_dialog.dart, _ApiKeyCard, color, _exportWardrobe, garmentCount, hasCustomKey, icon, label (+20 more)

### Community 25 - "home_screen.dart"
Cohesion: 0.08
Nodes (23): add_garment_screen.dart, garment_detail_screen.dart, _CategoryChip, createState, _EmptyWardrobeCard, garment, _GarmentCard, garmentCount (+15 more)

### Community 26 - "outfit_flat_lay_view_test.dart"
Cohesion: 0.09
Nodes (22): Directory, package:armario_virtual/theme/app_palette.dart, package:armario_virtual/widgets/outfit_flat_lay_view.dart, required int expectedImages,
  int, _allImagesDecoded, dir, elements, _fastFail (+14 more)

### Community 27 - "api_key_dialog.dart"
Cohesion: 0.11
Nodes (18): ApiKeyDialog, _ApiKeyDialogState, build, child, _controller, createState, dispose, _error (+10 more)

### Community 28 - "shimmer_box.dart"
Cohesion: 0.12
Nodes (16): AnimationController, BorderRadius, double?, baseColor, borderRadius, build, _controller, createState (+8 more)

### Community 29 - "gemini_outfit_service.dart"
Cohesion: 0.12
Nodes (16): api_key_service.dart, geminiModelName, GeminiOutfitService, generateText, generateTextFromImage, hasSharedKey, _isValidApiKey, _loadModel (+8 more)

### Community 30 - "WardrobeProvider"
Cohesion: 0.14
Nodes (16): WardrobeProvider, _save, _generateAi, build, _confirmDelete, garment, GarmentDetailScreen, build (+8 more)

### Community 31 - "app_palette.dart"
Cohesion: 0.12
Nodes (16): cardBeige, cardElevation, cardHairlineColor, chipBeige, chipBeigeBorder, copyWith, dark, favoritePinkBg (+8 more)

### Community 32 - "State"
Cohesion: 0.17
Nodes (16): MainNavigation, _MainNavigationState, AddGarmentScreen, _AddGarmentScreenState, _AssignmentSheet, _AssignmentSheetState, CalendarScreen, _CalendarScreenState (+8 more)

### Community 33 - "background_removal_service.dart"
Cohesion: 0.13
Nodes (14): BackgroundRemovalService, _iosChannel, isSupported, _matchSize, _processWithRetry, removeBackground, _removeBackgroundAndroid, _removeBackgroundIOS (+6 more)

### Community 34 - "pressable_scale.dart"
Cohesion: 0.14
Nodes (13): build, child, createState, enableHaptics, _handleTap, haptic, onTap, _pressed (+5 more)

### Community 35 - "garment_image.dart"
Cohesion: 0.17
Nodes (11): BoxFit, build, _buildImage, _decodeDataUrl, _errorBuilder, _ErrorPlaceholder, fit, _frameBuilder (+3 more)

### Community 36 - "outfit_flat_lay_view.dart"
Cohesion: 0.17
Nodes (11): _AutocroppedGarment, _bandFor, build, _FlatLayBand, _FlatLayBandRow, gap, garments, imagePath (+3 more)

### Community 37 - "outfit_plan_provider.dart"
Cohesion: 0.18
Nodes (10): bool get, assignOutfit, _isLoading, _loadPlans, _persist, planForDate, _plans, removeAssignment (+2 more)

### Community 38 - "BackgroundRemovalPlugin"
Cohesion: 0.25
Nodes (8): CGImagePropertyOrientation, FlutterMethodCall, FlutterPlugin, FlutterResult, BackgroundRemovalPlugin, String, NSObject, UIImage

### Community 39 - "category_badge.dart"
Cohesion: 0.18
Nodes (10): Color?, background, build, category, CategoryBadge, foreground, icon, iconForCategory (+2 more)

### Community 40 - "BackgroundRemovalPlugin.swift"
Cohesion: 0.24
Nodes (7): CoreImage, Flutter, FlutterSceneDelegate, SceneDelegate, UIKit, Vision, XCTest

### Community 41 - "List"
Cohesion: 0.18
Nodes (10): DateTime, createdAt, date, fromJson, garmentIds, id, occasion, PlannedOutfit (+2 more)

### Community 42 - "color_extraction_test.dart"
Cohesion: 0.18
Nodes (10): Exception, package:armario_virtual/models/garment.dart, package:armario_virtual/models/garment_options.dart, package:armario_virtual/services/color_extraction_service.dart, alpha, _extract, extractGarmentColor, _fillRect (+2 more)

### Community 43 - "ApiKeyProvider"
Cohesion: 0.22
Nodes (10): ChangeNotifier, _App, build, ApiKeyProvider, ThemeModeProvider, UserProfileProvider, _validateAndSave, _editName (+2 more)

### Community 44 - "FlutterMacOS"
Cohesion: 0.24
Nodes (5): Cocoa, FlutterMacOS, RunnerTests, RunnerTests, XCTestCase

### Community 45 - "empty_state.dart"
Cohesion: 0.20
Nodes (9): IconData, AppEmptyState, build, ctaIcon, ctaLabel, icon, onCta, subtitle (+1 more)

### Community 46 - "image_enhancer.dart"
Cohesion: 0.20
Nodes (9): adjusted, decoded, downscaleForAiPayload, enhanceGarmentPhoto, fromList, longestSide, resized, sharpened (+1 more)

### Community 47 - "ai_outfit_card.dart"
Cohesion: 0.22
Nodes (8): garment_image.dart, OutfitRecommendation, AiOutfitCard, build, onTap, outfit, ../services/outfit_recommendation_service.dart, VoidCallback?

### Community 48 - "package:flutter/foundation.dart"
Cohesion: 0.22
Nodes (8): _customApiKey, hasCustomKey, _isLoading, _load, validateAndSave, package:flutter/foundation.dart, ../services/api_key_service.dart, ../services/gemini_outfit_service.dart

### Community 49 - "package:flutter/material.dart"
Cohesion: 0.22
Nodes (7): AppSnackBar, AppSnackBarType, show, build, score, VersatilityBadge, package:flutter/material.dart

### Community 50 - "OutfitPlanProvider"
Cohesion: 0.29
Nodes (8): OutfitPlanProvider, _assignFromAi, build, _remove, _saveManual, build, build, MaterialPageRoute

### Community 51 - "theme_mode_provider.dart"
Cohesion: 0.25
Nodes (7): _load, setThemeMode, _storageKey, _themeMode, static const, ThemeMode, ThemeMode get

### Community 52 - "api_key_service.dart"
Cohesion: 0.25
Nodes (7): ApiKeyService, clearCustomApiKey, getCustomApiKey, _key, setCustomApiKey, _storage, package:flutter_secure_storage/flutter_secure_storage.dart

### Community 53 - "package:image/image.dart"
Cohesion: 0.25
Nodes (7): package:armario_virtual/services/image_compositor.dart, package:image/image.dart, return, _encode, _enhancedPhoto, image, main

### Community 54 - "dart:convert"
Cohesion: 0.29
Nodes (6): dart:convert, dart:io, ImageStorage, persist, readBytes, package:path_provider/path_provider.dart

### Community 55 - "dart:typed_data"
Cohesion: 0.29
Nodes (6): dart:typed_data, package:armario_virtual/services/garment_autocrop_service.dart, fromList, image, main, _pngWithOpaqueRect

### Community 56 - "user_profile_provider.dart"
Cohesion: 0.29
Nodes (6): defaultName, _load, _name, setName, _storageKey, String get

### Community 57 - "AppDelegate"
Cohesion: 0.47
Nodes (4): FlutterAppDelegate, AppDelegate, Bool, NSApplication

### Community 58 - "outfit_filters.dart"
Cohesion: 0.60
Nodes (4): OutfitOccasion, OutfitOccasionLabel, WeatherCondition, WeatherConditionLabel

### Community 59 - "package:shared_preferences/shared_preferences.dart"
Cohesion: 0.40
Nodes (4): package:armario_virtual/main.dart, package:flutter_test/flutter_test.dart, package:shared_preferences/shared_preferences.dart, main

## Knowledge Gaps
- **728 isolated node(s):** `Vision`, `CoreImage`, `_Palette`, `ivory`, `ivoryDim` (+723 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `WardrobeProvider` connect `WardrobeProvider` to `State`, `add_garment_screen.dart`, `wardrobe_provider.dart`, `ApiKeyProvider`, `calendar_screen.dart`, `OutfitPlanProvider`, `wardrobe_settings_screen.dart`, `outfit_screen.dart`, `profile_sheet.dart`, `home_screen.dart`?**
  _High betweenness centrality (0.029) - this node is a cross-community bridge._
- **Why does `OutfitOccasion` connect `outfit_filters.dart` to `calendar_screen.dart`, `outfit_screen.dart`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Why does `Garment` connect `garment.dart` to `calendar_screen.dart`, `outfit_screen.dart`, `WardrobeProvider`, `home_screen.dart`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **What connects `Vision`, `CoreImage`, `_Palette` to the rest of the system?**
  _728 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Win32Window` be split into smaller, more focused modules?**
  _Cohesion score 0.0597567424643046 - nodes in this community are weakly interconnected._
- **Should `add_garment_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.024691358024691357 - nodes in this community are weakly interconnected._
- **Should `outfit_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.06666666666666667 - nodes in this community are weakly interconnected._