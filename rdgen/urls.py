"""
URL configuration for rdgen project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
import django

from rdgenerator import views as views
if django.__version__.split('.')[0]>='4':
    from django.urls import re_path as url
else:
    from django.conf.urls import  url, include

urlpatterns = [
    url(r'^$',views.generator_view),
    url(r'^generator',views.generator_view),
    url(r'^check_for_file',views.check_for_file),
    url(r'^download',views.download),
    url(r'^creategh',views.create_github_run),
    url(r'^updategh',views.update_github_run),
    url(r'^startgh',views.startgh),
    url(r'^get_png',views.get_png),
    url(r'^save_custom_client',views.save_custom_client),
]
