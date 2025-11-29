[![Godot Asset Library](https://img.shields.io/badge/Godot%20Asset-Library-478cbf?style=for-the-badge&logo=godot-engine)](https://godotengine.org/asset-library/asset/4500)

# Godot Context Exporter

Godot 4 plugin that exports selected GDScript files, Scene trees, and Project Settings into a single text file or clipboard.

**Primary Use Case:** Quickly gathering project context to share with LLMs or for documentation.

## Features
*   📂 **Scripts:** Batch export `.gd` or `.cs` files (optionally grouped by folder).
*   🌳 **Scenes:** Text-based visualization of Scene trees (includes Nodes, Signals, Groups, and Inspector changes).
*   ⚙️ **Settings:** Includes `project.godot`, Autoloads (Globals), and cleaned-up Input Map.
*   🤖 **LLM Ready:** Optional Markdown formatting (code blocks) for better parsing by AI.
*   📋 **Output:** Copy directly to Clipboard or save to `res://context_exporter.txt`.

## Installation
1. Copy the folder containing this plugin into your project's `addons/` directory.
2. Go to **Project → Project Settings → Plugins** and enable **Godot Context Exporter**.

## Usage
Click on button in top right corner of editor  
*(you can hide this button in Advanced Settings)*
### Or
Navigate to **Project → Tools → Context Exporter...**

## License
MIT
