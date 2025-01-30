FROM python:3.13-alpine

WORKDIR /opt/rdgen

COPY . .

RUN pip install --no-cache-dir -r requirements.txt \
 && python manage.py migrate

EXPOSE 8000

CMD ["gunicorn", "-c", "gunicorn.conf.py", "rdgen.wsgi:application"]
