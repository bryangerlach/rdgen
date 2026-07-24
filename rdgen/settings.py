"""
Django 项目 rdgen 的设置文件

由 'django-admin startproject' 使用 Django 5.0.3 自动生成。

更多信息请参阅：
https://docs.djangoproject.com/en/5.0/topics/settings/

完整设置列表及其值请参阅：
https://docs.djangoproject.com/en/5.0/ref/settings/
"""
import os
from pathlib import Path

# 像这样构建项目内部路径：BASE_DIR / 'subdir'
BASE_DIR = Path(__file__).resolve().parent.parent


# 快速开始开发设置 —— 不适合生产环境
# 参阅：https://docs.djangoproject.com/en/5.0/howto/deployment/checklist/

# 安全警告：请妥善保管生产环境中使用的密钥！
SECRET_KEY = os.environ.get('SECRET_KEY','django-insecure-!(t-!f#6g#sr%yfded9(xha)g+=!6craeez^cp+*&bz_7vdk61')
GHUSER = os.environ.get("GHUSER", '')
GHBEARER = os.environ.get("GHBEARER", '')
GENURL = os.environ.get("GENURL", '')
GHBRANCH = os.environ.get("GHBRANCH",'master')
ZIP_PASSWORD = os.environ.get("ZIP_PASSWORD",'insecure')
PROTOCOL = os.environ.get("PROTOCOL", 'https')
REPONAME = os.environ.get("REPONAME", 'rdgen')
SH_SECRET = os.environ.get('SH_SECRET', 'secret')

MEDIA_URL = '/media/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'media')


# 安全警告：生产环境中不要开启调试模式！
DEBUG_ENV = os.environ.get("DEBUG", "False")
DEBUG = DEBUG_ENV.lower() in ['true', '1', 't']

ALLOWED_HOSTS = ['*']
#CSRF_TRUSTED_ORIGINS = os.getenv('CSRF_TRUSTED_ORIGINS', '').split()

# 应用定义

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rdgenerator',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    #'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'rdgen.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'rdgen.wsgi.application'


# 数据库
# https://docs.djangoproject.com/en/5.0/ref/settings/#databases

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}


# 密码验证
# https://docs.djangoproject.com/en/5.0/ref/settings/#auth-password-validators

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]


# 国际化
# https://docs.djangoproject.com/en/5.0/topics/i18n/

LANGUAGE_CODE = 'zh-hans'

TIME_ZONE = 'UTC'

USE_I18N = True

USE_TZ = True


# 静态文件（CSS、JavaScript、图片）
# https://docs.djangoproject.com/en/5.0/howto/static-files/

STATIC_URL = 'static/'

# 默认主键字段类型
# https://docs.djangoproject.com/en/5.0/ref/settings/#default-auto-field

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

DATA_UPLOAD_MAX_MEMORY_SIZE = None
