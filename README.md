# Godot Text Snapshot
![Screenshot](visuals/2.png)

Godot 4 plugin that exports selected GDScript files, Scene trees, and Project Settings into a single text file or clipboard.

**Primary Use Case:** Quickly gathering project context to share with LLMs or for documentation.

## Features
*   📂 **Scripts:** Batch export `.gd` files (optionally grouped by folder).
*   🌳 **Scenes:** Text-based visualization of Scene trees (includes Nodes, Signals, Groups, and Inspector changes).
*   ⚙️ **Settings:** Includes `project.godot`, Autoloads (Globals), and cleaned-up Input Map.
*   🤖 **LLM Ready:** Optional Markdown formatting (code blocks) for better parsing by AI.
*   📋 **Output:** Copy directly to Clipboard or save to `res://text_snapshot.txt`.

## Installation
1. Copy the folder containing this plugin into your project's `addons/` directory.
2. Go to **Project → Project Settings → Plugins** and enable **Godot Text Snapshot**.

## Usage
1. Navigate to **Project → Tools → Text Snapshot...**
2. Select the scripts and scenes you want to include.
3. (Optional) Configure formatting in the footer (e.g., wrap in Markdown).
4. Click **Copy to Clipboard** or **Save to File**.

## License
MIT
