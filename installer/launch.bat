@echo off
title VoiceSyntesis
cd /d "%~dp0"
powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Normal -File "%~dp0start_app.ps1"
