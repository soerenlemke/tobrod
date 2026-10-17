# setup.ps1

# --- curl (built from source via git submodule) ---
if (!(Test-Path "vendor\curl-src\build\lib\Release\libcurl.lib")) {
    Write-Host "Initializing curl submodule..."
    git submodule update --init --recursive vendor/curl-src

    Write-Host "Building curl (this takes a few minutes)..."
    Push-Location vendor\curl-src
    cmake -B build -G "Visual Studio 18 2026" -A x64 `
        -DBUILD_SHARED_LIBS=OFF `
        -DCURL_USE_SCHANNEL=ON `
        -DCURL_USE_LIBPSL=OFF `
        -DCMAKE_MSVC_RUNTIME_LIBRARY="MultiThreadedDLL" `
        -DBUILD_CURL_EXE=OFF
    cmake --build build --config Release
    Pop-Location
} else {
    Write-Host "curl already built, skipping."
}

# --- lexbor (built from source via git submodule) ---
if (!(Test-Path "vendor\lexbor-src\build\Release\lexbor_static.lib")) {
    Write-Host "Initializing lexbor submodule..."
    git submodule update --init vendor/lexbor-src

    Write-Host "Building lexbor..."
    Push-Location vendor\lexbor-src
    # Static only, and the same /MD CRT as curl and raylib so the linker doesn't complain.
    cmake -B build -G "Visual Studio 18 2026" -A x64 `
        -DLEXBOR_BUILD_SHARED=OFF `
        -DLEXBOR_BUILD_STATIC=ON `
        -DCMAKE_MSVC_RUNTIME_LIBRARY="MultiThreadedDLL"
    cmake --build build --config Release
    Pop-Location
} else {
    Write-Host "lexbor already built, skipping."
}

Write-Host "Done! Run 'odin run .' to start." -ForegroundColor Green
