#!/usr/bin/env bash
# Cut a Diktilo release: bump version, build + notarize the universal DMG,
# sign it for Sparkle, add it to appcast.xml, then (after an explicit "yes")
# push, create the GitHub Release and publish the appcast.
#
#   Scripts/release.sh <version> <notes-file>
#
# <notes-file>: plain text, one change per line starting with "- ". Used both
# for the GitHub Release body and the Sparkle "What's new" HTML.
#
# Run directly in Terminal.app on the Mac (notarytool needs the GUI-unlocked
# login keychain), on a clean `main` checkout. gh is not logged in on the Mac,
# so the GitHub Release is created over ssh from the Linux host, which also
# hosts the appcast (~/www/sypian.ski/diktilo/appcast.xml).
#
# That host is not named here, to keep this public repo free of private
# infrastructure. Set it either in your shell (`export DIKTILO_VPS=<ssh-host>`)
# or in Scripts/release.env, which is gitignored:
#
#   DIKTILO_VPS=<ssh-host>
set -euo pipefail

[ -f "$(dirname "$0")/release.env" ] && . "$(dirname "$0")/release.env"
VPS="${DIKTILO_VPS:?set DIKTILO_VPS (shell env or Scripts/release.env) to the ssh host that cuts the release}"
REPO=sypianski/diktilo
FEED_URL=https://sypian.ski/diktilo/appcast.xml
KEY_FILE="$HOME/.config/diktilo/sparkle_ed_private.txt"
SIGN_UPDATE=.dist-build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
PBXPROJ=VoiceInk.xcodeproj/project.pbxproj

die() { echo "Error: $*" >&2; exit 1; }

[ $# -eq 2 ] || die "usage: $0 <version> <notes-file>"
VERSION=$1
NOTES=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
cd "$(dirname "$0")/.."

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z, got '$VERSION'"
[ -s "$NOTES" ] || die "notes file '$NOTES' is empty or missing"
grep -q '^- ' "$NOTES" || die "notes file has no '- ' lines"
[ -s "$KEY_FILE" ] || die "Sparkle key $KEY_FILE missing (1Password: other → 'Diktilo Sparkle EdDSA key')"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "not on main"
[ -z "$(git status --porcelain)" ] || die "working tree not clean"
git fetch -q origin
[ -z "$(git rev-list HEAD..origin/main)" ] || die "origin/main has commits you don't have — pull first"
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && die "tag v$VERSION already exists"

CURRENT=$(awk -F ' = |;' '/MARKETING_VERSION = /{print $2; exit}' "$PBXPROJ")
python3 -c 'import sys; v=lambda s: tuple(map(int, s.split("."))); sys.exit(v(sys.argv[2]) <= v(sys.argv[1]))' \
    "$CURRENT" "$VERSION" || die "new version $VERSION must be greater than current $CURRENT"

echo "==> Bumping $CURRENT -> $VERSION"
sed -i '' "s/MARKETING_VERSION = $CURRENT;/MARKETING_VERSION = $VERSION;/" "$PBXPROJ"
git add "$PBXPROJ"
git commit -q -m "chore(release): wersja $VERSION"

echo "==> make dmg"
make dmg
BUILD=$(git rev-list --count HEAD)
DMG="dist/Diktilo-$VERSION-$BUILD.dmg"
[ -f "$DMG" ] || die "expected $DMG"

echo "==> make notarize"
make notarize DMG="$DMG"

echo "==> Signing for Sparkle"
SIG_ATTRS=$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" \
    .dist-build/Build/Products/Release/Diktilo.app/Contents/Info.plist)
DMG_URL="https://github.com/$REPO/releases/download/v$VERSION/Diktilo.dmg"

echo "==> Adding v$VERSION (build $BUILD) to appcast.xml"
python3 - "$VERSION" "$BUILD" "$MIN_OS" "$DMG_URL" "$SIG_ATTRS" "$NOTES" <<'PY'
import sys, html, email.utils
version, build, min_os, url, sig_attrs, notes = sys.argv[1:]
items = [l[2:].strip() for l in open(notes, encoding="utf-8") if l.startswith("- ")]
lis = "\n".join(f"                    <li>{html.escape(i)}</li>" for i in items)
item = f"""        <item>
            <title>{version}</title>
            <description><![CDATA[
                <ul>
{lis}
                </ul>
            ]]></description>
            <pubDate>{email.utils.formatdate(localtime=True)}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
            <enclosure url="{url}" {sig_attrs} type="application/octet-stream"/>
        </item>
"""
s = open("appcast.xml", encoding="utf-8").read()
anchor = s.find("        <item>")
if anchor < 0:
    anchor = s.index("    </channel>")
open("appcast.xml", "w", encoding="utf-8").write(s[:anchor] + item + s[anchor:])
PY
xmllint --noout appcast.xml || die "appcast.xml is not well-formed"
git add appcast.xml
git commit -q -m "chore(appcast): Diktilo $VERSION"

cat <<EOF

==================== READY TO PUBLISH ====================
Version:   $VERSION (build $BUILD, macOS $MIN_OS+)
DMG:       $DMG ($(du -h "$DMG" | cut -f1)) -> $DMG_URL
Commits:   $(git log --oneline origin/main..HEAD | wc -l | tr -d ' ') to push to origin/main
Notes:
$(cat "$NOTES")

This will:
  1. git push origin main + tag v$VERSION
  2. create GitHub Release v$VERSION on $REPO with Diktilo.dmg (via $VPS)
  3. publish appcast.xml to $FEED_URL  -> every installed Diktilo sees it
===========================================================
EOF
read -r -p "Publish? Type 'yes': " ANSWER
if [ "$ANSWER" != yes ]; then
    echo "Not published. Local commits stay; undo with: git reset --hard origin/main"
    exit 1
fi

echo "==> Pushing"
git tag "v$VERSION"
git push -q origin main "v$VERSION"

echo "==> Creating GitHub Release (via $VPS)"
STAGE="/tmp/diktilo-release-$VERSION"
ssh -n "$VPS" "rm -rf $STAGE && mkdir -p $STAGE"
scp -q "$DMG" "$VPS:$STAGE/Diktilo.dmg"
scp -q "$NOTES" "$VPS:$STAGE/notes.md"
ssh -n "$VPS" "gh release create v$VERSION $STAGE/Diktilo.dmg -R $REPO \
    --title 'Diktilo $VERSION' --notes-file $STAGE/notes.md --verify-tag && rm -rf $STAGE"

# Only after the DMG is downloadable — the feed must never point at a 404.
echo "==> Publishing appcast"
scp -q appcast.xml "$VPS:www/sypian.ski/diktilo/appcast.xml"

echo "==> Verifying"
curl -fsS "$FEED_URL" | xmllint --noout - || die "published feed is not valid XML"
curl -fsS "$FEED_URL" | grep -q "<sparkle:version>$BUILD</sparkle:version>" || die "feed lacks build $BUILD"
REMOTE_LEN=$(curl -fsSLI "$DMG_URL" | awk 'tolower($1)=="content-length:"{v=$2} END{print v}' | tr -d '\r')
LOCAL_LEN=$(stat -f %z "$DMG")
[ "$REMOTE_LEN" = "$LOCAL_LEN" ] || die "DMG size mismatch: remote $REMOTE_LEN, local $LOCAL_LEN"

echo ""
echo "Released Diktilo $VERSION. Pull on $VPS: cd ~/utensili/diktilo/macos && git pull"
