import AppKit
import Foundation

/// Keeps one Finder Quick Action per enabled pane in `~/Library/Services`, so
/// right-clicking a file offers Quick Actions ▸ "Upload to Loft (1 Day)".
///
/// A Quick Action is an Automator `.workflow` bundle: an Info.plist that
/// registers it as a service, plus a `document.wflow` holding one "Run Shell
/// Script" action. That script hands the selected paths to Loft through the
/// `loft://upload` scheme (see ``UploadURL``). Generating the bundles at
/// runtime is what lets the menu follow the pane names and order from
/// Settings; a static `NSServices` entry in Loft's own Info.plist cannot.
///
/// Bundles Loft wrote are recognised by the `LoftPaneID` key in their
/// Info.plist, so a sync never touches workflows the user made themselves.
enum FinderQuickActions {
    static let paneIDKey = "LoftPaneID"
    static let workflowExtension = "workflow"

    static var servicesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true)
    }

    /// Adds, rewrites and removes bundles until `directory` holds exactly one
    /// per enabled pane. Pass an empty array to uninstall everything Loft wrote.
    /// Returns true when anything on disk changed.
    @discardableResult
    static func sync(panes: [Pane],
                     directory: URL = servicesDirectory,
                     notifySystem: Bool = true) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var installed = installedBundles(in: directory)
        var changed = false
        var taken: Set<String> = []

        for pane in panes.filter(\.enabled).sorted(by: { $0.order < $1.order }) {
            let name = bundleName(for: pane, taken: taken)
            taken.insert(name)
            let bundle = directory.appendingPathComponent(name, isDirectory: true)

            // Same directory, so the name is the identity; the URLs themselves
            // differ in symlink resolution (/var vs /private/var).
            if let previous = installed.removeValue(forKey: pane.id),
               previous.lastPathComponent != bundle.lastPathComponent {
                try? fm.removeItem(at: previous)
                changed = true
            }
            if write(pane: pane, to: bundle) { changed = true }
        }

        for stale in installed.values {
            try? fm.removeItem(at: stale)
            changed = true
        }

        if changed && notifySystem {
            NSUpdateDynamicServices()
        }
        return changed
    }

    /// Bundles in `directory` that Loft generated, keyed by pane id.
    static func installedBundles(in directory: URL) -> [UUID: URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles]) else {
            return [:]
        }
        var result: [UUID: URL] = [:]
        for entry in entries where entry.pathExtension == workflowExtension {
            let plist = entry.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let raw = dict[paneIDKey] as? String,
                  let id = UUID(uuidString: raw) else { continue }
            result[id] = entry
        }
        return result
    }

    static func title(for pane: Pane) -> String {
        "Upload to Loft (\(pane.name))"
    }

    /// File name for the bundle. Finder forbids ":" and "/" in names, and two
    /// panes may share a name, so collisions get the pane's position appended.
    static func bundleName(for pane: Pane, taken: Set<String>) -> String {
        let safe = title(for: pane)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        var name = "\(safe).\(workflowExtension)"
        if taken.contains(name) {
            name = "\(safe) \(pane.order + 1).\(workflowExtension)"
        }
        return name
    }

    /// The zsh one-liner the Quick Action runs with the selected paths as
    /// arguments. Paths are hex-encoded with `od` (always present on macOS) and
    /// sent in batches so a large selection never produces a URL `open` would
    /// choke on.
    static func script(for pane: Pane) -> String {
        let base = "\(UploadURL.scheme)://\(UploadURL.host)?pane=\(pane.id.uuidString)"
        return """
        q=""; n=0
        for f in "$@"; do
          q="$q&f=$(printf '%s' "$f" | od -An -v -tx1 | tr -d ' \\n')"; n=$((n+1))
          if [ $n -ge 40 ]; then open "\(base)$q"; q=""; n=0; fi
        done
        [ -n "$q" ] && open "\(base)$q"
        exit 0
        """
    }

    static func infoPlist(for pane: Pane) -> [String: Any] {
        [
            "CFBundleIdentifier": "com.weteling.loft.quickaction.\(pane.id.uuidString.lowercased())",
            "CFBundleName": title(for: pane),
            "CFBundleShortVersionString": "1.0",
            paneIDKey: pane.id.uuidString,
            "NSServices": [[
                "NSBackgroundColorName": "background",
                "NSIconName": "NSActionTemplate",
                "NSMenuItem": ["default": title(for: pane)],
                "NSMessage": "runWorkflowAsService",
                "NSRequiredContext": ["NSApplicationIdentifier": "com.apple.finder"],
                "NSSendFileTypes": ["public.item"]
            ]]
        ]
    }

    /// The Automator document: one "Run Shell Script" action, files passed as
    /// arguments. Mirrors what Automator itself writes for a Quick Action, with
    /// the editor-only metadata trimmed to what the workflow runner reads.
    static func workflowDocument(for pane: Pane) -> [String: Any] {
        let parameter: (String, Any) -> [String: Any] = { name, defaultValue in
            ["default value": defaultValue, "name": name, "required": "0", "type": "0", "uuid": "0"]
        }
        return [
            "AMApplicationBuild": "534",
            "AMApplicationVersion": "2.10",
            "AMDocumentVersion": "2",
            "actions": [[
                "action": [
                    "AMAccepts": ["Container": "List", "Optional": true,
                                  "Types": ["com.apple.cocoa.string"]],
                    "AMActionVersion": "2.0.3",
                    "AMApplication": ["Automator"],
                    "AMParameterProperties": [
                        "COMMAND_STRING": [:], "CheckedForUserDefaultShell": [:],
                        "inputMethod": [:], "shell": [:], "source": [:]
                    ],
                    "AMProvides": ["Container": "List", "Types": ["com.apple.cocoa.string"]],
                    "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
                    "ActionName": "Run Shell Script",
                    "ActionParameters": [
                        "COMMAND_STRING": script(for: pane),
                        "CheckedForUserDefaultShell": true,
                        "inputMethod": 1,
                        "shell": "/bin/zsh",
                        "source": ""
                    ],
                    "BundleIdentifier": "com.apple.RunShellScript",
                    "CFBundleVersion": "2.0.3",
                    "CanShowSelectedItemsWhenRun": false,
                    "CanShowWhenRun": true,
                    "Category": ["AMCategoryUtilities"],
                    "Class Name": "RunShellScriptAction",
                    "InputUUID": "6B7C0A2E-1F7A-4B7B-9C1D-2A0E5B7F3D01",
                    "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
                    "OutputUUID": "6B7C0A2E-1F7A-4B7B-9C1D-2A0E5B7F3D02",
                    "UUID": pane.id.uuidString,
                    "UnlocalizedApplications": ["Automator"],
                    "arguments": [
                        "0": parameter("inputMethod", 0),
                        "1": parameter("CheckedForUserDefaultShell", false),
                        "2": parameter("source", ""),
                        "3": parameter("COMMAND_STRING", ""),
                        "4": parameter("shell", "/bin/sh")
                    ],
                    "conversionLabel": 0,
                    "isViewVisible": 1,
                    "location": "309.000000:305.000000",
                    "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib"
                ],
                "isViewVisible": 1
            ]],
            "connectors": [:],
            "workflowMetaData": [
                "applicationBundleIDsByPath": [:],
                "applicationPaths": [],
                "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "outputTypeIdentifier": "com.apple.Automator.nothing",
                "presentationMode": 15,
                "processesInput": false,
                "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": false,
                "systemImageName": "NSActionTemplate",
                "useAutomaticInputType": false,
                "workflowTypeIdentifier": "com.apple.Automator.servicesMenu"
            ]
        ]
    }

    /// Writes the bundle if it is missing or its contents differ. Returns true
    /// when something was written.
    private static func write(pane: Pane, to bundle: URL) -> Bool {
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let files: [(URL, [String: Any])] = [
            (contents.appendingPathComponent("Info.plist"), infoPlist(for: pane)),
            (contents.appendingPathComponent("document.wflow"), workflowDocument(for: pane))
        ]
        var wrote = false
        for (url, plist) in files {
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                                  format: .xml,
                                                                  options: 0) else { continue }
            if let existing = try? Data(contentsOf: url), existing == data { continue }
            try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            if (try? data.write(to: url, options: .atomic)) != nil { wrote = true }
        }
        return wrote
    }
}
