@echo off
rem Lance le serveur Deck en arriere-plan (fenetre cachee).
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0deck-serveur.ps1"
