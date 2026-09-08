# Graph Report - .  (2026-08-09)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 266 nodes · 374 edges · 16 communities (14 shown, 2 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.8)
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

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 22 edges
2. `MessageHandler` - 12 edges
3. `WardrobeProvider` - 11 edges
4. `FlutterWindow` - 10 edges
5. `Create` - 10 edges
6. `WndProc` - 10 edges
7. `MessageHandler` - 9 edges
8. `_MyApplication` - 7 edges
9. `OnCreate` - 7 edges
10. `WindowClassRegistrar` - 7 edges

## Surprising Connections (you probably didn't know these)
- `OnCreate` --calls--> `RegisterPlugins()`  [INFERRED]
  windows/runner/flutter_window.h → windows/flutter/generated_plugin_registrant.cc
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `Win32Window::Win32Window()` --calls--> `Destroy`  [INFERRED]
  windows/runner/win32_window.cpp → windows/runner/win32_window.h
- `_save` --references--> `WardrobeProvider`  [EXTRACTED]
  lib/screens/add_garment_screen.dart → lib/providers/wardrobe_provider.dart
- `build` --references--> `WardrobeProvider`  [EXTRACTED]
  lib/screens/outfit_screen.dart → lib/providers/wardrobe_provider.dart

## Import Cycles
- None detected.

## Communities (16 total, 2 thin omitted)

### Community 0 - "Win32Window"
Cohesion: 0.07
Nodes (51): Point, RECT, Size, unique_ptr, DartProject, HWND, LPARAM, LRESULT (+43 more)

### Community 1 - "add_garment_screen.dart"
Cohesion: 0.07
Nodes (36): add_garment_screen.dart, ChangeNotifier, dart:io, File?, ImageSource, WardrobeProvider, AddGarmentScreen, _AddGarmentScreenState (+28 more)

### Community 2 - "outfit_screen.dart"
Cohesion: 0.06
Nodes (35): dart:math, ArmarioVirtualApp, build, createState, _currentIndex, main, MainNavigation, _MainNavigationState (+27 more)

### Community 3 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.09
Nodes (18): Cocoa, file_selector_macos, Flutter, FlutterMacOS, FlutterPluginRegistry, FlutterSceneDelegate, FlutterViewController, Foundation (+10 more)

### Community 4 - "my_application.cc"
Cohesion: 0.09
Nodes (22): FlPluginRegistry, FlView, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins() (+14 more)

### Community 5 - "garment.dart"
Cohesion: 0.14
Nodes (15): DateTime, category, color, copyWith, createdAt, fromJson, Garment, GarmentCategory (+7 more)

### Community 6 - "AppDelegate"
Cohesion: 0.16
Nodes (10): Any, FlutterAppDelegate, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, AppDelegate, Bool, AppDelegate, Bool (+2 more)

### Community 7 - "wardrobe_provider.dart"
Cohesion: 0.15
Nodes (12): dart:convert, addGarment, byCategory, _garments, _loadGarments, _persist, removeGarment, _storageKey (+4 more)

### Community 8 - "wWinMain"
Cohesion: 0.26
Nodes (9): _In_, _In_opt_, string, vector, wWinMain(), wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 9 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

## Knowledge Gaps
- **70 isolated node(s):** `_currentIndex`, `_screens`, `main`, `build`, `createState` (+65 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `FlutterWindow` connect `Win32Window` to `GeneratedPluginRegistrant.swift`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `MessageHandler` (e.g. with `Destroy` and `GetClientArea`) actually correct?**
  _`MessageHandler` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Create` (e.g. with `Destroy` and `UpdateTheme`) actually correct?**
  _`Create` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `_currentIndex`, `_screens`, `main` to the rest of the system?**
  _70 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Win32Window` be split into smaller, more focused modules?**
  _Cohesion score 0.06594071385359952 - nodes in this community are weakly interconnected._
- **Should `add_garment_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.06827880512091039 - nodes in this community are weakly interconnected._
- **Should `outfit_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.06116642958748222 - nodes in this community are weakly interconnected._