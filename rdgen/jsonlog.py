"""LOG_FORMAT=json: one JSON object per log line, for log collectors (Loki, Elasticsearch...)."""
import datetime
import json
import logging


class JSONFormatter(logging.Formatter):
    def format(self, record):
        line = {
            "time": datetime.datetime.fromtimestamp(record.created, datetime.timezone.utc)
            .isoformat(timespec="microseconds")
            .replace("+00:00", "Z"),
            "level": record.levelname.lower(),
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if record.exc_info:
            line["exc"] = self.formatException(record.exc_info)
        return json.dumps(line)
