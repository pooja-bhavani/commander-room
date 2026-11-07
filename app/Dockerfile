FROM python:3.12-slim
ARG VERSION
WORKDIR /srv
COPY ${VERSION}/server.py /srv/server.py
USER 65532:65532
EXPOSE 8080
CMD ["python", "-u", "/srv/server.py"]
