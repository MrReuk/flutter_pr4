@echo off
rem Запускает анализ и тесты, весь вывод пишет в check.log рядом с проектом.
cd /d "%~dp0.."
echo === flutter pub get === > check.log
call flutter pub get >> check.log 2>&1
echo === flutter analyze === >> check.log
call flutter analyze >> check.log 2>&1
echo === flutter test === >> check.log
call flutter test --reporter expanded >> check.log 2>&1
echo === done === >> check.log
