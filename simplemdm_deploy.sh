#!/bin/bash
PKG_URL="https://github.com/hcyildirim/SHFTScreenSaver/releases/download/v3.2/SHFTScreenSaver.pkg"
PKG_PATH="/tmp/SHFTScreenSaver.pkg"

# Download and install
curl -sL -o "$PKG_PATH" "$PKG_URL"
installer -pkg "$PKG_PATH" -target /
rm -f "$PKG_PATH"

# Remove quarantine and whitelist
xattr -dr com.apple.quarantine /Library/Screen\ Savers/SHFTScreenSaver.saver 2>/dev/null
spctl --add /Library/Screen\ Savers/SHFTScreenSaver.saver 2>/dev/null

# Kill cached processes so new binary loads
killall legacyScreenSaver 2>/dev/null
killall ScreenSaverEngine 2>/dev/null

# Set SHFT Screen Saver as active for all users
for USER_HOME in /Users/*/; do
    USERNAME=$(basename "$USER_HOME")
    if [ "$USERNAME" = "Shared" ] || [ "$USERNAME" = "Guest" ]; then continue; fi
    id -u "$USERNAME" &>/dev/null || continue

    # Set ByHost screensaver preferences
    sudo -u "$USERNAME" defaults -currentHost write com.apple.screensaver moduleDict -dict moduleName "SHFTScreenSaver" path "/Library/Screen Savers/SHFTScreenSaver.saver" type -int 0
    sudo -u "$USERNAME" defaults -currentHost write com.apple.screensaver PrefsVersion -int 100
    sudo -u "$USERNAME" defaults -currentHost write com.apple.screensaver idleTime -int 300
    sudo -u "$USERNAME" defaults -currentHost write com.apple.screensaver CleanExit -int 1

    # Flush preferences cache
    sudo -u "$USERNAME" killall cfprefsd 2>/dev/null

    # Update wallpaper store
    STORE_DIR="${USER_HOME}Library/Application Support/com.apple.wallpaper/Store"
    STORE_FILE="$STORE_DIR/Index.plist"
    sudo -u "$USERNAME" mkdir -p "$STORE_DIR"

    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Freeze WallpaperAgent so it can't overwrite our plist
    WAPID=$(sudo -u "$USERNAME" pgrep -x WallpaperAgent 2>/dev/null)
    if [ -n "$WAPID" ]; then
        kill -STOP "$WAPID" 2>/dev/null
    fi

    # Write wallpaper store plist
    cat > "$STORE_FILE" << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AllSpacesAndDisplays</key>
	<dict>
		<key>Type</key>
		<string>individual</string>
		<key>Desktop</key>
		<dict>
			<key>Content</key>
			<dict>
				<key>Choices</key>
				<array>
					<dict>
						<key>Configuration</key>
						<data></data>
						<key>Files</key>
						<array/>
						<key>Provider</key>
						<string>default</string>
					</dict>
				</array>
				<key>EncodedOptionValues</key>
				<data>YnBsaXN0MDDRAQJWdmFsdWVz0AgLEgAAAAAAAAEBAAAAAAAAAAMAAAAAAAAAAAAAAAAAAAAT</data>
				<key>Shuffle</key>
				<string>\$null</string>
			</dict>
			<key>LastSet</key>
			<date>$NOW</date>
			<key>LastUse</key>
			<date>$NOW</date>
		</dict>
		<key>Idle</key>
		<dict>
			<key>Content</key>
			<dict>
				<key>Choices</key>
				<array>
					<dict>
						<key>Configuration</key>
						<data>YnBsaXN0MDDRAQJWbW9kdWxl0QMEWHJlbGF0aXZlXxA1ZmlsZTovLy9MaWJyYXJ5L1NjcmVlbiUyMFNhdmVycy9TSEZUU2NyZWVuU2F2ZXIuc2F2ZXIICxIVHgAAAAAAAAEBAAAAAAAAAAUAAAAAAAAAAAAAAAAAAABW</data>
						<key>Files</key>
						<array/>
						<key>Provider</key>
						<string>com.apple.wallpaper.choice.screen-saver</string>
					</dict>
				</array>
				<key>EncodedOptionValues</key>
				<data>YnBsaXN0MDDRAQJWdmFsdWVz0AgLEgAAAAAAAAEBAAAAAAAAAAMAAAAAAAAAAAAAAAAAAAAT</data>
				<key>Shuffle</key>
				<string>\$null</string>
			</dict>
			<key>LastSet</key>
			<date>$NOW</date>
			<key>LastUse</key>
			<date>$NOW</date>
		</dict>
	</dict>
	<key>Displays</key>
	<dict/>
	<key>Spaces</key>
	<dict/>
	<key>SystemDefault</key>
	<dict>
		<key>Type</key>
		<string>individual</string>
		<key>Desktop</key>
		<dict>
			<key>Content</key>
			<dict>
				<key>Choices</key>
				<array>
					<dict>
						<key>Configuration</key>
						<data></data>
						<key>Files</key>
						<array/>
						<key>Provider</key>
						<string>default</string>
					</dict>
				</array>
				<key>EncodedOptionValues</key>
				<data>YnBsaXN0MDDRAQJWdmFsdWVz0AgLEgAAAAAAAAEBAAAAAAAAAAMAAAAAAAAAAAAAAAAAAAAT</data>
				<key>Shuffle</key>
				<string>\$null</string>
			</dict>
			<key>LastSet</key>
			<date>$NOW</date>
			<key>LastUse</key>
			<date>$NOW</date>
		</dict>
		<key>Idle</key>
		<dict>
			<key>Content</key>
			<dict>
				<key>Choices</key>
				<array>
					<dict>
						<key>Configuration</key>
						<data>YnBsaXN0MDDRAQJWbW9kdWxl0QMEWHJlbGF0aXZlXxA1ZmlsZTovLy9MaWJyYXJ5L1NjcmVlbiUyMFNhdmVycy9TSEZUU2NyZWVuU2F2ZXIuc2F2ZXIICxIVHgAAAAAAAAEBAAAAAAAAAAUAAAAAAAAAAAAAAAAAAABW</data>
						<key>Files</key>
						<array/>
						<key>Provider</key>
						<string>com.apple.wallpaper.choice.screen-saver</string>
					</dict>
				</array>
				<key>EncodedOptionValues</key>
				<data>YnBsaXN0MDDRAQJWdmFsdWVz0AgLEgAAAAAAAAEBAAAAAAAAAAMAAAAAAAAAAAAAAAAAAAAT</data>
				<key>Shuffle</key>
				<string>\$null</string>
			</dict>
			<key>LastSet</key>
			<date>$NOW</date>
			<key>LastUse</key>
			<date>$NOW</date>
		</dict>
	</dict>
</dict>
</plist>
XMLEOF

    # Convert to binary and fix ownership
    plutil -convert binary1 "$STORE_FILE"
    chown "$USERNAME:staff" "$STORE_FILE"

    # Kill frozen WallpaperAgent - launchd restarts it with our new plist
    if [ -n "$WAPID" ]; then
        kill -9 "$WAPID" 2>/dev/null
    fi

    # Install LaunchAgent to clean up stale legacyScreenSaver process
    # legacyScreenSaver never exits on its own - accumulates ~15MB per start/stop cycle
    # This agent kills it when user is active (idle<30s) and ScreenSaverEngine is gone
    AGENT_DIR="${USER_HOME}Library/LaunchAgents"
    AGENT_FILE="$AGENT_DIR/com.shft.screensaver.cleanup.plist"
    sudo -u "$USERNAME" mkdir -p "$AGENT_DIR"
    sudo -u "$USERNAME" launchctl unload "$AGENT_FILE" 2>/dev/null
    cat > "$AGENT_FILE" << 'AGENTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.shft.screensaver.cleanup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>IDLE=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print $NF; exit}'); IDLE_SEC=$((IDLE / 1000000000)); [ "$IDLE_SEC" -gt 30 ] &amp;&amp; exit 0; pgrep -x legacyScreenSaver &gt;/dev/null &amp;&amp; ! pgrep -x ScreenSaverEngine &gt;/dev/null &amp;&amp; killall legacyScreenSaver 2&gt;/dev/null; exit 0</string>
    </array>
    <key>StartInterval</key>
    <integer>5</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
AGENTEOF
    chown "$USERNAME:staff" "$AGENT_FILE"
    sudo -u "$USERNAME" launchctl load "$AGENT_FILE" 2>/dev/null

    echo "Screen saver set for user: $USERNAME"
done
echo "SHFT Screen Saver v3.2 installed and activated for all users"
