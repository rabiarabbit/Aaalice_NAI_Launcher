@echo off
cd /d "%~dp0..\.."
"E:\flutter\bin\dart.bat" run tool\database\build_databases.dart
pause
