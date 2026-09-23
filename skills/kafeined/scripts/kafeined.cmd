@echo off
rem kafeined.cmd — thin shim so Windows users can run kafeined without Git Bash.
rem Forwards everything to kafeined.ps1 and propagates its exit code.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kafeined.ps1" %*
exit /b %ERRORLEVEL%
