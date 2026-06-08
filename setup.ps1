# setup.ps1

# --- SDL3 ---
if (!(Test-Path "SDL3.dll")) {
    Write-Host "ERROR: Place SDL3.dll in the project root" -ForegroundColor Red
    Write-Host "Download: https://github.com/libsdl-org/SDL/releases" -ForegroundColor Yellow
    exit 1
}

# --- SDL3_ttf ---
if (!(Test-Path "SDL3_ttf.dll")) {
    Write-Host "Downloading SDL3_ttf 3.2.2..."
    Invoke-WebRequest "https://github.com/libsdl-org/SDL_ttf/releases/download/release-3.2.2/SDL3_ttf-3.2.2-win32-x64.zip" -OutFile "sdl3_ttf.zip"
    Expand-Archive "sdl3_ttf.zip" -DestinationPath "sdl3_ttf_tmp"
    Copy-Item "sdl3_ttf_tmp\SDL3_ttf.dll" "SDL3_ttf.dll"
    Remove-Item "sdl3_ttf.zip"
    Remove-Item "sdl3_ttf_tmp" -Recurse
}

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