# setup.ps1

# SDL3
if (!(Test-Path "SDL3.dll")) {
    Write-Host "Copying SDL3.dll..."
    Copy-Item "C:\Program Files\SDL3\lib\SDL3.dll" "SDL3.dll"
}

# curl
if (!(Test-Path "curl.dll")) {
    Write-Host "Downloading curl..."
    Invoke-WebRequest "https://curl.se/windows/dl-8.14.0_1/curl-8.14.0_1-win64-mingw.zip" -OutFile "curl.zip"
    Expand-Archive "curl.zip" -DestinationPath "curl_tmp"
    Copy-Item "curl_tmp\curl-8.14.0_1-win64-mingw\bin\libcurl-x64.dll" "curl.dll"
    Remove-Item "curl.zip"
    Remove-Item "curl_tmp" -Recurse
}

Write-Host "Done! Run 'odin run .' to start."s