# One image for every platform role: the load and refresh jobs, and the questions-site app.
#   job:  sqlcs load      (fetch, build, run, site, push to the bucket)
#   job:  sqlcs refresh   (pull, run, site, push the site)
#   app:  sqlcs serve     (default; port 8080, health /health)
FROM python:3.12-slim

WORKDIR /app
COPY pyproject.toml requirements.txt ./
COPY sqlcs ./sqlcs
COPY scripts ./scripts
COPY queries ./queries
COPY docs ./docs
RUN pip install --no-cache-dir . \
 && useradd --create-home --uid 10001 sqlcs \
 && mkdir -p data db \
 && chown -R sqlcs:sqlcs /app

USER sqlcs
ENV PYTHONUNBUFFERED=1 PORT=8080
EXPOSE 8080
ENTRYPOINT ["sqlcs"]
CMD ["serve"]
