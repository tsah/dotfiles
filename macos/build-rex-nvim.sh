#!/bin/sh
# Build ~/Applications/Rex Nvim.app and make it the default app for text files.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
app="$HOME/Applications/Rex Nvim.app"
plist="$app/Contents/Info.plist"
mkdir -p "$HOME/Applications"
rm -rf "$app"
osacompile -o "$app" "$here/rex-nvim.applescript"
pb() { /usr/libexec/PlistBuddy -c "$1" "$plist"; }
pb "Delete :CFBundleIdentifier" 2>/dev/null || true
pb "Delete :CFBundleDocumentTypes" 2>/dev/null || true
# Content types it becomes the default for. Specific types (JSON, Python...) do
# not inherit a default set on public.plain-text, so each is listed.
types="public.plain-text public.text public.source-code public.script
public.shell-script public.bash-script public.zsh-script public.python-script
public.ruby-script public.perl-script public.php-script public.json public.yaml
public.xml public.comma-separated-values-text public.tab-separated-values-text
public.log com.apple.log com.apple.property-list public.c-source
public.c-header public.c-plus-plus-source public.c-plus-plus-header
public.objective-c-source public.swift-source com.sun.java-source
com.netscape.javascript-source public.css
net.daringfireball.markdown public.make-source public.patch-file"
# Text formats macOS has no type for; the app declares them (UTImportedTypeDeclarations).
# id:extension. .ts is left out: macOS already maps it to MPEG-2 video.
imported="org.rust-lang.rust-source:rs org.golang.go-source:go org.toml.toml:toml
org.lua.lua-script:lua dev.tsah.typescript-jsx:tsx dev.tsah.javascript-jsx:jsx
dev.tsah.ini:ini dev.tsah.nix:nix dev.tsah.hcl:tf dev.tsah.kotlin:kt
dev.tsah.scala:scala dev.tsah.gradle:gradle"
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleIdentifier string dev.tsah.rex-nvim" \
  -c "Add :LSUIElement bool true" \
  -c "Add :CFBundleDocumentTypes array" \
  -c "Add :CFBundleDocumentTypes:0 dict" \
  -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Text" \
  -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" \
  -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" \
  -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" \
  "$plist"
pb "Add :UTImportedTypeDeclarations array"
i=0
for entry in $imported; do
  id=${entry%%:*}
  pb "Add :UTImportedTypeDeclarations:$i dict"
  pb "Add :UTImportedTypeDeclarations:$i:UTTypeIdentifier string $id"
  pb "Add :UTImportedTypeDeclarations:$i:UTTypeDescription string ${entry##*:} source"
  pb "Add :UTImportedTypeDeclarations:$i:UTTypeConformsTo array"
  pb "Add :UTImportedTypeDeclarations:$i:UTTypeConformsTo:0 string public.source-code"
  pb "Add :UTImportedTypeDeclarations:$i:UTTypeTagSpecification dict"
  pb "Add :UTImportedTypeDeclarations:$i:UTTypeTagSpecification:public.filename-extension array"
  pb "Add :UTImportedTypeDeclarations:$i:UTTypeTagSpecification:public.filename-extension:0 string ${entry##*:}"
  types="$types $id"
  i=$((i + 1))
done
i=0
for t in $types; do
  pb "Add :CFBundleDocumentTypes:0:LSItemContentTypes:$i string $t"
  i=$((i + 1))
done
codesign --force --deep -s - "$app" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
swift - "$app" $types <<'SWIFT'
import AppKit
import UniformTypeIdentifiers
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
var failed: [String] = []
for id in args.dropFirst(2) {
    guard let type = UTType(id) else { failed.append("\(id) (unknown type)"); continue }
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type) { error in
        if error != nil { failed.append(id) }
        done.signal()
    }
    _ = done.wait(timeout: .now() + 10)
}
print("Rex Nvim is the default for \(args.count - 2 - failed.count) text types")
if !failed.isEmpty { print("not set: \(failed.joined(separator: ", "))") }
SWIFT
