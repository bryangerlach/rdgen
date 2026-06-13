@echo off
echo Django Project Setup

REM Проверка существования виртуального окружения
if not exist ".venv\" (
    echo Creating virtual environment...
    python -m venv .venv
) else (
    echo Virtual environment already exists.
)

REM Активация виртуального окружения
call .venv\Scripts\activate

REM Проверка существования requirements.txt
if exist "requirements.txt" (
    echo Installing dependencies...
    pip install -r requirements.txt
) else (
    echo requirements.txt not found, skipping installation.
)

REM Загрузка переменных из .env файла
if exist ".env" (
    for /f "usebackq tokens=1,2 delims==" %%a in (".env") do set %%a=%%b
) else (
    echo .env file not found!
    pause
    exit
)

echo Applying migrations...
python manage.py migrate

echo Starting development server on http://0.0.0.0:8000
echo Press Ctrl+C to stop the server
python manage.py runserver 0.0.0.0:8000

pause