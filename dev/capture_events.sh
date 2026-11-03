
echo "Capturing events..."
timeout 15s libinput debug-events > /home/utilisateur/quickshell_todo/dev/tablet_events.log 2>&1
echo "Capture finished."
