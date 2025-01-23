FROM python:3.13

WORKDIR /opt/rdgen

COPY . .

RUN python -m venv rdgen
RUN chmod +x rdgen/bin/activate
RUN /bin/sh -c rdgen/bin/activate
RUN pip install --no-cache-dir -r requirements.txt
RUN python manage.py migrate

EXPOSE 8000

CMD ["gunicorn", "-c", "gunicorn.conf.py", "rdgen.wsgi:application"]