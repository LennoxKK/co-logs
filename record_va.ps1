# Set the output file names
$VIDEO_FILE = "/sdcard/video.mp4"
$AUDIO_FILE = "/sdcard/audio.wav"
$LOCAL_VIDEO = "video.mp4"
$LOCAL_AUDIO = "audio.wav"
$FINAL_OUTPUT = "output.mp4"

# Step 1: Start the screen recording in a new PowerShell window
Start-Process powershell -ArgumentList "-NoExit", "-Command", "adb shell screenrecord $VIDEO_FILE"

# Step 2: Start the audio recording in a new PowerShell window
Start-Process powershell -ArgumentList "-NoExit", "-Command", "adb shell arecord -f cd -t wav $AUDIO_FILE"

# Step 3: Wait a few seconds to give the user time to start both recordings
Write-Host "Starting screen and audio recording... Please wait a few seconds."
Start-Sleep -Seconds 5

# Step 4: Notify user to start recording and wait for user input
Write-Host "Both screen and audio recording should now be running."
Write-Host "Press ENTER when you're ready to stop the recording."
Read-Host "Press ENTER when ready to pull the files..."

# Step 5: Pull the video and audio files from the device
Write-Host "Pulling video and audio files from device..."
adb pull $VIDEO_FILE $LOCAL_VIDEO
adb pull $AUDIO_FILE $LOCAL_AUDIO

# Step 6: Combine the video and audio using ffmpeg
Write-Host "Combining video and audio..."
& ffmpeg -i $LOCAL_VIDEO -i $LOCAL_AUDIO -c:v copy -c:a aac -strict experimental $FINAL_OUTPUT

# Step 7: Notify user of completion
Write-Host "Recording and combination complete. Final output: $FINAL_OUTPUT"
