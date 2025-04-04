adb shell dumpsys window | Select-String "mCurrentFocus" | ForEach-Object { $_ -replace ".*u0 (.*)\/.*", '$1' }
