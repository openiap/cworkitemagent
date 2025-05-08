@echo off
echo Building OpenIAP client CLI for Windows

set OPENIAP_VERSION=0.0.38
set ARCH=x64

REM Create lib directory if it doesn't exist
if not exist lib mkdir lib

REM Check if we already have the header file
if not exist clib_openiap.h (
    echo Downloading C header file...
    powershell -Command "Invoke-WebRequest -Uri https://raw.githubusercontent.com/openiap/rustapi/refs/tags/%OPENIAP_VERSION%/crates/clib/clib_openiap.h -OutFile clib_openiap.h"
    if %ERRORLEVEL% neq 0 (
        echo Failed to download header file
        echo Please download manually from: https://raw.githubusercontent.com/openiap/rustapi/refs/tags/%OPENIAP_VERSION%/crates/clib/clib_openiap.h
        exit /b %ERRORLEVEL%
    )
) else (
    echo Header file already exists, skipping download.
)

REM Check if we already have the DLL
if not exist lib\openiap-windows-%ARCH%.dll (
    echo Downloading OpenIAP library...
    echo https://github.com/openiap/rustapi/releases/download/%OPENIAP_VERSION%/openiap-windows-%ARCH%.dll
    powershell -Command "Invoke-WebRequest -Uri https://github.com/openiap/rustapi/releases/download/%OPENIAP_VERSION%/openiap-windows-%ARCH%.dll -OutFile lib\openiap-windows-%ARCH%.dll -Headers @{'User-Agent'='Mozilla/5.0'}"
    if %ERRORLEVEL% neq 0 (
        echo Failed to download library
        echo Please download manually from: https://github.com/openiap/rustapi/releases/download/%OPENIAP_VERSION%/openiap-windows-%ARCH%.dll
        exit /b %ERRORLEVEL%
    )
) else (
    echo Library file already exists, skipping download.
)

REM Copy to the correct name for runtime loading
echo Copying to correct name for loader...
copy lib\openiap-windows-%ARCH%.dll openiap_clib.dll

REM Compile
echo Compiling...
gcc main.c -I. -L.\lib -lopeniap_clib -o workitem_client.exe

if %ERRORLEVEL% neq 0 (
    echo Build failed
    exit /b %ERRORLEVEL%
)

echo Build completed successfully
echo Run workitem_client.exe to start the application