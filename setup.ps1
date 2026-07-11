# setup.ps1

# --- curl ---
if (!(Test-Path "curl.dll")) {
    Write-Host "Downloading curl 8.14.0..."
    Invoke-WebRequest "https://curl.se/windows/dl-8.14.0_1/curl-8.14.0_1-win64-mingw.zip" -OutFile "curl.zip"
    Expand-Archive "curl.zip" -DestinationPath "curl_tmp"
    Copy-Item "curl_tmp\curl-8.14.0_1-win64-mingw\bin\libcurl-x64.dll" "curl.dll"
    Remove-Item "curl.zip"
    Remove-Item "curl_tmp" -Recurse
}

Write-Host "Done! Run 'odin run .' to start." -ForegroundColor Green